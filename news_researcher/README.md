# Multi-Source News Researcher

An **agentic RAG** system built on **LangGraph**. Give it a research question and it:

1. **breaks the question down** into focused sub-questions,
2. **searches several sources in parallel**: news APIs, web search and a local vector database,
3. **grades each result for relevance**, **removes duplicate stories**, and **ranks sources** by credibility, recency and how many outlets agree,
4. **checks its own coverage** and runs follow-up searches where it found too little,
5. **pulls out claims** and groups the ones that match across outlets, **flags contradictions** and **builds a timeline**,
6. writes a **report where every claim has a citation**, checks that each finding is backed by the sources it cites, and flags any sentence without a citation.

```
START → plan ─┬─ Send(sub-query × source) ─→ research_worker ─→ dedupe → reflect ─┐
              │   (parallel fan-out)              ▲  (retrieve + grade)           │ gaps?
              │                                   └──────── follow-up searches ───┤
              └─ (no sources) → dedupe                                            ▼ covered
      rank → extract_claims → detect_contradictions → build_timeline → write_report → remember → END
```

| Node | What it does |
|---|---|
| `plan` | The LLM splits the question into up to N sub-questions (facts, latest news, background, stakeholder reactions, disputed points). For each one it writes a keyword search query and picks which kinds of source to use (`news` / `web` / `vector`). |
| `research_worker` | One parallel worker per (sub-query, source) pair, sent out with LangGraph's `Send` API. It runs the search, then **grades relevance** (one batched LLM call, or a keyword + embedding score). A source that fails is logged, and the rest of the run carries on. |
| `dedupe` | First merges results with the same canonical URL. Then **semantic deduplication** merges copies of the same wire story. The most credible copy is kept and the other outlets are recorded. Independent reports of the same event are kept separate. |
| `reflect` | **Self-correction loop.** Counts the relevant stories for each sub-question. If any has too few, it writes new search queries and runs another retrieval round (`NR_MAX_ITERATIONS`). |
| `rank` | **Source ranking:** `0.45·relevance + 0.25·credibility + 0.15·recency + 0.15·corroboration`. Credibility starts from a per-domain prior (`credibility.py`), recency halves every 7 days, and corroboration counts the other outlets that ran the same story. |
| `extract_claims` | Pulls short, single-fact claims out of the top stories (one parallel LLM call per story) and groups matching claims across outlets. A claim is **corroborated** when 2 or more independent domains report it. |
| `detect_contradictions` | Pairs up related claims that come from different sources, and has the LLM judge whether each pair is a contradiction, consistent, or unrelated. The fallback rules look for different figures, opposite words (approved/rejected) and negation. Both claims in a contradiction are marked **contested**. |
| `build_timeline` | Builds a timeline from dates stated in the claims. A story with no stated date falls back to its earliest publication date, marked with `*`. Same-day events that match are merged. |
| `write_report` | The writer may use **only** the numbered sources. After writing, citations are **checked**: citations to sources that don't exist are removed, sentences without a citation are counted (the grounding score), and each key finding is **checked against the text of the sources it cites**. |
| `remember` | Saves the relevant articles to the vector DB, so later research runs can retrieve them. |

## Sources

| Source | Kind | Key needed |
|---|---|---|
| GDELT DOC 2.0 | news | no |
| Google News RSS | news | no |
| NewsAPI.org | news | `NEWSAPI_KEY` |
| Tavily | web search | `TAVILY_API_KEY` |
| Vector DB (ChromaDB, or a built-in JSONL+NumPy store) | vector | no |

To add a new source, subclass `sources.base.Source` with an async `search(query, k)` method and register it in `sources/__init__.py`.

## LLM: optional

| `NR_LLM_PROVIDER` | Behaviour |
|---|---|
| `auto` (default) | Uses Anthropic (`claude-sonnet-5-5`) when `ANTHROPIC_API_KEY` is set. Otherwise runs without an LLM. |
| `anthropic` | Uses `langchain-anthropic`. Set the model with `NR_LLM_MODEL`. |
| `ollama` | Uses a local model (`llama3.2` by default) at `NR_OLLAMA_BASE_URL`. |
| `none` | Runs the whole pipeline with rule-based fallbacks. It works offline and gives the same output every time. |

Every LLM call uses JSON-schema structured output. If a call fails (timeout, bad output, rate limit), **that node falls back to its rule-based version** and the run continues. The report's `Pipeline:` line shows which method each step used.

## Quick start

```bash
cd news_researcher
pip install -e ".[all]"            # or just -e . for the minimal, keyless setup
cp .env.example .env && export $(grep -v '^#' .env | xargs)

news-researcher sources            # show the configured sources, LLM and vector DB
news-researcher research "What is happening with EU AI Act enforcement?" -o report.md --json report.json
news-researcher ingest ./my_articles/ https://example.com/some-article   # add to the vector DB
```

See [`examples/sample_report.md`](examples/sample_report.md) for the full report format. It was generated offline from the test fixture corpus. In that run, a syndicated AP copy was merged, a $12bn vs $9bn conflict was flagged, the timeline was built, and every finding was checked.

### Python API

```python
import asyncio
from news_researcher import Settings, build_runtime, research

rt = build_runtime(Settings.from_env(max_iterations=3))
report = asyncio.run(research("Who is winning the EV price war in China?", rt))
print(report.to_markdown())
report.stats  # grounding, verified findings, contradictions, by_provider, ...
```

## Configuration

All settings are in `config.py` and can be overridden with `NR_<FIELD>` environment variables. The ones you'll use most:

| Variable | Default | Meaning |
|---|---|---|
| `NR_MAX_SUB_QUERIES` | 5 | Number of sub-questions the planner writes |
| `NR_MAX_ITERATIONS` | 2 | Maximum retrieval rounds, including reflection follow-ups |
| `NR_RESULTS_PER_SOURCE` | 8 | Results fetched per source for each sub-query |
| `NR_RELEVANCE_THRESHOLD` | 0.5 | Minimum LLM relevance grade to keep a result |
| `NR_DEDUP_THRESHOLD` | 0.9 | Similarity at which two results count as the same story. Lower it for semantic embedders. |
| `NR_EMBEDDING_PROVIDER` | hashing | `hashing` (offline) or `ollama` (`nomic-embed-text`) |
| `NR_VECTOR_BACKEND` | auto | `chroma` when installed, otherwise `local`. `none` turns the vector DB off. |
| `NR_CREDIBILITY_FILE` | – | JSON `{domain: score}` that overrides or extends the credibility priors |

## Tests

```bash
pip install -e ".[dev]" && pytest -q
```

The tests run fully offline. They use a fixture news cycle: a wire story, a syndicated copy, an independent report that corroborates it, a blog post that contradicts it, a stakeholder reaction and an off-topic story. The tests check relevance filtering, deduplication, ranking, corroboration, contradiction detection, the timeline, citation grounding, the reflection loop, LLM-planned routing, error handling and the vector DB.

## Limitations

- GDELT returns headlines only. Add NewsAPI or Tavily to get article text, and the claims and evidence checks get much better.
- The offline hashing embedder catches near-duplicates and close rewording well. It does not match true paraphrases. Use `NR_EMBEDDING_PROVIDER=ollama`, or an LLM, for real semantic matching.
- Credibility scores are rough starting values, not fact-check verdicts. Adjust them for your domain.
