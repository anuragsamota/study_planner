"""Shared data model helpers.

The planner data is a plain JSON document so that the Flutter app and this
server can exchange it losslessly. All datetimes are *naive local* ISO-8601
strings in the student's time zone (``2026-10-03T17:00:00``); the profile
carries ``utc_offset_minutes`` so the server can work out "now" for the
student even when it is deployed in a different time zone.

Document shape (see also ``app/lib/models``)::

    {
      "version": 1,
      "updated_at": "...",
      "profile":  {...},
      "subjects": [{id, name, color, difficulty, proficiency,
                    target_minutes_per_week, exam_date}],
      "tasks":    [{id, subject_id, title, type, due, priority,
                    estimated_minutes, completed_minutes, status, notes,
                    created_at}],
      "sessions": [{id, subject_id, task_id, title, start, duration_minutes,
                    status, source, focus_rating, notes}],
      "scores":   [{id, subject_id, title, score, max_score, date}]
    }
"""

from __future__ import annotations

import copy
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any

SCHEMA_VERSION = 1

TASK_TYPES = ("assignment", "project", "exam", "reading", "revision", "other")
TASK_STATUSES = ("todo", "in_progress", "done")
SESSION_STATUSES = ("planned", "completed", "skipped", "missed")
SESSION_SOURCES = ("auto", "manual", "ai")
PRIORITY_WEIGHT = {1: 1.0, 2: 2.0, 3: 3.0}  # low, medium, high

DEFAULT_PROFILE: dict[str, Any] = {
    "name": "Student",
    "daily_goal_minutes": 120,
    "session_minutes": 45,
    "break_minutes": 10,
    "max_sessions_per_day": 4,
    "preferred_time": "evening",  # morning | afternoon | evening | night
    "utc_offset_minutes": 0,
    # ISO weekday (1 = Monday) -> list of availability windows.
    "availability": {
        str(d): [{"start": "17:00", "end": "21:00"}] for d in range(1, 6)
    }
    | {"6": [{"start": "10:00", "end": "13:00"}], "7": [{"start": "15:00", "end": "18:00"}]},
}


def new_id() -> str:
    return uuid.uuid4().hex


def empty_document() -> dict[str, Any]:
    return {
        "version": SCHEMA_VERSION,
        "updated_at": iso(datetime.now()),
        "profile": copy.deepcopy(DEFAULT_PROFILE),
        "subjects": [],
        "tasks": [],
        "sessions": [],
        "scores": [],
    }


def normalize(doc: dict[str, Any] | None) -> dict[str, Any]:
    """Fill in missing keys so downstream code can rely on them."""
    base = empty_document()
    if not doc:
        return base
    out = copy.deepcopy(doc)
    for key in ("subjects", "tasks", "sessions", "scores"):
        out.setdefault(key, [])
    profile = copy.deepcopy(DEFAULT_PROFILE)
    profile.update(out.get("profile") or {})
    out["profile"] = profile
    out.setdefault("version", SCHEMA_VERSION)
    out.setdefault("updated_at", base["updated_at"])
    return out


def iso(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat()


def parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        try:
            d = date.fromisoformat(value[:10])
        except ValueError:
            return None
        dt = datetime(d.year, d.month, d.day)
    # Everything is compared as naive local time.
    return dt.replace(tzinfo=None) if dt.tzinfo else dt


def parse_due(value: str | None) -> datetime | None:
    """A bare date as a due date means "end of that day"."""
    if value and len(value) == 10:
        d = parse_dt(value)
        return d.replace(hour=23, minute=59) if d else None
    return parse_dt(value)


def student_now(doc: dict[str, Any]) -> datetime:
    offset = int((doc.get("profile") or {}).get("utc_offset_minutes") or 0)
    return (datetime.now(timezone.utc) + timedelta(minutes=offset)).replace(tzinfo=None)


def session_end(session: dict[str, Any]) -> datetime | None:
    start = parse_dt(session.get("start"))
    if start is None:
        return None
    return start + timedelta(minutes=int(session.get("duration_minutes") or 0))


def effective_status(session: dict[str, Any], now: datetime) -> str:
    """A planned session whose end has passed counts as missed."""
    status = session.get("status", "planned")
    if status == "planned":
        end = session_end(session)
        if end is not None and end <= now:
            return "missed"
    return status


def find_subject(doc: dict[str, Any], ref: str | None) -> dict[str, Any] | None:
    """Look a subject up by id or (case-insensitive) name."""
    if not ref:
        return None
    for s in doc["subjects"]:
        if s["id"] == ref:
            return s
    low = ref.strip().lower()
    for s in doc["subjects"]:
        if s["name"].strip().lower() == low:
            return s
    for s in doc["subjects"]:
        if low in s["name"].strip().lower():
            return s
    return None


def find_by_id(items: list[dict[str, Any]], item_id: str) -> dict[str, Any] | None:
    return next((i for i in items if i.get("id") == item_id), None)
