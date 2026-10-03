import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from study_planner_mcp import server  # noqa: E402
from study_planner_mcp.store import Store  # noqa: E402


@pytest.fixture(autouse=True)
def tmp_store(tmp_path, monkeypatch):
    store = Store(tmp_path / "data")
    monkeypatch.setattr(server, "store", store)
    return store
