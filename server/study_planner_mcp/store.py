"""Tiny JSON file store – one document per student."""

from __future__ import annotations

import json
import os
import re
import threading
from datetime import datetime
from pathlib import Path
from typing import Any

from .model import iso, normalize

_SAFE = re.compile(r"[^A-Za-z0-9_.-]")


class Store:
    def __init__(self, data_dir: str | os.PathLike[str]):
        self.dir = Path(data_dir)
        self.dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def _path(self, student_id: str) -> Path:
        safe = _SAFE.sub("_", student_id or "default")[:64] or "default"
        return self.dir / f"{safe}.json"

    def load(self, student_id: str) -> dict[str, Any]:
        with self._lock:
            path = self._path(student_id)
            if not path.exists():
                return normalize(None)
            return normalize(json.loads(path.read_text(encoding="utf-8")))

    def save(self, student_id: str, doc: dict[str, Any], *, touch: bool = True) -> dict[str, Any]:
        with self._lock:
            if touch:
                doc["updated_at"] = iso(datetime.now())
            path = self._path(student_id)
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")
            tmp.replace(path)
            return doc
