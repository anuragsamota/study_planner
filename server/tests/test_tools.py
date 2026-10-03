import pytest

from study_planner_mcp import server


def test_tool_roundtrip():
    server.add_subject("Maths", proficiency=2)
    task = server.add_task("Problem set 3", "maths", due="2099-01-10", priority=3, estimated_minutes=90)
    assert task["subject"] == "Maths"
    plan = server.auto_plan(days=7)
    assert plan["planned_sessions"]
    server.update_task(task["id"], status="done")
    assert server.list_tasks() == []
    server.log_study_session("Maths", 50, focus_rating=4)
    server.record_score("Maths", "Quiz", 8, 10)
    a = server.get_analytics()
    assert a["total_minutes"] == 50
    assert a["subjects"][0]["avg_score_pct"] == 0.8
    assert server.get_overview()["subjects"][0]["name"] == "Maths"


def test_unknown_subject_message():
    with pytest.raises(ValueError, match="add_subject"):
        server.add_task("x", "Biology")


def test_students_are_isolated():
    server.add_subject("Maths", student_id="alice")
    assert server.list_subjects(student_id="bob") == []


def test_sync_merges_when_server_changed():
    pushed = server.sync_push({"subjects": [{"id": "a", "name": "A"}], "updated_at": "2026-01-01T00:00:00"}, None)
    assert not pushed["merged"]
    synced_at = pushed["document"]["updated_at"]
    server.add_subject("FromAgent")  # server-side change after sync
    result = server.sync_push(
        {"subjects": [{"id": "a", "name": "A renamed"}, {"id": "b", "name": "B"}], "tombstones": []},
        synced_at.replace("T", " "),  # older than server's updated_at
    )
    names = sorted(s["name"] for s in result["document"]["subjects"])
    assert result["merged"] and names == ["A renamed", "B", "FromAgent"]
    deleted = server.sync_push({"subjects": [{"id": "b", "name": "B"}], "tombstones": ["a"]}, "0")
    assert sorted(s["name"] for s in deleted["document"]["subjects"]) == ["B", "FromAgent"]
