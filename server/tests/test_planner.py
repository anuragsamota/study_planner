from datetime import datetime, timedelta

from study_planner_mcp.analytics import strength_score, summarize
from study_planner_mcp.model import empty_document, parse_dt
from study_planner_mcp.planner import generate_plan

NOW = datetime(2026, 10, 5, 8, 0)  # Monday


def doc_with(subjects=(), tasks=(), sessions=(), scores=()):
    doc = empty_document()
    doc["subjects"] = list(subjects)
    doc["tasks"] = list(tasks)
    doc["sessions"] = list(sessions)
    doc["scores"] = list(scores)
    return doc


def subject(sid, name, proficiency=3, difficulty=3, **kw):
    return {"id": sid, "name": name, "proficiency": proficiency, "difficulty": difficulty, **kw}


def test_strength_score_renormalises_missing_signals():
    assert strength_score(proficiency=5, score_pct=None, completion_rate=None, avg_focus=None) == 1.0
    assert strength_score(proficiency=1, score_pct=1.0, completion_rate=None, avg_focus=None) == 0.40 / 0.65


def test_plan_respects_availability_and_daily_cap():
    doc = doc_with([subject("m", "Maths")])
    plan = generate_plan(doc, NOW, days=7)
    per_day = {}
    for s in plan["sessions"]:
        start = parse_dt(s["start"])
        per_day[start.date()] = per_day.get(start.date(), 0) + 1
        windows = doc["profile"]["availability"][str(start.isoweekday())]
        assert any(w["start"] <= start.strftime("%H:%M") and (start + timedelta(minutes=s["duration_minutes"])).strftime("%H:%M") <= w["end"] for w in windows)
    assert per_day and max(per_day.values()) <= doc["profile"]["max_sessions_per_day"]


def test_urgent_high_priority_task_comes_first():
    doc = doc_with(
        [subject("m", "Maths"), subject("p", "Physics")],
        tasks=[
            {"id": "t1", "subject_id": "p", "title": "Far essay", "due": "2026-10-30", "priority": 1, "estimated_minutes": 60, "status": "todo"},
            {"id": "t2", "subject_id": "m", "title": "Urgent sheet", "due": "2026-10-06", "priority": 3, "estimated_minutes": 90, "status": "todo"},
        ],
    )
    sessions = sorted(generate_plan(doc, NOW, 7)["sessions"], key=lambda s: s["start"])
    assert sessions[0]["task_id"] == "t2"
    # The urgent task is fully covered before its deadline.
    covered = sum(s["duration_minutes"] for s in sessions if s["task_id"] == "t2")
    assert covered >= 90
    assert all(parse_dt(s["start"]) < datetime(2026, 10, 6, 23, 59) for s in sessions if s["task_id"] == "t2")


def test_weak_subject_gets_more_revision_than_strong():
    doc = doc_with(
        [subject("w", "Chemistry", proficiency=1, difficulty=5), subject("s", "History", proficiency=5, difficulty=1)],
        scores=[{"id": "x", "subject_id": "w", "title": "quiz", "score": 30, "max_score": 100, "date": "2026-10-01"}],
    )
    sessions = generate_plan(doc, NOW, 7)["sessions"]
    weak = sum(s["duration_minutes"] for s in sessions if s["subject_id"] == "w")
    strong = sum(s["duration_minutes"] for s in sessions if s["subject_id"] == "s")
    assert weak > strong


def test_replan_keeps_manual_sessions_and_avoids_overlap():
    manual = {"id": "man", "subject_id": "m", "title": "Tutor", "start": "2026-10-05T17:00:00", "duration_minutes": 60, "status": "planned", "source": "manual"}
    old_auto = {"id": "old", "subject_id": "m", "title": "x", "start": "2026-10-06T17:00:00", "duration_minutes": 45, "status": "planned", "source": "auto"}
    doc = doc_with([subject("m", "Maths")], sessions=[manual, old_auto])
    plan = generate_plan(doc, NOW, 7)
    assert manual in plan["kept"] and old_auto not in plan["kept"]
    for s in plan["sessions"]:
        start = parse_dt(s["start"])
        assert not (start < datetime(2026, 10, 5, 18) and datetime(2026, 10, 5, 17) < start + timedelta(minutes=s["duration_minutes"]))


def test_at_risk_when_not_enough_time():
    doc = doc_with(
        [subject("m", "Maths")],
        tasks=[{"id": "big", "subject_id": "m", "title": "Thesis", "due": "2026-10-06", "priority": 3, "estimated_minutes": 2000, "status": "todo"}],
    )
    plan = generate_plan(doc, NOW, 7)
    assert plan["at_risk"] and plan["at_risk"][0]["task_id"] == "big"


def test_summary_streak_missed_and_levels():
    sessions = [
        {"id": str(i), "subject_id": "m", "start": f"2026-10-0{d}T18:00:00", "duration_minutes": 60, "status": "completed", "focus_rating": 5}
        for i, d in enumerate((2, 3, 4))
    ] + [{"id": "p", "subject_id": "c", "start": "2026-10-04T10:00:00", "duration_minutes": 30, "status": "planned"}]
    doc = doc_with([subject("m", "Maths", proficiency=5), subject("c", "Chem", proficiency=1)], sessions=sessions)
    s = summarize(doc, NOW)
    assert s["streak_days"] == 3
    assert s["total_minutes"] == 180
    chem = next(x for x in s["subjects"] if x["name"] == "Chem")
    assert chem["sessions_missed"] == 1 and chem["level"] == "weak"
    assert s["strong_subjects"] == ["Maths"] and s["weak_subjects"] == ["Chem"]
    assert s["best_period"] == "evening"
