"""Runtime settings, read from environment variables (prefix ``NR_``)."""

from __future__ import annotations

import os
from dataclasses import dataclass, fields


def _get(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


@dataclass
class Settings:
    # --- LLM -----------------------------------------------------------------
    # "auto" picks Anthropic when ANTHROPIC_API_KEY is set, otherwise runs the
    # deterministic heuristic pipeline (no LLM at all).
    llm_provider: str = "auto"  # auto | anthropic | ollama | none
    llm_model: str | None = None
    ollama_base_url: str = "http://localhost:11434"
    llm_concurrency: int = 4

    # --- Embeddings / vector DB ----------------------------------------------
    embedding_provider: str = "hashing"  # hashing | ollama
    embedding_model: str = "nomic-embed-text"
    vector_backend: str = "auto"  # auto | chroma | local | none
    vector_db_path: str = ".news_researcher/vectordb"
    auto_ingest: bool = True  # store relevant articles for future runs

    # --- Sources ---------------------------------------------------------------
    newsapi_key: str | None = None
    tavily_api_key: str | None = None
    enable_gdelt: bool = True
    enable_google_news: bool = True
    gdelt_timespan: str = "3months"
    news_language: str = "en"
    results_per_source: int = 8
    request_timeout: float = 20.0

    # --- Agent behaviour -------------------------------------------------------
    max_sub_queries: int = 5
    max_iterations: int = 2  # retrieval rounds (1 = no follow-up searches)
    min_docs_per_sub_query: int = 2
    relevance_threshold: float = 0.5  # LLM grader, 0..1
    heuristic_relevance_threshold: float = 0.3
    dedup_threshold: float = 0.9  # near-verbatim (syndicated) copies only
    claim_cluster_threshold: float = 0.7
    max_docs_for_claims: int = 15
    max_contradiction_pairs: int = 30
    max_report_sources: int = 20
    recency_half_life_days: float = 7.0

    @classmethod
    def from_env(cls, **overrides) -> "Settings":
        values: dict = {}
        for f in fields(cls):
            raw = _get(f"NR_{f.name.upper()}")
            if raw is None:
                continue
            kind = f.type if isinstance(f.type, str) else getattr(f.type, "__name__", "")
            if kind.startswith("bool"):
                values[f.name] = raw.lower() in ("1", "true", "yes", "on")
            elif kind.startswith("int"):
                values[f.name] = int(raw)
            elif kind.startswith("float"):
                values[f.name] = float(raw)
            else:
                values[f.name] = raw
        # Conventional key names are honoured too.
        values.setdefault("newsapi_key", _get("NEWSAPI_KEY"))
        values.setdefault("tavily_api_key", _get("TAVILY_API_KEY"))
        values.update({k: v for k, v in overrides.items() if v is not None})
        return cls(**values)
