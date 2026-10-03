"""Generate app/test/fixtures/parity.json: the Dart planner/analytics must match the Python ones.

Run from server/:  python tests/make_parity_fixture.py
"""

import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from study_planner_mcp.analytics import summarize  # noqa: E402
from study_planner_mcp.model import normalize  # noqa: E402
from study_planner_mcp.planner import generate_plan  # noqa: E402

NOW = datetime(2026, 10, 5, 8, 0)  # a Monday

DOC = normalize(
    {
        "profile": {"name": "Ada", "daily_goal_minutes": 120, "session_minutes": 45, "break_minutes": 10,
                    "max_sessions_per_day": 4, "preferred_time": "evening"},
        "subjects": [
            {"id": "math", "name": "Mathematics", "difficulty": 4, "proficiency": 2, "target_minutes_per_week": 180},
            {"id": "phys", "name": "Physics", "difficulty": 4, "proficiency": 3, "target_minutes_per_week": 120,
             "exam_date": "2026-10-14"},
            {"id": "hist", "name": "History", "difficulty": 2, "proficiency": 5, "target_minutes_per_week": 90,
             "ai_weight": 0.7},
            {"id": "chem", "name": "Chemistry", "difficulty": 3, "proficiency": 3},
        ],
        "tasks": [
            {"id": "t1", "subject_id": "math", "title": "Problem set 4", "type": "assignment", "due": "2026-10-07",
             "priority": 3, "estimated_minutes": 120, "completed_minutes": 30, "status": "in_progress"},
            {"id": "t2", "subject_id": "phys", "title": "Lab report", "type": "project", "due": "2026-10-12T09:00:00",
             "priority": 2, "estimated_minutes": 180, "completed_minutes": 0, "status": "todo"},
            {"id": "t3", "subject_id": "hist", "title": "Essay", "type": "assignment", "due": "2026-10-20",
             "priority": 1, "estimated_minutes": 90, "completed_minutes": 0, "status": "todo"},
            {"id": "t4", "subject_id": "chem", "title": "Read ch. 5", "type": "reading", "due": None,
             "priority": 2, "estimated_minutes": 60, "completed_minutes": 0, "status": "todo"},
            {"id": "t5", "subject_id": "math", "title": "Old quiz", "type": "exam", "due": "2026-10-01",
             "priority": 3, "estimated_minutes": 60, "completed_minutes": 60, "status": "done"},
        ],
        "sessions": [
            {"id": "s1", "subject_id": "math", "title": "x", "start": "2026-10-02T18:00:00", "duration_minutes": 50,
             "status": "completed", "source": "manual", "focus_rating": 2},
            {"id": "s2", "subject_id": "hist", "title": "x", "start": "2026-10-03T10:00:00", "duration_minutes": 45,
             "status": "completed", "source": "auto", "focus_rating": 5},
            {"id": "s3", "subject_id": "phys", "title": "x", "start": "2026-10-04T15:00:00", "duration_minutes": 45,
             "status": "planned", "source": "auto"},
            {"id": "s4", "subject_id": "chem", "title": "Tutor", "start": "2026-10-06T18:00:00", "duration_minutes": 60,
             "status": "planned", "source": "manual"},
            {"id": "s5", "subject_id": "math", "title": "old auto", "start": "2026-10-07T17:00:00",
             "duration_minutes": 45, "status": "planned", "source": "auto"},
        ],
        "scores": [
            {"id": "q1", "subject_id": "math", "title": "Quiz", "score": 11, "max_score": 20, "date": "2026-09-28"},
            {"id": "q2", "subject_id": "hist", "title": "Test", "score": 92, "max_score": 100, "date": "2026-09-30"},
        ],
    }
)

plan = generate_plan(DOC, NOW, 7)
summary = summarize(DOC, NOW)
out = {
    "now": NOW.isoformat(),
    "document": DOC,
    "expected_sessions": [
        {k: s[k] for k in ("start", "duration_minutes", "subject_id", "task_id", "title", "notes")} for s in plan["sessions"]
    ],
    "expected_kept_ids": sorted(s["id"] for s in plan["kept"]),
    "expected_at_risk": [r["task_id"] for r in plan["at_risk"]],
    "expected_strength": {s["subject_id"]: s["strength"] for s in summary["subjects"]},
    "expected_summary": {k: summary[k] for k in ("total_minutes", "streak_days", "week_minutes", "best_period")}
    | {"weak": summary["weak_subjects"], "strong": summary["strong_subjects"]},
}
target = Path(__file__).resolve().parents[2] / "app" / "test" / "fixtures" / "parity.json"
target.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"wrote {target} with {len(plan['sessions'])} sessions")
