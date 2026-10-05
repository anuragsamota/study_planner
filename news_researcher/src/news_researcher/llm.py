"""Thin wrapper around a LangChain chat model.

Every node calls :meth:`LLM.structured`, which returns ``None`` on any failure
so the node can fall back to its deterministic heuristic. That keeps a run
alive when the model times out, rate-limits or returns malformed output.
"""

from __future__ import annotations

import asyncio
import logging
from typing import TypeVar

from pydantic import BaseModel

from .config import Settings

log = logging.getLogger(__name__)
T = TypeVar("T", bound=BaseModel)

DEFAULT_MODELS = {"anthropic": "claude-sonnet-5-5", "ollama": "llama3.2"}


class LLM:
    def __init__(self, chat_model, name: str, concurrency: int = 4, method: str = "json_schema"):
        self.model = chat_model
        self.name = name
        self.method = method  # native JSON-schema constrained output on both providers
        self._sem = asyncio.Semaphore(concurrency)

    async def structured(self, schema: type[T], system: str, user: str) -> T | None:
        async with self._sem:
            try:
                runnable = self.model.with_structured_output(schema, method=self.method)
                result = await runnable.ainvoke([("system", system), ("human", user)])
            except Exception as exc:  # noqa: BLE001 - any provider error -> heuristic fallback
                log.warning("LLM call for %s failed: %s", schema.__name__, exc)
                return None
        if isinstance(result, dict):
            try:
                result = schema.model_validate(result)
            except Exception:  # noqa: BLE001
                return None
        return result if isinstance(result, schema) else None


def build_llm(settings: Settings) -> LLM | None:
    import os

    provider = settings.llm_provider
    if provider == "auto":
        provider = "anthropic" if os.environ.get("ANTHROPIC_API_KEY") else "none"
    if provider == "none":
        return None
    model = settings.llm_model or DEFAULT_MODELS.get(provider)
    if provider == "anthropic":
        from langchain_anthropic import ChatAnthropic

        chat = ChatAnthropic(model=model, temperature=0, max_tokens=4096, timeout=120)
    elif provider == "ollama":
        from langchain_ollama import ChatOllama

        chat = ChatOllama(model=model, base_url=settings.ollama_base_url, temperature=0)
    else:
        raise ValueError(f"Unknown LLM provider: {provider!r}")
    return LLM(chat, f"{provider}:{model}", settings.llm_concurrency)
