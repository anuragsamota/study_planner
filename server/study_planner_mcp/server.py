"""Study Planner MCP server.

Exposes a student's study data (subjects, tasks, sessions, scores, profile)
as MCP tools, resources and prompts so that any MCP host – the Flutter app's
built-in Ollama agent, Claude Desktop, an IDE, ... – can plan and analyse
studies on the student's behalf.

Every tool takes an optional ``student_id``. The Flutter app fills it in
automatically (it is hidden from the language model); stdio clients use the
``default`` student.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta
from typing import Any, Literal

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

from . import __version__
from .analytics import summarize
from .model import (
    TASK_STATUSES,
    TASK_TYPES,
    effective_status,
    find_by_id,
    find_subject,
    iso,
    new_id,
    normalize,
    parse_dt,
    parse_due,
    student_now,
)
from .planner import apply_plan
from .store import Store

INSTRUCTIONS = """\
You are connected to a student's study planner. Use these tools to look at
their subjects, tasks/deadlines, schedule and analytics, and to change their
plan. Prefer `get_overview` first to understand the student. After adding or
changing tasks, call `auto_plan` so the schedule reflects the change.
Dates use the student's local time in ISO format (YYYY-MM-DD or
YYYY-MM-DDTHH:MM). Priorities: 1 = low, 2 = medium, 3 = high.
"""

StudentId = str
MAX_TOMBSTONES = 1000

store = Store(os.environ.get("PLANNER_DATA_DIR", os.path.join(os.getcwd(), "data")))

mcp = FastMCP(
    "study-planner",
    instructions=INSTRUCTIONS,
    stateless_http=True,
    json_response=True,
    # Host-header checks are relaxed so the server is reachable over the LAN
    # and behind reverse proxies; use PLANNER_API_TOKEN to restrict access.
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)


# --------------------------------------------------------------------------- helpers


def _load(student_id: str | None) -> tuple[dict[str, Any], datetime]:
    doc = store.load(student_id or "default")
    return doc, student_now(doc)


def _save(student_id: str | None, doc: dict[str, Any]) -> None:
    store.save(student_id or "default", doc)


def _subject_or_error(doc: dict[str, Any], ref: str) -> dict[str, Any]:
    subject = find_subject(doc, ref)
    if subject is None:
        names = ", ".join(s["name"] for s in doc["subjects"]) or "none yet"
        raise ValueError(f"Unknown subject '{ref}'. Known subjects: {names}. Use add_subject first.")
    return subject


def _subject_name(doc: dict[str, Any], sid: str | None) -> str | None:
    s = find_by_id(doc["subjects"], sid) if sid else None
    return s["name"] if s else None


def _task_view(doc: dict[str, Any], t: dict[str, Any], now: datetime) -> dict[str, Any]:
    due = parse_due(t.get("due"))
    return {
        "id": t["id"],
        "title": t["title"],
        "subject": _subject_name(doc, t.get("subject_id")),
        "type": t.get("type"),
        "due": t.get("due"),
        "overdue": bool(due and due < now and t.get("status") != "done"),
        "priority": t.get("priority"),
        "status": t.get("status"),
        "estimated_minutes": t.get("estimated_minutes"),
        "completed_minutes": t.get("completed_minutes", 0),
    }


def _session_view(doc: dict[str, Any], s: dict[str, Any], now: datetime) -> dict[str, Any]:
    return {
        "id": s["id"],
        "title": s.get("title"),
        "subject": _subject_name(doc, s.get("subject_id")),
        "start": s.get("start"),
        "duration_minutes": s.get("duration_minutes"),
        "status": effective_status(s, now),
        "source": s.get("source"),
        "reason": s.get("notes"),
    }


def _norm_date(value: str | None, now: datetime) -> str | None:
    if not value:
        return None
    dt = parse_dt(value)
    if dt is None:
        raise ValueError(f"Could not understand date '{value}'. Use YYYY-MM-DD or YYYY-MM-DDTHH:MM.")
    return value[:10] if len(value) == 10 else iso(dt)


# --------------------------------------------------------------------------- read tools


@mcp.tool()
def get_overview(student_id: StudentId = "default") -> dict[str, Any]:
    """Snapshot of the student: profile, subjects with strength levels, open tasks, today's plan and key stats."""
    doc, now = _load(student_id)
    stats = summarize(doc, now)
    today = now.date().isoformat()
    open_tasks = sorted(
        (t for t in doc["tasks"] if t.get("status") != "done"),
        key=lambda t: (parse_due(t.get("due")) or datetime.max, -int(t.get("priority") or 2)),
    )
    return {
        "now": iso(now),
        "profile": {k: v for k, v in doc["profile"].items() if k != "availability"},
        "subjects": [
            {"name": s["name"], "level": s["level"], "strength": s["strength"], "minutes_last_30d": s["recent_minutes"]}
            for s in stats["subjects"]
        ],
        "open_tasks": [_task_view(doc, t, now) for t in open_tasks[:15]],
        "today": [
            _session_view(doc, s, now) for s in sorted(doc["sessions"], key=lambda s: s.get("start", "")) if (s.get("start") or "").startswith(today)
        ],
        "stats": {
            k: stats[k]
            for k in ("today_minutes", "week_minutes", "streak_days", "daily_goal_minutes", "weak_subjects", "strong_subjects", "tasks")
        },
    }


@mcp.tool()
def list_subjects(student_id: StudentId = "default") -> list[dict[str, Any]]:
    """List the student's subjects with difficulty, self-rated proficiency (1-5), weekly target and exam date."""
    doc, _ = _load(student_id)
    return doc["subjects"]


@mcp.tool()
def list_tasks(
    status: Literal["open", "done", "all"] = "open",
    subject: str | None = None,
    student_id: StudentId = "default",
) -> list[dict[str, Any]]:
    """List assignments, projects, exams and other tasks, sorted by due date."""
    doc, now = _load(student_id)
    sub = _subject_or_error(doc, subject) if subject else None
    tasks = [
        t
        for t in doc["tasks"]
        if (status == "all" or (status == "done") == (t.get("status") == "done"))
        and (sub is None or t.get("subject_id") == sub["id"])
    ]
    tasks.sort(key=lambda t: parse_due(t.get("due")) or datetime.max)
    return [_task_view(doc, t, now) for t in tasks]


@mcp.tool()
def get_schedule(start_date: str | None = None, days: int = 7, student_id: StudentId = "default") -> list[dict[str, Any]]:
    """Study sessions (planned and past) from start_date (default today) for the given number of days."""
    doc, now = _load(student_id)
    start = parse_dt(start_date) if start_date else now.replace(hour=0, minute=0, second=0, microsecond=0)
    if start is None:
        raise ValueError("start_date must be YYYY-MM-DD")
    end = start + timedelta(days=max(1, min(days, 60)))
    sessions = [s for s in doc["sessions"] if (st := parse_dt(s.get("start"))) and start <= st < end]
    sessions.sort(key=lambda s: s["start"])
    return [_session_view(doc, s, now) for s in sessions]


@mcp.tool()
def get_analytics(window_days: int = 30, student_id: StudentId = "default") -> dict[str, Any]:
    """Study analytics: time spent (total, per day, per subject), streak, goal adherence,
    strong/weak subjects with a 0-1 strength score, best time of day and rule-based recommendations."""
    doc, now = _load(student_id)
    return summarize(doc, now, max(1, min(window_days, 365)))


# --------------------------------------------------------------------------- write tools


@mcp.tool()
def add_subject(
    name: str,
    difficulty: int = 3,
    proficiency: int = 3,
    target_minutes_per_week: int = 120,
    exam_date: str | None = None,
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Add a subject. difficulty and proficiency are 1 (low) to 5 (high)."""
    doc, now = _load(student_id)
    if find_subject(doc, name) and find_subject(doc, name)["name"].lower() == name.lower():
        raise ValueError(f"Subject '{name}' already exists")
    subject = {
        "id": new_id(),
        "name": name.strip(),
        "color": 0xFF5C6BC0,
        "difficulty": _clamp(difficulty, 1, 5),
        "proficiency": _clamp(proficiency, 1, 5),
        "target_minutes_per_week": max(0, target_minutes_per_week),
        "exam_date": _norm_date(exam_date, now),
    }
    doc["subjects"].append(subject)
    _save(student_id, doc)
    return subject


@mcp.tool()
def update_subject(
    subject: str,
    difficulty: int | None = None,
    proficiency: int | None = None,
    target_minutes_per_week: int | None = None,
    exam_date: str | None = None,
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Update a subject (by name or id): difficulty/proficiency 1-5, weekly target minutes, exam date."""
    doc, now = _load(student_id)
    s = _subject_or_error(doc, subject)
    if difficulty is not None:
        s["difficulty"] = _clamp(difficulty, 1, 5)
    if proficiency is not None:
        s["proficiency"] = _clamp(proficiency, 1, 5)
    if target_minutes_per_week is not None:
        s["target_minutes_per_week"] = max(0, target_minutes_per_week)
    if exam_date is not None:
        s["exam_date"] = _norm_date(exam_date, now)
    _save(student_id, doc)
    return s


@mcp.tool()
def add_task(
    title: str,
    subject: str,
    due: str | None = None,
    type: Literal["assignment", "project", "exam", "reading", "revision", "other"] = "assignment",
    priority: int = 2,
    estimated_minutes: int = 60,
    notes: str = "",
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Add an assignment/project/exam/etc. due is a date (YYYY-MM-DD) or datetime. priority 1=low 2=medium 3=high."""
    doc, now = _load(student_id)
    sub = _subject_or_error(doc, subject)
    task = {
        "id": new_id(),
        "subject_id": sub["id"],
        "title": title.strip(),
        "type": type if type in TASK_TYPES else "other",
        "due": _norm_date(due, now),
        "priority": _clamp(priority, 1, 3),
        "estimated_minutes": max(15, estimated_minutes),
        "completed_minutes": 0,
        "status": "todo",
        "notes": notes,
        "created_at": iso(now),
    }
    doc["tasks"].append(task)
    _save(student_id, doc)
    return _task_view(doc, task, now)


@mcp.tool()
def update_task(
    task_id: str,
    title: str | None = None,
    status: Literal["todo", "in_progress", "done"] | None = None,
    due: str | None = None,
    priority: int | None = None,
    estimated_minutes: int | None = None,
    completed_minutes: int | None = None,
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Update a task by id (see list_tasks): mark done, change deadline, priority or estimate."""
    doc, now = _load(student_id)
    t = find_by_id(doc["tasks"], task_id)
    if t is None:
        raise ValueError(f"No task with id {task_id}")
    if title:
        t["title"] = title
    if status in TASK_STATUSES:
        t["status"] = status
    if due is not None:
        t["due"] = _norm_date(due, now)
    if priority is not None:
        t["priority"] = _clamp(priority, 1, 3)
    if estimated_minutes is not None:
        t["estimated_minutes"] = max(15, estimated_minutes)
    if completed_minutes is not None:
        t["completed_minutes"] = max(0, completed_minutes)
    _save(student_id, doc)
    return _task_view(doc, t, now)


@mcp.tool()
def auto_plan(days: int = 7, student_id: StudentId = "default") -> dict[str, Any]:
    """Automatically (re)plan the student's study sessions for the next `days` days, based on deadlines,
    priorities, weak subjects, exams and the student's availability. Manually scheduled sessions are kept."""
    doc, now = _load(student_id)
    plan = apply_plan(doc, now, max(1, min(days, 28)))
    _save(student_id, doc)
    return {
        "planned_sessions": [_session_view(doc, s, now) for s in plan["sessions"]],
        "at_risk_tasks": plan["at_risk"],
    }


@mcp.tool()
def schedule_session(
    subject: str,
    start: str,
    duration_minutes: int = 45,
    title: str | None = None,
    task_id: str | None = None,
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Manually schedule a study session at `start` (YYYY-MM-DDTHH:MM). Auto-planning keeps it."""
    doc, now = _load(student_id)
    sub = _subject_or_error(doc, subject)
    st = parse_dt(start)
    if st is None:
        raise ValueError("start must be YYYY-MM-DDTHH:MM")
    session = {
        "id": new_id(),
        "subject_id": sub["id"],
        "task_id": task_id,
        "title": title or f"{sub['name']} study",
        "start": iso(st),
        "duration_minutes": _clamp(duration_minutes, 5, 600),
        "status": "planned",
        "source": "ai",
        "focus_rating": None,
        "notes": "",
    }
    doc["sessions"].append(session)
    _save(student_id, doc)
    return _session_view(doc, session, now)


@mcp.tool()
def log_study_session(
    subject: str,
    minutes: int,
    focus_rating: int | None = None,
    date: str | None = None,
    task_id: str | None = None,
    notes: str = "",
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Record study the student already did. focus_rating 1-5. date defaults to now."""
    doc, now = _load(student_id)
    sub = _subject_or_error(doc, subject)
    minutes = _clamp(minutes, 1, 720)
    start = parse_dt(date) if date else now - timedelta(minutes=minutes)
    session = {
        "id": new_id(),
        "subject_id": sub["id"],
        "task_id": task_id,
        "title": f"{sub['name']} study",
        "start": iso(start or now),
        "duration_minutes": minutes,
        "status": "completed",
        "source": "manual",
        "focus_rating": _clamp(focus_rating, 1, 5) if focus_rating else None,
        "notes": notes,
    }
    doc["sessions"].append(session)
    if task_id and (t := find_by_id(doc["tasks"], task_id)):
        t["completed_minutes"] = int(t.get("completed_minutes") or 0) + minutes
        if t.get("status") == "todo":
            t["status"] = "in_progress"
    _save(student_id, doc)
    return _session_view(doc, session, now)


@mcp.tool()
def record_score(
    subject: str,
    title: str,
    score: float,
    max_score: float = 100,
    date: str | None = None,
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Record a test/quiz/assignment result. Scores feed the strength/weakness analysis."""
    doc, now = _load(student_id)
    sub = _subject_or_error(doc, subject)
    if max_score <= 0:
        raise ValueError("max_score must be positive")
    entry = {
        "id": new_id(),
        "subject_id": sub["id"],
        "title": title,
        "score": max(0.0, min(float(score), float(max_score))),
        "max_score": float(max_score),
        "date": _norm_date(date, now) or now.date().isoformat(),
    }
    doc["scores"].append(entry)
    _save(student_id, doc)
    return entry


@mcp.tool()
def update_preferences(
    daily_goal_minutes: int | None = None,
    session_minutes: int | None = None,
    break_minutes: int | None = None,
    max_sessions_per_day: int | None = None,
    preferred_time: Literal["morning", "afternoon", "evening", "night"] | None = None,
    student_id: StudentId = "default",
) -> dict[str, Any]:
    """Change study preferences used by the automatic planner."""
    doc, _ = _load(student_id)
    p = doc["profile"]
    if daily_goal_minutes is not None:
        p["daily_goal_minutes"] = _clamp(daily_goal_minutes, 0, 960)
    if session_minutes is not None:
        p["session_minutes"] = _clamp(session_minutes, 15, 180)
    if break_minutes is not None:
        p["break_minutes"] = _clamp(break_minutes, 0, 60)
    if max_sessions_per_day is not None:
        p["max_sessions_per_day"] = _clamp(max_sessions_per_day, 1, 12)
    if preferred_time is not None:
        p["preferred_time"] = preferred_time
    _save(student_id, doc)
    return {k: v for k, v in p.items() if k != "availability"}


# --------------------------------------------------------------------------- sync (used by the app, hidden from the LLM)


@mcp.tool()
def sync_push(snapshot: dict[str, Any], last_synced_at: str | None = None, student_id: StudentId = "default") -> dict[str, Any]:
    """[App internal] Upload the app's planner document. If the server copy changed since
    `last_synced_at` the two are merged (app wins on conflicts). Returns the resulting document."""
    incoming = normalize(snapshot)
    current = store.load(student_id)
    server_changed = (
        bool(current["subjects"] or current["tasks"] or current["sessions"])
        and current.get("updated_at", "") > (last_synced_at or "")
    )
    merged = _merge(current, incoming) if server_changed else incoming
    store.save(student_id, merged)
    return {"merged": server_changed, "document": merged}


@mcp.tool()
def sync_pull(student_id: StudentId = "default") -> dict[str, Any]:
    """[App internal] Download the server's planner document."""
    return store.load(student_id)


def _merge(server: dict[str, Any], app: dict[str, Any]) -> dict[str, Any]:
    tombstones = list(dict.fromkeys((server.get("tombstones") or []) + (app.get("tombstones") or [])))[-MAX_TOMBSTONES:]
    dead = set(tombstones)
    out = dict(app)
    for key in ("subjects", "tasks", "sessions", "scores"):
        by_id = {i["id"]: i for i in server.get(key, []) if i["id"] not in dead}
        by_id.update({i["id"]: i for i in app.get(key, []) if i["id"] not in dead})
        out[key] = list(by_id.values())
    out["tombstones"] = tombstones
    return out


# --------------------------------------------------------------------------- resources & prompts


@mcp.resource("planner://{student_id}/document", mime_type="application/json")
def document_resource(student_id: str) -> dict[str, Any]:
    """The full planner document for a student."""
    return store.load(student_id)


@mcp.resource("planner://{student_id}/analytics", mime_type="application/json")
def analytics_resource(student_id: str) -> dict[str, Any]:
    """Current analytics for a student."""
    doc, now = _load(student_id)
    return summarize(doc, now)


@mcp.prompt()
def weekly_review() -> str:
    """Review the past week and plan the next one."""
    return (
        "Call get_analytics and get_overview. Then give me a short, encouraging weekly review: "
        "how much I studied vs my goal, my strongest and weakest subjects, deadlines coming up. "
        "Finally call auto_plan for 7 days and summarise the new plan in a few bullet points."
    )


@mcp.prompt()
def plan_my_day() -> str:
    """What should I study today?"""
    return (
        "Call get_overview. Tell me what to study today, in order, with times, and why. "
        "If nothing is planned for today, call auto_plan first."
    )


def _clamp(value: int | float, lo: int, hi: int) -> int:
    return int(max(lo, min(hi, int(value))))


SERVER_INFO = {"name": "study-planner", "version": __version__}
