"""The skill's eval harness (skills/lowey/evals/run_evals.py): briefs, scoring, process stats, the results table."""
import importlib.util
import io
import json
import pathlib
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("run_evals", ROOT / "skills" / "lowey" / "evals" / "run_evals.py")
run_evals = importlib.util.module_from_spec(spec)
sys.modules["run_evals"] = run_evals  # dataclasses look their module up
spec.loader.exec_module(run_evals)


def check(name, result, detail=""):
    return {"name": name, "result": result, "detail": detail}


def test_the_twelve_briefs_parse():
    briefs = run_evals.parse_briefs((ROOT / "skills" / "lowey" / "evals" / "briefs.md").read_text(encoding="utf-8"))
    assert len(briefs) == 12
    by_id = {brief.id: brief for brief in briefs}
    assert by_id["vertical-short"].framing == "9:16"
    assert by_id["classroom-reveal"].voiceover == "Two plus two equals four."
    assert by_id["three-shot-story"].seconds == 12
    assert "Enigma" in by_id["night-desk"].text and "seconds" not in by_id["night-desk"].text


def test_scoring_follows_the_rubric():
    good = {"report": {"checks": [check(name, "pass") for name in ["Read", "Focus", "Frame", "Ground", "Scale", "Light", "Clutter"]]}}
    sheet = {"report": {"checks": [check("Motion", "pass")]}}
    assert run_evals.score([good, good], sheet) == {"score": 1.0, "fails": {}, "result": "pass"}
    floating = {"report": {"checks": [check("Ground", "fail", "“Lamp” floats 12 cm")] + good["report"]["checks"][:2]
                           + [check("Light", "skipped")]}}
    scored = run_evals.score([floating], None)
    assert scored["fails"] == {"Ground": "“Lamp” floats 12 cm"}
    assert scored["result"] == "fail", "a Ground fail fails the brief whatever the score"
    assert scored["score"] == round(2 / 3, 3), "skipped lines aren't counted"
    assert run_evals.score([], None)["score"] == 0


def test_process_stats():
    calls = [{"tool": "read_project", "input": {}},
             {"tool": "build", "input": {"actions": [{"do": "add", "shape": "cube", "name": "Box"}]}},
             {"tool": "find_assets", "input": {"query": "desk"}},
             {"tool": "build", "input": {"actions": [{"do": "add", "asset": "kit.office-desk"}], "dry_run": True}},
             {"tool": "commit", "input": {"proposal_id": "p"}},
             {"tool": "observe", "input": {}}]
    stats = run_evals.process(calls)
    assert stats == {"proposals": 2, "calls": 6, "kitFirst": False, "looked": True, "rounds": 1}
    assert run_evals.process(calls[2:5])["looked"] is False, "it changed the scene and never looked"


def test_table_and_rescore(tmp_path):
    folder = tmp_path / "night-desk"
    folder.mkdir()
    (folder / "observe-mid.json").write_text(json.dumps({"checks": [check("Read", "pass"), check("Clutter", "fail", "9 things")]}))
    (folder / "contact-sheet.json").write_text(json.dumps({"checks": [check("Motion", "pass")]}))
    (folder / "calls.json").write_text(json.dumps([{"tool": "find_assets", "input": {}}, {"tool": "build", "input": {"actions": []}},
                                                   {"tool": "observe", "input": {}}]))
    rows = run_evals.rescore(tmp_path)
    assert rows[0]["brief"] == "night-desk" and rows[0]["score"] == round(2 / 3, 3) and rows[0]["looked"]
    run_evals.write(tmp_path, rows)
    text = (tmp_path / "results.md").read_text(encoding="utf-8")
    assert "| night-desk | 0.67 | Clutter: 9 things |" in text
    assert "0 of 1 briefs pass" in text
    assert json.loads((tmp_path / "results.json").read_text(encoding="utf-8"))[0]["result"] == "fail"


def test_silent_voiceover_and_skill_files():
    with wave.open(io.BytesIO(run_evals.silent_wav(1.5)), "rb") as audio:
        assert audio.getnframes() == 24000 and audio.getframerate() == 16000
    assert "director loop" in run_evals.call_tool("read_skill_file", {"path": "SKILL.md"})[0]["text"]
    assert run_evals.call_tool("read_skill_file", {"path": "../../README.md"})[0]["text"].startswith("No skill file"), "stays in the skill"


def test_tools_for_the_model_are_the_sixteen_plus_reading():
    names = [tool["name"] for tool in run_evals.tool_definitions()]
    assert len(names) == 17 and names[-1] == "read_skill_file"
    assert all(tool["input_schema"].get("type") == "object" for tool in run_evals.tool_definitions())
