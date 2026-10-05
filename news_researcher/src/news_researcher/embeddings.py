"""Text embeddings used for grading, deduplication, clustering and the vector DB.

``HashingEmbedder`` is deterministic and fully offline (feature hashing over
stemmed unigrams + bigrams). It is good at near-duplicate detection, which is
most of what the pipeline needs. ``OllamaEmbedder`` gives true semantic
embeddings when a local Ollama server is available.
"""

from __future__ import annotations

import hashlib
from typing import Protocol

import numpy as np

from .config import Settings
from .text import STOPWORDS, stem, tokenize


class Embedder(Protocol):
    name: str

    def embed(self, texts: list[str]) -> np.ndarray: ...


class HashingEmbedder:
    def __init__(self, dim: int = 1024):
        self.dim = dim
        self.name = f"hashing-{dim}"

    def _vector(self, text: str) -> np.ndarray:
        vec = np.zeros(self.dim, dtype=np.float32)
        toks = [stem(t) for t in tokenize(text) if t not in STOPWORDS]
        features = [(t, 1.0) for t in toks] + [(f"{a}_{b}", 0.5) for a, b in zip(toks, toks[1:])]
        for feature, weight in features:
            h = int.from_bytes(hashlib.blake2b(feature.encode(), digest_size=8).digest(), "little")
            vec[h % self.dim] += weight if (h >> 40) & 1 else -weight
        norm = np.linalg.norm(vec)
        return vec / norm if norm else vec

    def embed(self, texts: list[str]) -> np.ndarray:
        if not texts:
            return np.zeros((0, self.dim), dtype=np.float32)
        return np.stack([self._vector(t) for t in texts])


class OllamaEmbedder:
    def __init__(self, model: str, base_url: str):
        from langchain_ollama import OllamaEmbeddings

        self._impl = OllamaEmbeddings(model=model, base_url=base_url)
        self.name = f"ollama-{model}"

    def embed(self, texts: list[str]) -> np.ndarray:
        if not texts:
            return np.zeros((0, 1), dtype=np.float32)
        vecs = np.asarray(self._impl.embed_documents(texts), dtype=np.float32)
        norms = np.linalg.norm(vecs, axis=1, keepdims=True)
        return vecs / np.where(norms == 0, 1, norms)


class CachedEmbedder:
    """Memoises embeddings; the same snippets get embedded by several nodes."""

    def __init__(self, inner: Embedder, max_items: int = 20_000):
        self.inner = inner
        self.name = inner.name
        self._cache: dict[str, np.ndarray] = {}
        self._max = max_items

    def embed(self, texts: list[str]) -> np.ndarray:
        missing = list(dict.fromkeys(t for t in texts if t not in self._cache))
        if missing:
            if len(self._cache) + len(missing) > self._max:
                self._cache.clear()
            for text, vec in zip(missing, self.inner.embed(missing)):
                self._cache[text] = vec
        if not texts:
            return self.inner.embed([])
        return np.stack([self._cache[t] for t in texts])


def cosine_matrix(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    if a.size == 0 or b.size == 0:
        return np.zeros((len(a), len(b)), dtype=np.float32)
    return a @ b.T  # inputs are L2-normalised


def build_embedder(settings: Settings) -> Embedder:
    if settings.embedding_provider == "ollama":
        inner: Embedder = OllamaEmbedder(settings.embedding_model, settings.ollama_base_url)
    else:
        inner = HashingEmbedder()
    return CachedEmbedder(inner)
