"""The LangGraph research workflow.

    START → plan ─┬─(Send × sub-query × source)→ research_worker ─→ dedupe → reflect ─┐
                  │                                   ▲                             │
                  │                                   └──── follow-up searches ─────┤
                  └─(no sources)→ dedupe                                            ▼
          rank → extract_claims → detect_contradictions → build_timeline → write_report → remember → END
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable

from langgraph.graph import END, START, StateGraph
from langgraph.types import Send

from .config import Settings
from .embeddings import build_embedder
from .llm import build_llm
from .models import Report
from .nodes.curation import dedupe, rank
from .nodes.planning import plan, reflect
from .nodes.reporting import remember, write_report
from .nodes.retrieval import research_worker
from .nodes.timeline import build_timeline
from .nodes.verification import detect_contradictions, extract_claims
from .sources import build_sources
from .sources.vector import build_vector_store
from .state import ResearchState, Runtime


def _bind(fn: Callable[..., Awaitable[dict]], rt: Runtime):
    async def node(state):
        return await fn(state, rt)

    node.__name__ = fn.__name__
    return node


def _fan_out(rt: Runtime, fallback: str):
    """Dispatch one parallel worker per (pending sub-query, matching source)."""

    def route(state: ResearchState):
        sends = [
            Send("research_worker", {"query": state["query"], "sub_query": sq, "source_name": src.name})
            for sq in state.get("pending_queries", [])
            for src in rt.sources
            if src.kind in sq.source_kinds
        ]
        return sends or fallback

    return route


def build_graph(rt: Runtime):
    g = StateGraph(ResearchState)
    for name, fn in [
        ("plan", plan),
        ("research_worker", research_worker),
        ("dedupe", dedupe),
        ("reflect", reflect),
        ("rank", rank),
        ("extract_claims", extract_claims),
        ("detect_contradictions", detect_contradictions),
        ("build_timeline", build_timeline),
        ("write_report", write_report),
        ("remember", remember),
    ]:
        g.add_node(name, _bind(fn, rt))

    g.add_edge(START, "plan")
    g.add_conditional_edges("plan", _fan_out(rt, "dedupe"), ["research_worker", "dedupe"])
    g.add_edge("research_worker", "dedupe")
    g.add_edge("dedupe", "reflect")
    g.add_conditional_edges("reflect", _fan_out(rt, "rank"), ["research_worker", "rank"])
    for a, b in [
        ("rank", "extract_claims"),
        ("extract_claims", "detect_contradictions"),
        ("detect_contradictions", "build_timeline"),
        ("build_timeline", "write_report"),
        ("write_report", "remember"),
        ("remember", END),
    ]:
        g.add_edge(a, b)
    return g.compile()


def build_runtime(settings: Settings | None = None) -> Runtime:
    settings = settings or Settings.from_env()
    embedder = build_embedder(settings)
    store = build_vector_store(settings.vector_backend, settings.vector_db_path, embedder)
    return Runtime(
        settings=settings,
        sources=build_sources(settings, store),
        embedder=embedder,
        llm=build_llm(settings),
        vector_store=store,
    )


async def research(query: str, rt: Runtime | None = None, on_step: Callable[[str, dict], None] | None = None) -> Report:
    """Run the full pipeline and return the final report."""
    rt = rt or build_runtime()
    graph = build_graph(rt)
    final: dict = {}
    async for update in graph.astream({"query": query}, stream_mode="updates", config={"recursion_limit": 100}):
        for node, delta in update.items():
            if on_step and delta:
                on_step(node, delta)
            if delta and "report" in delta:
                final = delta
    return final["report"]
