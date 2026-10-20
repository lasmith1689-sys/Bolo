"""Tests for accept_list.py. Run from the repo root:  python3 -m unittest tools/tts/test_accept_list.py

The real-data check runs when ACCEPT_OLD and ACCEPT_NEW point at the two lab results folders
(each holding results.json and summary.md), for example after
  git show origin/lab/results:run-36722519301/results.json > /tmp/run-36722519301/results.json
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import accept_list as al  # noqa: E402

CONTENT = {
    "speakers": [{"name": "A", "voice": "male"}, {"name": "B", "voice": "female"}],
    "scenes": {"s1": [{"speaker": 0, "gu": "કેમ છો?"}, {"speaker": 1, "gu": "મજામાં, આભાર."}]},
    "phrases": [
        {"id": "p1", "gu": "કેમ છો?", "scene": "s1", "line": 0},
        {"id": "p2", "gu": "મજામાં", "scene": "s1", "line": 1},  # words differ: recorded as itself
        {"id": "p3", "gu": "ઘર", "scene": "s9", "line": 0},  # no scene: female
    ],
}


def row(set_, id_, text, voice, variant, **scores):
    r = {"set": set_, "key": f"{set_}/{id_}", "id": id_, "text": text, "voice": voice, "variant": variant}
    for k, v in scores.items():
        r[k.replace("whisper", "whisper-ct2")] = v
    return r


OLD = {"recs": ["mms", "vakyansh"], "rows": [
    row("indic-c1", "a", "કેમ છો?", "male", "c1", mms_fcer=0.5, vakyansh_fcer=0.2, mms_ctx_fcer=0.9),
    row("indic-c2", "b", "કેમ છો?", "male", "c2", mms_fcer=0.5, vakyansh_fcer=0.5),
    row("indic-c1", "c", "મજામાં", "female", "c1", mms_fcer=0.4, vakyansh_fcer=0.4, mms_ctx_fcer=0.1),
    row("svara-00", "d", "ઘર", "male", "svara-label", mms_fcer=0.15, vakyansh_fcer=1.0),
    row("svara-00", "dt", "ઘર", "male", "svara-label-trim", mms_fcer=1.0, vakyansh_fcer=1.0),
    row("humans-words", "h", "અંક", "commons", "human-word", mms_fcer=0.0, vakyansh_fcer=0.5),
    row("controls", "r", "ઘર", "-", "reversed", mms_fcer=0.0, vakyansh_fcer=0.0),
]}
NEW = {"recs": ["mms", "vakyansh", "whisper-ct2"], "rows": [
    row("indic-c1", "a", "કેમ છો?", "male", "c1", mms_fcer=0.5, vakyansh_fcer=0.2, whisper_fcer=0.1),
    # vakyansh differs from the old run here: the newer value must win and be counted.
    row("indic-c2", "b", "કેમ છો?", "male", "c2", mms_fcer=0.5, vakyansh_fcer=0.1, whisper_fcer=0.6),
    row("indic-c1", "c", "મજામાં", "female", "c1", mms_fcer=0.4, vakyansh_fcer=0.4, whisper_fcer=0.9, mms_ctx_fcer=0.1),
    row("humans-words", "h", "અંક", "commons", "human-word", mms_fcer=0.0, vakyansh_fcer=0.5, whisper_fcer=0.2),
    row("controls", "r", "ઘર", "-", "reversed", mms_fcer=0.0, vakyansh_fcer=0.0, whisper_fcer=0.0),
    row("indic-nosplit", "n", "ઘર", "female", "nosplit", mms_fcer=0.3, vakyansh_fcer=0.3, whisper_fcer=0.3),
]}


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


class AcceptListTest(unittest.TestCase):
    def setUp(self):
        self.res = al.build(OLD, NEW, CONTENT, "old", "new")
        self.clips = {c["key"]: c for c in self.res["clips"]}
        self.phr = {p["id"]: p for p in self.res["phrases"]}

    def test_join_stats(self):
        j = self.res["join"]
        self.assertEqual(j["merged_rows"], 8)
        self.assertEqual(j["keys_only_in"]["old"]["keys"], ["svara-00/d", "svara-00/dt"])
        self.assertEqual(j["keys_only_in"]["old"]["by_set"], {"svara-label": 1, "svara-label-trim": 1})
        self.assertEqual(j["keys_only_in"]["new"]["keys"], ["indic-nosplit/n"])
        d = j["value_differences"]["vakyansh"]
        self.assertEqual((d["shared_clips"], d["clips_differing"], d["pass_flips"]), (5, 1, 1))
        # The old run's mms_ctx_fcer on indic-c1/a is absent from the newer row: still a difference.
        self.assertEqual(j["value_differences"]["mms"]["clips_differing"], 1)

    def test_newer_run_wins_and_old_fills_gaps(self):
        b = self.clips["indic-c2/b"]["recs"]["vakyansh"]
        self.assertEqual((b["fcer"], b["pass"], b["run"]), (0.1, True, "new"))
        d = self.clips["svara-00/d"]["recs"]
        self.assertEqual(sorted(d), ["mms", "vakyansh"])
        self.assertEqual(d["mms"]["run"], "old")
        self.assertTrue(d["mms"]["pass"])  # 0.15 is inclusive, as in lab.py
        self.assertEqual(self.clips["indic-nosplit/n"]["recs"]["mms"]["run"], "new")

    def test_threshold_and_context(self):
        c = self.clips["indic-c1/c"]
        self.assertFalse(c["recs"]["mms"]["pass"])
        self.assertTrue(c["recs"]["mms"]["ctx_pass"])
        self.assertTrue(c["passes_any"])

    def test_phrase_accept(self):
        p1 = self.phr["p1"]
        self.assertEqual(p1["voice"], "male")
        self.assertEqual(p1["accepted"], ["indic-carrier/male"])
        cand = p1["candidates"][0]
        self.assertEqual(cand["clips"], 2)  # c1 and c2 are variants of one candidate
        self.assertEqual(cand["recs_passing"], ["vakyansh", "whisper-ct2"])
        p2 = self.phr["p2"]
        self.assertEqual(p2["text"], "મજામાં")
        self.assertEqual(p2["accepted"], ["indic-carrier/female"])
        self.assertFalse(p2["candidates"][0]["accepted_without_ctx"])  # only in context
        p3 = self.phr["p3"]
        self.assertEqual(p3["voice"], "female")
        self.assertEqual(p3["accepted"], ["svara-label/male"])  # controls never count
        self.assertEqual(p3["accepted_app_voice"], [])
        self.assertEqual(self.res["phrase_totals"]["with_accepted_tts_voice"], 3)
        self.assertEqual(self.res["phrase_totals"]["with_accepted_app_voice"], 2)

    def test_counts_and_baseline(self):
        sc = self.res["set_counts"]
        self.assertEqual(sc["indic-c2"]["vakyansh"]["passed"], 1)
        self.assertNotIn("whisper-ct2", sc["svara-label"])
        self.assertIn("svara-label: no whisper-ct2 scores in either run", self.res["missing_data"])
        hb = self.res["human_baseline"]["humans-words"]
        self.assertEqual((hb["mms"]["passed"], hb["vakyansh"]["passed"], hb["whisper-ct2"]["rate"]), (1, 0, 0.0))
        self.assertEqual(self.res["human_baseline"]["humans-sentences"]["n"], 0)

    def test_summary_reconcile(self):
        good = ("| set | n | mms fCER<=0.15 / empty | vakyansh fCER<=0.15 / empty |\n|---|---|---|---|\n"
                "| controls | 1 | 1/1 / 0 | 1/1 / 0 |\n| humans-words | 1 | 1/1 / 0 | 0/1 / 0 |\n"
                "| indic-c1 | 2 | 0/2 / 0 | 0/2 / 0 |\n| indic-c2 | 1 | 0/1 / 0 | 0/1 / 0 |\n"
                "| svara-label | 1 | 1/1 / 0 | 0/1 / 0 |\n| svara-label-trim | 1 | 0/1 / 0 | 0/1 / 0 |\n")
        merged = [{"key": c["key"], "set": c["set"], "variant": c["variant"],
                   **{f"{r}_fcer": e["fcer"] for r, e in c["recs"].items()}} for c in self.res["clips"]]
        src = {(c["key"], r): e["run"] for c in self.res["clips"] for r, e in c["recs"].items()}
        lines, bad = al.reconcile("old", al.parse_summary(good), OLD["rows"], merged, self.res["recs"], src)
        self.assertEqual(bad, 0)
        # indic-c2 vakyansh: the old summary says 0/1, merged (newer) says 1/1: reported, explained.
        self.assertTrue(any("indic-c2 vakyansh" in l and "explained" in l for l in lines))
        lines, bad = al.reconcile("old", al.parse_summary(good.replace("| 1/1 / 0 | 0/1 / 0 |\n| indic", "| 0/1 / 0 | 0/1 / 0 |\n| indic")),
                                  OLD["rows"], merged, self.res["recs"], src)
        self.assertEqual(bad, 1)

    def test_malformed_input(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "r.json")
            write_json(p, {"recs": []})
            with self.assertRaises(ValueError):
                al.load(p)
        dup = {"recs": [], "rows": [OLD["rows"][0], OLD["rows"][0]]}
        with self.assertRaises(ValueError):
            al.join(dup, NEW)
        with self.assertRaises(ValueError):
            al.parse_summary("no table here")

    def test_deterministic_output(self):
        with tempfile.TemporaryDirectory() as t:
            paths = []
            for name, d in (("o", OLD), ("n", NEW), ("c", CONTENT)):
                paths.append(os.path.join(t, name + ".json"))
                write_json(paths[-1], d)
            outs = []
            for i in range(2):
                out = os.path.join(t, f"out{i}")
                al.main([paths[0], paths[1], out, "--content", paths[2]])
                outs.append([read_bytes(os.path.join(out, f)) for f in ("accept_list.json", "accept_list.md")])
            self.assertEqual(outs[0], outs[1])


@unittest.skipUnless(os.environ.get("ACCEPT_OLD") and os.environ.get("ACCEPT_NEW"), "real lab results not given")
class RealDataTest(unittest.TestCase):
    def test_real_runs_reconcile(self):
        old, new = os.environ["ACCEPT_OLD"], os.environ["ACCEPT_NEW"]
        with tempfile.TemporaryDirectory() as t:
            p = subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)), "accept_list.py"),
                                os.path.join(old, "results.json"), os.path.join(new, "results.json"), t,
                                "--check-summary", os.path.join(old, "summary.md"), os.path.join(new, "summary.md")],
                               capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            self.assertIn("reconciliation: OK", p.stdout)
            res = json.loads(read_bytes(os.path.join(t, "accept_list.json")).decode("utf-8"))
            wc = res["set_counts"]
            self.assertEqual([wc[s]["whisper-ct2"]["passed"] for s in ("indic-c1", "indic-c2", "indic-c3",
                                                                       "humans-words", "humans-sentences")],
                             [78, 82, 79, 3, 9])
            self.assertEqual(res["phrase_totals"]["phrases"], 56)


if __name__ == "__main__":
    unittest.main()
