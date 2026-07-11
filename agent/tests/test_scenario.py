from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from godot_agent.scenario import ScenarioFailure, load_scenario, run_scenario


class FakeRuntimeClient:
    def __init__(self) -> None:
        self.calls = []
        self.frames = 0
        self.flow = "title"

    def runtime_call(self, method, params=None, session_id=None, *, timeout, poll_interval):
        params = {} if params is None else dict(params)
        self.calls.append((method, params, session_id, timeout, poll_interval))
        if method == "time.set_paused":
            return {"previous": False, "paused": params["paused"]}
        if method == "gameplay.intent":
            if params["name"] == "start_match":
                self.flow = "ready"
            return {"result": {"accepted": True}}
        if method == "time.advance_physics_frames":
            self.frames += params["frames"]
            if self.frames >= 20:
                self.flow = "result"
            return {"frames": params["frames"]}
        if method == "gameplay.state":
            return {"driver_path": ".", "state": {"presentation": {"flow": self.flow}, "frames": self.frames}}
        if method == "viewport.capture":
            return {"path": params["path"], "width": 1280, "height": 720}
        raise AssertionError(method)


class ScenarioTests(unittest.TestCase):
    def test_runs_intents_waits_assertions_observations_and_capture(self):
        client = FakeRuntimeClient()
        result = run_scenario(
            client,
            {
                "name": "quick loop",
                "steps": [
                    {"intent": {"name": "start_match", "params": {"seed": 7}}},
                    {"advance": 1},
                    {"assert": {"path": "presentation.flow", "equals": "ready"}},
                    {"wait": {"path": "presentation.flow", "equals": "result", "max_frames": 30, "step_frames": 5}},
                    {"observe": "result-state"},
                    {"capture": "res://.godot/agent/captures/quick.png"},
                ],
            },
            session_id=4,
            timeout=2.0,
            poll_interval=0.001,
        )
        self.assertTrue(result["ok"])
        self.assertEqual(result["step_count"], 6)
        self.assertEqual(result["final_state"]["presentation"]["flow"], "result")
        self.assertGreaterEqual(result["steps"][3]["advanced_frames"], 19)
        self.assertTrue(all(call[2] == 4 for call in client.calls))
        self.assertEqual(client.calls[0][0], "time.set_paused")
        self.assertEqual(client.calls[-1], ("time.set_paused", {"paused": False}, 4, 2.0, 0.001))

    def test_reports_failed_assertion_with_step_number_and_restores_pause(self):
        client = FakeRuntimeClient()
        with self.assertRaisesRegex(ScenarioFailure, "step 1: assertion failed"):
            run_scenario(
                client,
                {"steps": [{"assert": {"path": "presentation.flow", "equals": "game_over"}}]},
            )
        self.assertEqual(client.calls[-1][0], "time.set_paused")
        self.assertEqual(client.calls[-1][1], {"paused": False})

    def test_rejects_ambiguous_and_oversized_steps(self):
        client = FakeRuntimeClient()
        bad_scenarios = [
            {"steps": []},
            {"steps": [{"advance": 601}]},
            {"steps": [{"intent": {"name": "x"}, "observe": True}]},
            {"steps": [{"assert": {"path": "x", "equals": 1, "not_equals": 2}}]},
        ]
        for scenario in bad_scenarios:
            with self.subTest(scenario=scenario), self.assertRaises(ScenarioFailure):
                run_scenario(client, scenario)

    def test_loads_json_and_rejects_non_object(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "scenario.json"
            path.write_text('{"name":"sample","steps":[{"observe":true}]}', encoding="utf-8")
            self.assertEqual(load_scenario(path)["name"], "sample")
            path.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(ScenarioFailure, "JSON object"):
                load_scenario(path)


if __name__ == "__main__":
    unittest.main()

