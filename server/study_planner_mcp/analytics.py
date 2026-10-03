"""Study analytics: time spent, strengths/weaknesses and habits.

Mirrored by ``app/lib/services/analytics.dart`` – keep both in sync.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta
from typing import Any

from .model import effective_status, parse_dt, parse_due

STRONG_THRESHOLD = 0.70
WEAK_THRESHOLD = 0.50


def time_period(hour: int) -> str:
    if 5 <= hour < 12:
        return "morning"
    if 12 <= hour < 17:
        return "afternoon"
    if 17 <= hour < 21:
        return "evening"
    return "night"


def strength_score(
    *,
    proficiency: float,
    score_pct: float | None,
    completion_rate: float | None,
    avg_focus: float | None,
) -> float:
    """Weighted 0..1 mastery estimate; missing signals are re-normalised away."""
    parts: list[tuple[float, float]] = [(0.25, (proficiency - 1) / 4)]
    if score_pct is not None:
        parts.append((0.40, score_pct))
    if completion_rate is not None:
        parts.append((0.20, completion_rate))
    if avg_focus is not None:
        parts.append((0.15, (avg_focus - 1) / 4))
    total_w = sum(w for w, _ in parts)
    return max(0.0, min(1.0, sum(w * v for w, v in parts) / total_w))


def level_for(strength: float) -> str:
    if strength >= STRONG_THRESHOLD:
        return "strong"
    if strength < WEAK_THRESHOLD:
        return "weak"
    return "average"


def subject_stats(doc: dict[str, Any], now: datetime, window_days: int = 30) -> list[dict[str, Any]]:
    window_start = now - timedelta(days=window_days)
    out = []
    for subject in doc["subjects"]:
        sid = subject["id"]
        total = recent = completed = missed = 0
        focus: list[int] = []
        for s in doc["sessions"]:
            if s.get("subject_id") != sid:
                continue
            status = effective_status(s, now)
            start = parse_dt(s.get("start"))
            if status == "completed":
                completed += 1
                minutes = int(s.get("duration_minutes") or 0)
                total += minutes
                if start and start >= window_start:
                    recent += minutes
                if s.get("focus_rating"):
                    focus.append(int(s["focus_rating"]))
            elif status in ("missed", "skipped"):
                missed += 1
        scores = [
            sc["score"] / sc["max_score"]
            for sc in doc["scores"]
            if sc.get("subject_id") == sid and sc.get("max_score")
        ]
        score_pct = sum(scores) / len(scores) if scores else None
        completion = completed / (completed + missed) if (completed + missed) else None
        avg_focus = sum(focus) / len(focus) if focus else None
        strength = strength_score(
            proficiency=float(subject.get("proficiency") or 3),
            score_pct=score_pct,
            completion_rate=completion,
            avg_focus=avg_focus,
        )
        out.append(
            {
                "subject_id": sid,
                "name": subject["name"],
                "total_minutes": total,
                "recent_minutes": recent,
                "sessions_completed": completed,
                "sessions_missed": missed,
                "completion_rate": _round(completion),
                "avg_focus": _round(avg_focus),
                "avg_score_pct": _round(score_pct),
                "proficiency": subject.get("proficiency", 3),
                "difficulty": subject.get("difficulty", 3),
                "strength": round(strength, 3),
                "level": level_for(strength),
            }
        )
    return out


def summarize(doc: dict[str, Any], now: datetime, window_days: int = 30) -> dict[str, Any]:
    subjects = subject_stats(doc, now, window_days)
    today = now.date()

    daily: dict[str, int] = defaultdict(int)
    period_focus: dict[str, list[int]] = defaultdict(list)
    period_minutes: dict[str, int] = defaultdict(int)
    total_minutes = 0
    for s in doc["sessions"]:
        if effective_status(s, now) != "completed":
            continue
        start = parse_dt(s.get("start"))
        if not start:
            continue
        minutes = int(s.get("duration_minutes") or 0)
        total_minutes += minutes
        daily[start.date().isoformat()] += minutes
        period = time_period(start.hour)
        period_minutes[period] += minutes
        if s.get("focus_rating"):
            period_focus[period].append(int(s["focus_rating"]))

    series = [
        {"date": (today - timedelta(days=i)).isoformat(), "minutes": daily.get((today - timedelta(days=i)).isoformat(), 0)}
        for i in range(13, -1, -1)
    ]
    window_minutes = sum(m for d, m in daily.items() if d >= (today - timedelta(days=window_days - 1)).isoformat())

    # Streak: consecutive days with study, counting back from today (or
    # yesterday when nothing has been done yet today).
    streak = 0
    cursor = today if daily.get(today.isoformat()) else today - timedelta(days=1)
    while daily.get(cursor.isoformat()):
        streak += 1
        cursor -= timedelta(days=1)

    goal = int(doc["profile"].get("daily_goal_minutes") or 0)
    last7 = [daily.get((today - timedelta(days=i)).isoformat(), 0) for i in range(7)]
    goal_days = sum(1 for m in last7 if goal and m >= goal)

    open_tasks = [t for t in doc["tasks"] if t.get("status") != "done"]
    overdue = [t for t in open_tasks if (d := parse_due(t.get("due"))) and d < now]
    due_week = [t for t in open_tasks if (d := parse_due(t.get("due"))) and now <= d <= now + timedelta(days=7)]

    best_period = None
    if period_focus:
        best_period = max(period_focus, key=lambda p: sum(period_focus[p]) / len(period_focus[p]))
    elif period_minutes:
        best_period = max(period_minutes, key=period_minutes.get)

    ranked = sorted(subjects, key=lambda s: s["strength"])
    result = {
        "generated_at": now.replace(microsecond=0).isoformat(),
        "window_days": window_days,
        "total_minutes": total_minutes,
        "window_minutes": window_minutes,
        "avg_daily_minutes": round(window_minutes / window_days, 1),
        "today_minutes": daily.get(today.isoformat(), 0),
        "week_minutes": sum(last7),
        "daily_goal_minutes": goal,
        "goal_days_last_7": goal_days,
        "streak_days": streak,
        "daily_series": series,
        "minutes_by_period": dict(period_minutes),
        "best_period": best_period,
        "tasks": {
            "open": len(open_tasks),
            "done": len(doc["tasks"]) - len(open_tasks),
            "overdue": len(overdue),
            "due_this_week": len(due_week),
        },
        "subjects": subjects,
        "weak_subjects": [s["name"] for s in ranked if s["level"] == "weak"],
        "strong_subjects": [s["name"] for s in reversed(ranked) if s["level"] == "strong"],
    }
    result["recommendations"] = recommendations(result, doc)
    return result


def recommendations(summary: dict[str, Any], doc: dict[str, Any]) -> list[str]:
    """Plain rule-based tips – always available, no AI required."""
    tips: list[str] = []
    if summary["tasks"]["overdue"]:
        tips.append(
            f"You have {summary['tasks']['overdue']} overdue task(s). Tackle them first or re-plan their deadlines."
        )
    for name in summary["weak_subjects"][:2]:
        tips.append(f"{name} looks like a weak area – the planner gives it extra practice sessions.")
    has_history = summary["total_minutes"] > 0
    goal = summary["daily_goal_minutes"]
    if has_history and goal and summary["goal_days_last_7"] < 4:
        tips.append(
            f"You met your {goal}-minute daily goal on {summary['goal_days_last_7']} of the last 7 days. "
            "Shorter, more frequent sessions can help build the habit."
        )
    if summary["best_period"] and summary["best_period"] != doc["profile"].get("preferred_time"):
        tips.append(
            f"You focus best in the {summary['best_period']}. Consider making it your preferred study time."
        )
    neglected = [s["name"] for s in summary["subjects"] if s["recent_minutes"] == 0]
    if has_history and neglected:
        tips.append("Not studied recently: " + ", ".join(neglected[:3]) + ".")
    if summary["streak_days"] >= 3:
        tips.append(f"{summary['streak_days']}-day streak – keep it going!")
    if not tips:
        tips.append(
            "You're on track. Keep following your plan."
            if has_history
            else "Start your first session from the plan – your progress and insights will appear here."
        )
    return tips


def _round(value: float | None) -> float | None:
    return None if value is None else round(value, 3)
