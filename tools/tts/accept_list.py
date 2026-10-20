"""Accept list: which recorded voices are heard correctly, per course phrase.

Joins two lab result files (results.json from the lab/results branch) by clip key, takes each
recognizer's columns from the run that has them (the newer run wins when both do), and decides per
clip and per phrase whether the audio passes the recognizer round trip.

A clip passes a recognizer when its fCER (the `<rec>_fcer` column: CER after folding vowel length
and nasal marks) is <= 0.15, the same column and threshold lab.py's summary.md uses. A clip that was
also scored right after the voice's context sentence passes "in context" when `<rec>_ctx_fcer` <=
0.15. A phrase is accepted for a candidate (family of sets, voice) when at least one of its clips in
that candidate passes at least one recognizer, plain or in context.

  python3 -I tools/tts/accept_list.py OLD/results.json NEW/results.json OUT_DIR \
      [--content content.json] [--check-summary OLD/summary.md NEW/summary.md]

OLD is the run whose MMS and Vakyansh columns cover every set (run 36722519301), NEW the run with
the whisper-ct2 columns (run 39361763954). Standard library only, no network. Writes
OUT_DIR/accept_list.json and OUT_DIR/accept_list.md; the same inputs give byte-identical files.
With --check-summary it also recounts every set and compares with both summary.md files and exits
with status 1 on a mismatch it cannot explain.
"""
import argparse
import json
import os
import re
import sys

THRESHOLD = 0.15
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CONTENT = os.path.join(ROOT, "Packages/BoloKit/Sources/BoloKit/Resources/content.json")
PUNCT = "?!.,"  # as in synthesize.py
NOT_TTS = {"context", "controls", "humans-words", "humans-sentences"}
HUMANS = ("humans-words", "humans-sentences")
FIELDS = ("heard", "cer", "fcer", "ctx_heard", "ctx_fcer")


# ---------------------------------------------------------------------------------------------
def load(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if not isinstance(d, dict) or not isinstance(d.get("rows"), list):
        raise ValueError(f"{path}: expected {{'recs': [...], 'rows': [...]}}")
    return d


def recs_of(data):
    """Recognizers that have transcript columns (utmos is a quality score, not a recognizer)."""
    found = set()
    for row in data["rows"]:
        for k in row:
            if k.endswith("_fcer") and not k.endswith("_ctx_fcer"):
                found.add(k[:-len("_fcer")])
    return sorted(found)


def group_of(row):
    """The summary.md grouping: Svara shards (svara-00, svara-01, ...) are grouped by variant."""
    return row["variant"] if re.fullmatch(r"svara-\d+", row["set"]) else row["set"]


def family_of(row):
    """Candidate voice source a phrase could be shipped from. The three carrier cuts are variants of
    one candidate, as are a Svara take and its trimmed version."""
    s = row["set"]
    if re.fullmatch(r"indic-c\d+", s):
        return "indic-carrier"
    if re.fullmatch(r"svara-\d+", s):
        v = row["variant"]
        return v[:-len("-trim")] if v.endswith("-trim") else v
    return s


def words(text):
    return [w.strip(PUNCT) for w in text.split() if w.strip(PUNCT)]


def phrase_requests(content):
    """Course phrase -> (app voice, the text that is recorded for it), as synthesize.requests()."""
    speakers = content["speakers"]
    voice = lambda sp: speakers[sp]["voice"] if 0 <= sp < len(speakers) else "female"
    out = []
    for p in content["phrases"]:
        lines = content["scenes"].get(p["scene"], [])
        if 0 <= p["line"] < len(lines):
            line = lines[p["line"]]
            text = line["gu"] if words(line["gu"]) == words(p["gu"]) else p["gu"]
            out.append({"id": p["id"], "gu": p["gu"], "en": p.get("en", ""), "voice": voice(line["speaker"]),
                        "text": text})
        else:
            out.append({"id": p["id"], "gu": p["gu"], "en": p.get("en", ""), "voice": "female", "text": p["gu"]})
    return out


# ---------------------------------------------------------------------------------------------
def join(old, new, old_name="old", new_name="new"):
    """Merges the two runs by key. Returns (rows by key, rec -> source run per key, join stats)."""
    old_rows = {r["key"]: r for r in old["rows"]}
    new_rows = {r["key"]: r for r in new["rows"]}
    for name, d, m in ((old_name, old, old_rows), (new_name, new, new_rows)):
        if len(m) != len(d["rows"]):
            raise ValueError(f"{name}: duplicate keys")
    old_recs, new_recs = recs_of(old), recs_of(new)
    recs = sorted(set(old_recs) | set(new_recs))
    merged, source = {}, {}
    diffs = {r: {"shared_clips": 0, "clips_differing": 0, "fields_differing": 0, "pass_flips": 0,
                 "ctx_pass_flips": 0} for r in recs}
    for k in sorted(set(old_rows) | set(new_rows)):
        o, n = old_rows.get(k), new_rows.get(k)
        base = dict(n if n is not None else o)
        for r in recs:
            for f in FIELDS:
                base.pop(f"{r}_{f}", None)
            in_o = o is not None and f"{r}_fcer" in o
            in_n = n is not None and f"{r}_fcer" in n
            pick = n if in_n else o if in_o else None
            if pick is None:
                continue
            for f in FIELDS:
                if f"{r}_{f}" in pick:
                    base[f"{r}_{f}"] = pick[f"{r}_{f}"]
            source[(k, r)] = new_name if in_n else old_name
            if in_o and in_n:
                d = diffs[r]
                d["shared_clips"] += 1
                nf = sum(1 for f in FIELDS if o.get(f"{r}_{f}") != n.get(f"{r}_{f}"))
                d["fields_differing"] += nf
                d["clips_differing"] += 1 if nf else 0
                d["pass_flips"] += (o[f"{r}_fcer"] <= THRESHOLD) != (n[f"{r}_fcer"] <= THRESHOLD)
                if f"{r}_ctx_fcer" in o and f"{r}_ctx_fcer" in n:
                    d["ctx_pass_flips"] += (o[f"{r}_ctx_fcer"] <= THRESHOLD) != (n[f"{r}_ctx_fcer"] <= THRESHOLD)
        merged[k] = base
    only_old = sorted(set(old_rows) - set(new_rows))
    only_new = sorted(set(new_rows) - set(old_rows))

    def by_group(keys, rows):
        out = {}
        for k in keys:
            g = group_of(rows[k])
            out[g] = out.get(g, 0) + 1
        return dict(sorted(out.items()))

    stats = {
        "runs": {old_name: {"rows": len(old_rows), "recs": old_recs},
                 new_name: {"rows": len(new_rows), "recs": new_recs}},
        "merged_rows": len(merged),
        "keys_only_in": {old_name: {"count": len(only_old), "by_set": by_group(only_old, old_rows), "keys": only_old},
                         new_name: {"count": len(only_new), "by_set": by_group(only_new, new_rows), "keys": only_new}},
        "value_differences": diffs,
    }
    return merged, source, recs, stats


def clip_record(row, recs, source):
    rec = {"key": row["key"], "set": row["set"], "group": group_of(row), "family": family_of(row),
           "voice": row.get("voice"), "variant": row.get("variant"), "text": row["text"], "recs": {}}
    for r in recs:
        if f"{r}_fcer" not in row:
            continue
        e = {"fcer": row[f"{r}_fcer"], "pass": row[f"{r}_fcer"] <= THRESHOLD, "run": source[(row["key"], r)]}
        if f"{r}_ctx_fcer" in row:
            e["ctx_fcer"] = row[f"{r}_ctx_fcer"]
            e["ctx_pass"] = row[f"{r}_ctx_fcer"] <= THRESHOLD
        rec["recs"][r] = e
    rec["passes_any"] = any(e["pass"] or e.get("ctx_pass", False) for e in rec["recs"].values())
    return rec


def set_counts(rows, recs):
    """group -> {"n": clips, rec: [passed, scored]} using the summary's rule (plain fCER only)."""
    out = {}
    for row in rows:
        g = out.setdefault(group_of(row), {"n": 0})
        g["n"] += 1
        for r in recs:
            if f"{r}_fcer" in row:
                c = g.setdefault(r, [0, 0])
                c[1] += 1
                c[0] += row[f"{r}_fcer"] <= THRESHOLD
    return dict(sorted(out.items()))


def phrases(content, clips):
    by_text = {}
    for c in clips:
        if c["set"] not in NOT_TTS:
            by_text.setdefault(c["text"], []).append(c)
    out = []
    for p in phrase_requests(content):
        cands = {}
        for c in by_text.get(p["text"], []):
            cand = cands.setdefault((c["family"], c["voice"]), {"family": c["family"], "voice": c["voice"],
                                                                "clips": 0, "evidence": []})
            cand["clips"] += 1
            for r, e in sorted(c["recs"].items()):
                if e["pass"]:
                    cand["evidence"].append({"key": c["key"], "variant": c["variant"], "rec": r, "ctx": False,
                                             "fcer": e["fcer"]})
                if e.get("ctx_pass"):
                    cand["evidence"].append({"key": c["key"], "variant": c["variant"], "rec": r, "ctx": True,
                                             "fcer": e["ctx_fcer"]})
        cl = []
        for _, cand in sorted(cands.items()):
            cand["accepted"] = bool(cand["evidence"])
            cand["accepted_without_ctx"] = any(not e["ctx"] for e in cand["evidence"])
            cand["recs_passing"] = sorted({e["rec"] for e in cand["evidence"]})
            cand["evidence"].sort(key=lambda e: (e["key"], e["rec"], e["ctx"]))
            cl.append(cand)
        out.append({**p, "candidates": cl,
                    "accepted": sorted(f"{c['family']}/{c['voice']}" for c in cl if c["accepted"]),
                    "accepted_app_voice": sorted(f"{c['family']}/{c['voice']}" for c in cl
                                                 if c["accepted"] and c["voice"] == p["voice"])})
    return out


def human_baseline(rows, recs):
    out = {}
    for s in HUMANS:
        rs = [r for r in rows if r["set"] == s]
        out[s] = {"n": len(rs)}
        for r in recs:
            got = [x for x in rs if f"{r}_fcer" in x]
            ok = sum(1 for x in got if x[f"{r}_fcer"] <= THRESHOLD)
            out[s][r] = {"passed": ok, "scored": len(got), "rate": round(ok / len(got), 3) if got else None}
    return out


# ---------------------------------------------------------------------------------------------
def parse_summary(text):
    """summary.md table -> {group: {"n": int, rec: [passed, scored]}}."""
    lines = [l for l in text.splitlines() if l.startswith("|")]
    if len(lines) < 2:
        raise ValueError("summary.md: no table")
    head = [c.strip() for c in lines[0].strip("|").split("|")]
    recs = []
    for h in head[2:]:
        m = re.fullmatch(r"(\S+) fCER<=0\.15 / empty", h)
        if not m:
            raise ValueError(f"summary.md: unexpected column {h!r}")
        recs.append(m.group(1))
    out = {}
    for l in lines[2:]:
        cells = [c.strip() for c in l.strip("|").split("|")]
        g = {"n": int(cells[1])}
        for r, c in zip(recs, cells[2:]):
            m = re.fullmatch(r"(\d+)/(\d+) / \d+", c)
            if not m:
                raise ValueError(f"summary.md: unexpected cell {c!r}")
            g[r] = [int(m.group(1)), int(m.group(2))]
        out[cells[0]] = g
    return out


def reconcile(name, summary, run_rows, merged_rows, recs, source):
    """Compares a run's summary.md with (a) that run's own rows and (b) the merged accept data for
    every recognizer whose merged value came from this run. Returns (lines, unexplained mismatches)."""
    lines, bad = [], 0
    own = set_counts(run_rows, recs)
    mine = [r for r in merged_rows if r["key"] in {x["key"] for x in run_rows}]
    merged = set_counts(mine, recs)
    for g in sorted(set(summary) | set(own)):
        s, o, m = summary.get(g), own.get(g), merged.get(g)
        for r in ["n"] + recs:
            sv = s.get(r) if s else None
            if sv is None:
                if o and o.get(r):
                    lines.append(f"{name} {g} {r}: missing from summary.md, data has {o[r][0]}/{o[r][1]}")
                    bad += 1
                continue
            ov = o.get(r) if o else None
            mv = m.get(r) if m else None
            status = "ok" if sv == ov == mv else "MISMATCH"
            note = ""
            if sv == ov and mv != sv:
                srcs = sorted({source.get((x["key"], r)) for x in mine if group_of(x) == g} - {None})
                note = f" (merged values come from {', '.join(srcs)}; this run's own rows reconcile)"
                status = "explained"
            elif sv != ov:
                bad += 1
            fmt = lambda v: "-" if v is None else str(v) if r == "n" else f"{v[0]}/{v[1]}"
            lines.append(f"{name} {g} {r}: summary {fmt(sv)} | run rows {fmt(ov)} | merged {fmt(mv)} -> {status}{note}")
    return lines, bad


# ---------------------------------------------------------------------------------------------
def build(old, new, content, old_name, new_name):
    merged, source, recs, stats = join(old, new, old_name, new_name)
    rows = [merged[k] for k in sorted(merged)]
    clips = [clip_record(r, recs, source) for r in rows]
    ph = phrases(content, clips)
    counts = set_counts(rows, recs)
    with_src = {}
    for g, c in counts.items():
        e = {"n": c["n"]}
        for r in recs:
            if r in c:
                srcs = sorted({source[(x["key"], r)] for x in rows if group_of(x) == g and (x["key"], r) in source})
                e[r] = {"passed": c[r][0], "scored": c[r][1], "runs": srcs}
        with_src[g] = e
    tts_accepted = [p for p in ph if p["accepted"]]
    app_accepted = [p for p in ph if p["accepted_app_voice"]]
    missing = []
    for g, e in with_src.items():
        for r in recs:
            if r not in e:
                missing.append(f"{g}: no {r} scores in either run")
            elif e[r]["scored"] < e["n"]:
                missing.append(f"{g}: {r} scored {e[r]['scored']} of {e['n']} clips")
    no_clip = [p["id"] for p in ph if not p["candidates"]]
    result = {
        "threshold": THRESHOLD,
        "rule": "clip passes a recognizer when <rec>_fcer <= 0.15 (in context: <rec>_ctx_fcer <= 0.15); phrase "
                "accepted for a candidate (family, voice) when any of its clips passes any recognizer, plain or "
                "in context",
        "inputs": {old_name: "older run (MMS/Vakyansh for all sets)", new_name: "newer run (whisper-ct2)"},
        "recs": recs,
        "join": stats,
        "set_counts": with_src,
        "human_baseline": human_baseline(rows, recs),
        "phrase_totals": {"phrases": len(ph), "with_accepted_tts_voice": len(tts_accepted),
                          "with_accepted_app_voice": len(app_accepted), "without_any_clip": no_clip},
        "missing_data": missing,
        "phrases": ph,
        "clips": clips,
    }
    return result


def dumps(obj):
    return json.dumps(obj, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def markdown(res):
    recs = res["recs"]
    j = res["join"]
    names = sorted(j["runs"])
    out = ["# Accept list", "",
           "A clip passes a recognizer when its fCER (CER after folding vowel length and nasal marks) is <= 0.15, "
           "the rule of lab.py's summary.md. A phrase is accepted for a voice when at least one of its clips "
           "(any carrier cut, take or trim) passes at least one recognizer, heard alone or right after the "
           "context sentence. Recognizer round trip only: this says nothing about how natural a clip sounds.", "",
           "## Inputs", ""]
    for n in names:
        r = j["runs"][n]
        o = j["keys_only_in"][n]
        out.append(f"- {n}: {r['rows']} rows, recognizers {', '.join(r['recs'])}; {o['count']} keys only in this run"
                   + (" (" + ", ".join(f"{g} {c}" for g, c in o["by_set"].items()) + ")" if o["count"] else ""))
    out.append(f"- merged: {j['merged_rows']} clips. Where both runs scored a clip, the newer run's values are used.")
    for r, d in sorted(j["value_differences"].items()):
        if d["shared_clips"]:
            out.append(f"- {r}: {d['shared_clips']} clips scored in both runs, {d['clips_differing']} differ "
                       f"({d['fields_differing']} fields), {d['pass_flips']} pass/fail flips, "
                       f"{d['ctx_pass_flips']} in-context flips")
    out += ["", "## Clips passing per set (plain fCER <= 0.15)", "",
            "| set | n | " + " | ".join(recs) + " |", "|---|---|" + "---|" * len(recs)]
    for g, e in res["set_counts"].items():
        cells = [f"{e[r]['passed']}/{e[r]['scored']}" if r in e else "-" for r in recs]
        out.append(f"| {g} | {e['n']} | " + " | ".join(cells) + " |")
    out += ["", "## Human baseline", "", "Real Gujarati speech through the same recognizers.", "",
            "| set | n | " + " | ".join(recs) + " |", "|---|---|" + "---|" * len(recs)]
    for s, e in res["human_baseline"].items():
        cells = [f"{e[r]['passed']}/{e[r]['scored']} ({e[r]['rate']:.0%})" if e[r]["scored"] else "-" for r in recs]
        out.append(f"| {s} | {e['n']} | " + " | ".join(cells) + " |")
    t = res["phrase_totals"]
    out += ["", "## Phrases", "",
            f"{t['with_accepted_tts_voice']} of {t['phrases']} phrases have at least one accepted synthetic voice; "
            f"{t['with_accepted_app_voice']} have one in the voice the app uses for that phrase.", "",
            "Candidates are written family/voice with the recognizers that passed it; * marks a candidate that "
            "passed only in context.", "",
            "| id | phrase | app voice | accepted | not accepted |", "|---|---|---|---|---|"]
    for p in res["phrases"]:
        acc = [f"{c['family']}/{c['voice']} ({', '.join(c['recs_passing'])})" + ("" if c["accepted_without_ctx"] else "*")
               for c in p["candidates"] if c["accepted"]]
        rej = [f"{c['family']}/{c['voice']}" for c in p["candidates"] if not c["accepted"]]
        out.append(f"| {p['id']} | {p['text']} | {p['voice']} | {'; '.join(acc) or 'none'} | {'; '.join(rej) or '-'} |")
    out += ["", "## Missing data", ""]
    out += [f"- {m}" for m in res["missing_data"]] or ["- none"]
    if t["without_any_clip"]:
        out.append("- phrases with no clip in either run: " + ", ".join(t["without_any_clip"]))
    out += ["- Human recordings have no in-context scores (only the male/female TTS voices have a context sentence).",
            "- Pass counts here use the plain fCER, like summary.md; the in-context scores only widen the phrase "
            "accept decision.", ""]
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("old", help="older results.json (MMS and Vakyansh for all sets)")
    ap.add_argument("new", help="newer results.json (whisper-ct2)")
    ap.add_argument("out", help="output directory")
    ap.add_argument("--content", default=CONTENT, help="course content.json (phrase list)")
    ap.add_argument("--old-name", default=None, help="label for the older run (default: its folder name)")
    ap.add_argument("--new-name", default=None, help="label for the newer run (default: its folder name)")
    ap.add_argument("--check-summary", nargs=2, metavar=("OLD_SUMMARY", "NEW_SUMMARY"))
    a = ap.parse_args(argv)
    label = lambda p, given: given or os.path.basename(os.path.dirname(os.path.abspath(p))) or p
    old_name, new_name = label(a.old, a.old_name), label(a.new, a.new_name)
    if old_name == new_name:
        old_name, new_name = "old", "new"
    old, new = load(a.old), load(a.new)
    with open(a.content, encoding="utf-8") as f:
        content = json.load(f)
    res = build(old, new, content, old_name, new_name)
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "accept_list.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(dumps(res))
    with open(os.path.join(a.out, "accept_list.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(markdown(res))
    t = res["phrase_totals"]
    print(f"{res['join']['merged_rows']} clips, {t['with_accepted_tts_voice']}/{t['phrases']} phrases with an "
          f"accepted voice -> {a.out}")
    if a.check_summary:
        merged = [c for c in res["clips"]]
        rows = {}
        for c in merged:
            r = {"key": c["key"], "set": c["set"], "variant": c["variant"]}
            for rec, e in c["recs"].items():
                r[f"{rec}_fcer"] = e["fcer"]
            rows[c["key"]] = r
        bad = 0
        for name, data, path in ((old_name, old, a.check_summary[0]), (new_name, new, a.check_summary[1])):
            with open(path, encoding="utf-8") as f:
                summary = parse_summary(f.read())
            lines, b = reconcile(name, summary, data["rows"], [rows[k] for k in sorted(rows)], res["recs"],
                                 {(c["key"], rec): e["run"] for c in merged for rec, e in c["recs"].items()})
            print("\n".join(lines))
            bad += b
        print(f"reconciliation: {'OK' if not bad else f'{bad} unexplained mismatches'}")
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
