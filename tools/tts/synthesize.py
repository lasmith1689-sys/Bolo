"""Generates Bolo's recorded Gujarati clips. Run by .github/workflows/audio.yml on Ubuntu runners.

  synthesize.py plan      [--shards N] [--force]   which clips are missing or stale, split into shards
  synthesize.py generate  --shard I                synthesize one shard to WAV (best of --candidates)
  synthesize.py finalize                           trim, normalise, encode AAC, verify, write manifest

Every clip the app can ask for is one (voice, Gujarati text) pair, computed exactly as BoloKit's
Content.allAudioRequests does: each scene line in its speaker's voice, plus each phrase on its own in
the voice of whoever says it in its scene (reusing the scene line when the phrase is the whole line).
The BoloKit test testBundledManifestCoversEveryClip checks the result from the Swift side.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONTENT = os.path.join(ROOT, "Packages/BoloKit/Sources/BoloKit/Resources/content.json")
AUDIO_DIR = os.path.join(ROOT, "App/Resources/Audio")
MANIFEST = os.path.join(AUDIO_DIR, "manifest.json")
WORK = os.path.join(ROOT, "tts-work")

# ---------------------------------------------------------------------------------------------
# Engines. ENGINE picks one; its "id" goes into the manifest so a change of engine or voice
# settings regenerates every clip.
ENGINES = {
    "indictts": {
        "id": "ai4bharat-indictts-gu-fastpitch-hifigan-v1",
        "model": "AI4Bharat Indic-TTS (FastPitch + HiFi-GAN, Gujarati)",
        "voices": {"male": "male", "female": "female"},
        "candidates": 1,
    },
    "svara": {
        "id": "kenpath-svara-tts-v1-t0.6",
        "model": "Svara TTS v1 (Kenpath)",
        "voices": {"male": "Gujarati (Male)", "female": "Gujarati (Female)"},
        # Sampled, so it sometimes repeats itself or says its speaker label ("Gujarati ...") before
        # the line: draw takes until the recognizer hears the line cleanly. Not the default: in the
        # probe about half its takes did that, and on CPU runners it is slow.
        "candidates": 6,
    },
    "mms": {
        "id": "facebook-mms-tts-guj",
        "model": "Meta MMS-TTS Gujarati",
        "voices": {"male": None, "female": None},
        "candidates": 1,
    },
}
ENGINE = os.environ.get("ENGINE", "indictts")

PUNCT = "?!.,"


def words(text):
    return [w.strip(PUNCT) for w in text.split() if w.strip(PUNCT)]


def requests():
    c = json.load(open(CONTENT, encoding="utf-8"))
    voice = lambda speaker: c["speakers"][speaker]["voice"] if 0 <= speaker < len(c["speakers"]) else "female"
    out = set()
    for lines in c["scenes"].values():
        for line in lines:
            out.add((voice(line["speaker"]), line["gu"]))
    for p in c["phrases"]:
        lines = c["scenes"].get(p["scene"], [])
        if 0 <= p["line"] < len(lines):
            line = lines[p["line"]]
            if words(line["gu"]) == words(p["gu"]):
                out.add((voice(line["speaker"]), line["gu"]))
            else:
                out.add((voice(line["speaker"]), p["gu"]))
        else:
            out.add(("female", p["gu"]))
    return sorted(out, key=lambda vt: f"{vt[0]}|{vt[1]}")


def key(voice, text):
    return f"{voice}|{text}"


def file_name(voice, text):
    return f"{voice}-{hashlib.sha1(text.encode('utf-8')).hexdigest()[:10]}.m4a"


def load_manifest():
    try:
        return json.load(open(MANIFEST, encoding="utf-8"))
    except FileNotFoundError:
        return {"model": "", "engine": "", "clips": {}}


# ---------------------------------------------------------------------------------------------
def cmd_plan(args):
    engine = ENGINES[ENGINE]
    manifest = load_manifest()
    todo = []
    for voice, text in requests():
        entry = manifest.get("clips", {}).get(key(voice, text))
        fresh = (not args.force and entry and entry.get("engine") == engine["id"]
                 and os.path.exists(os.path.join(AUDIO_DIR, entry["file"])))
        if not fresh:
            todo.append({"voice": voice, "text": text})
    shards = max(1, min(args.shards, len(todo))) if todo else 0
    plan = {"engine": ENGINE, "shards": [todo[i::shards] for i in range(shards)]}
    os.makedirs(WORK, exist_ok=True)
    json.dump(plan, open(os.path.join(WORK, "plan.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"{len(requests())} clips needed, {len(todo)} to generate with {ENGINE} in {shards} shards")
    gh = os.environ.get("GITHUB_OUTPUT")
    if gh:
        with open(gh, "a") as f:
            f.write(f"matrix={json.dumps(list(range(shards)))}\n")
            f.write(f"count={len(todo)}\n")


# ---------------------------------------------------------------------------------------------
class IndicTTS:
    def __init__(self):
        import glob
        import zipfile
        url = "https://github.com/AI4Bharat/Indic-TTS/releases/download/v1-checkpoints-release/gu.zip"
        base = "/tmp/indictts"
        if not os.path.exists(f"{base}/gu/fastpitch/best_model.pth"):
            subprocess.run(["curl", "-sSL", "--retry", "3", "-o", "/tmp/gu.zip", url], check=True)
            with zipfile.ZipFile("/tmp/gu.zip") as z:
                z.extractall(base)
            os.remove("/tmp/gu.zip")
        fp, hg = f"{base}/gu/fastpitch", f"{base}/gu/hifigan"
        cfg = json.load(open(f"{fp}/config.json"))

        def patch(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    if isinstance(v, str) and v.endswith("speakers.pth"):
                        o[k] = f"{fp}/speakers.pth"
                    else:
                        patch(v)
            elif isinstance(o, list):
                for v in o:
                    patch(v)
        patch(cfg)
        json.dump(cfg, open(f"{fp}/config.json", "w"), indent=1)
        from TTS.utils.synthesizer import Synthesizer
        self.syn = Synthesizer(tts_checkpoint=f"{fp}/best_model.pth", tts_config_path=f"{fp}/config.json",
                               tts_speakers_file=f"{fp}/speakers.pth", vocoder_checkpoint=f"{hg}/best_model.pth",
                               vocoder_config=f"{hg}/config.json", use_cuda=False)
        self.sr = self.syn.output_sample_rate

    def synth(self, text, voice, seed):
        import numpy as np
        return np.asarray(self.syn.tts(text, speaker_name=voice), dtype="float32")


class Svara:
    def __init__(self):
        import torch
        from snac import SNAC
        from transformers import AutoModelForCausalLM, AutoTokenizer
        self.torch = torch
        repo = "kenpath/svara-tts-v1"
        self.tok = AutoTokenizer.from_pretrained(repo)
        self.model = AutoModelForCausalLM.from_pretrained(repo, torch_dtype=torch.bfloat16, low_cpu_mem_usage=True).eval()
        self.snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").eval()
        self.sr = 24000

    def synth(self, text, voice, seed):
        return self.synth_many(text, voice, seed, 1)[0]

    def synth_many(self, text, voice, seed, n):
        """n sampled takes of one line in a single batched generate call: on a CPU, three rows cost
        little more than one."""
        import numpy as np
        torch = self.torch
        body = self.tok(f"{voice}: {text}", add_special_tokens=False).input_ids
        ids = torch.tensor([[128000, 128259, 156939] + body + [128260, 128009, 128261, 128257]]).repeat(n, 1)
        torch.manual_seed(seed)
        # About 82 audio tokens per second of speech: allow a slow reading of the line and no more,
        # so a take that starts to ramble is cut short instead of costing minutes.
        budget = int(82 * (1.0 + 0.17 * len(norm(text)))) + 50
        with torch.inference_mode():
            out = self.model.generate(ids, attention_mask=torch.ones_like(ids), max_new_tokens=min(900, budget),
                                      do_sample=True, temperature=0.6, top_p=0.9, top_k=40, repetition_penalty=1.1,
                                      eos_token_id=[128258, 128262], pad_token_id=128263)
        takes = []
        for row in out[:, ids.shape[1]:].tolist():
            if 128258 in row:
                row = row[:row.index(128258)]
            codes = [t - 128266 for t in row if 128266 <= t < 128266 + 7 * 4096]
            frames = len(codes) // 7
            if frames == 0:
                takes.append(np.zeros(1, dtype="float32"))
                continue
            c = torch.tensor([codes[i] - (i % 7) * 4096 for i in range(frames * 7)]).view(frames, 7)
            layers = [c[:, 0].reshape(1, -1), c[:, [1, 4]].reshape(1, -1), c[:, [2, 3, 5, 6]].reshape(1, -1)]
            if any(((x < 0) | (x > 4095)).any() for x in layers):
                takes.append(np.zeros(1, dtype="float32"))
                continue
            with torch.inference_mode():
                takes.append(self.snac.decode(layers).reshape(-1).numpy().astype("float32"))
        return takes


class MMS:
    def __init__(self):
        import torch
        from transformers import AutoTokenizer, VitsModel
        self.torch = torch
        self.model = VitsModel.from_pretrained("facebook/mms-tts-guj").eval()
        self.tok = AutoTokenizer.from_pretrained("facebook/mms-tts-guj")
        self.sr = self.model.config.sampling_rate

    def synth(self, text, voice, seed):
        self.torch.manual_seed(seed)
        with self.torch.inference_mode():
            return self.model(**self.tok(text, return_tensors="pt")).waveform[0].numpy().astype("float32")


def norm(s):
    s = unicodedata.normalize("NFC", s)
    return "".join(ch for ch in s if not (unicodedata.category(ch).startswith("P") or ch.isspace()))


def cer(ref, hyp):
    a, b = norm(ref), norm(hyp)
    if not a:
        return 0.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1] / len(a)


class Recognizer:
    """Meta MMS speech recognition (Gujarati adapter), used only to score clips, never shipped."""

    def __init__(self):
        import torch
        from transformers import AutoProcessor, Wav2Vec2ForCTC
        self.torch = torch
        self.proc = AutoProcessor.from_pretrained("facebook/mms-1b-all", target_lang="guj")
        self.model = Wav2Vec2ForCTC.from_pretrained("facebook/mms-1b-all", target_lang="guj",
                                                    ignore_mismatched_sizes=True).eval()

    def hear(self, audio, sr):
        import librosa
        import numpy as np
        y = librosa.resample(audio, orig_sr=sr, target_sr=16000) if sr != 16000 else audio
        # The recognizer needs some context: a word under a second long often decodes to nothing.
        # Half a second of silence either side tells a recognizer miss from a bad clip.
        pad = np.zeros(8000, dtype="float32")
        y = np.concatenate([pad, np.asarray(y, dtype="float32"), pad])
        with self.torch.inference_mode():
            ids = self.model(**self.proc(y, sampling_rate=16000, return_tensors="pt")).logits.argmax(-1)[0]
        return self.proc.decode(ids)


def cmd_generate(args):
    import numpy as np
    import soundfile as sf
    import torch
    torch.set_num_threads(os.cpu_count() or 4)
    plan = json.load(open(os.path.join(WORK, "plan.json"), encoding="utf-8"))
    items = plan["shards"][args.shard]
    engine = ENGINES[plan["engine"]]
    t0 = time.time()
    tts = {"indictts": IndicTTS, "svara": Svara, "mms": MMS}[plan["engine"]]()
    print(f"{plan['engine']} loaded in {time.time() - t0:.0f}s; {len(items)} clips in shard {args.shard}", flush=True)
    candidates = args.candidates or engine["candidates"]
    asr = Recognizer() if candidates > 1 or args.score else None
    out_dir = os.path.join(WORK, "raw")
    os.makedirs(out_dir, exist_ok=True)
    # One take per generate call: batched takes all ran to the token cap (run 36684352102).
    batch = 1
    deadline = t0 + args.budget_minutes * 60 if args.budget_minutes else None
    for n, item in enumerate(items):
        # Stop starting new clips once the time budget is spent, so the job ends on its own and
        # uploads what it has; the next run records only what is still missing.
        if deadline and time.time() > deadline:
            left = len(items) - n
            print(f"::warning title=Audio shard {args.shard}::Time budget spent after {n} of {len(items)} clips; "
                  f"{left} left for the next run.", flush=True)
            break
        voice, text = item["voice"], item["text"]
        best, tried, done = None, 0, False
        while tried < candidates and not done:
            seed = int(hashlib.sha1(f"{voice}|{text}|{tried}".encode()).hexdigest()[:8], 16)
            t1 = time.time()
            if batch > 1:
                takes = tts.synth_many(text, engine["voices"][voice], seed, min(batch, candidates - tried))
            else:
                takes = [tts.synth(text, engine["voices"][voice], seed)]
            took = time.time() - t1
            for audio in takes:
                k = tried
                tried += 1
                score = {"cer": None, "asr": None}
                if asr is not None and len(audio) > tts.sr * 0.1:
                    heard = asr.hear(audio, tts.sr)
                    score = {"cer": round(cer(text, heard), 3), "asr": heard}
                dur = len(audio) / tts.sr
                # Prefer the take the recognizer understands best; penalise implausible lengths.
                plausible = 0.25 <= dur <= 1.2 + 0.18 * len(norm(text))
                rank = (0 if plausible else 1, score["cer"] if score["cer"] is not None else 0.5)
                print(f"[{n + 1}/{len(items)}] {voice} {text} take {k}: {dur:.2f}s ({took:.0f}s for {len(takes)}) "
                      f"cer={score['cer']} {score['asr']}", flush=True)
                if best is None or rank < best[0]:
                    best = (rank, audio, score, k)
                if plausible and score["cer"] is not None and score["cer"] <= 0.15:
                    done = True  # heard cleanly: good enough
        name = file_name(voice, text).replace(".m4a", "")
        sf.write(os.path.join(out_dir, f"{name}.wav"), best[1], tts.sr)
        json.dump({"voice": voice, "text": text, "candidate": best[3], "candidates_tried": tried,
                   "plausible": best[0][0] == 0, **best[2]},
                  open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8"), ensure_ascii=False)


# ---------------------------------------------------------------------------------------------
def process(wav_in, m4a_out):
    """Trim silence, normalise loudness, fade the edges, encode mono AAC. Returns stats."""
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(wav_in, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    peak = float(np.max(np.abs(audio))) if len(audio) else 0.0
    stats = {"raw_peak": round(peak, 4), "raw_dur": round(len(audio) / sr, 3)}
    if peak < 1e-4:
        stats.update(dur=0.0, active_rms_db=-120.0, peak_db=-120.0)
        return stats
    # Trim to where the signal rises above -40 dB of its peak, keeping a little air.
    frame = int(sr * 0.01)
    env = np.array([np.max(np.abs(audio[i:i + frame])) for i in range(0, len(audio), frame)])
    loud = np.where(env > peak * 10 ** (-40 / 20))[0]
    start = max(0, loud[0] * frame - int(sr * 0.06))
    end = min(len(audio), (loud[-1] + 1) * frame + int(sr * 0.14))
    audio = audio[start:end]
    # Normalise the speech (frames within 30 dB of the peak) to -20 dBFS RMS, peak capped at -1.5 dBFS.
    env = np.array([np.sqrt(np.mean(audio[i:i + frame] ** 2)) for i in range(0, len(audio), frame)])
    active = env[env > env.max() * 10 ** (-30 / 20)]
    rms = float(np.sqrt(np.mean(active ** 2))) if len(active) else 1e-6
    gain = min(10 ** (-20 / 20) / max(rms, 1e-6), 10 ** (-1.5 / 20) / max(float(np.max(np.abs(audio))), 1e-6))
    audio = audio * gain
    fade = min(int(sr * 0.012), len(audio) // 4)
    if fade > 0:
        ramp = np.linspace(0, 1, fade, dtype="float32")
        audio[:fade] *= ramp
        audio[-fade:] *= ramp[::-1]
    tmp = m4a_out + ".wav"
    sf.write(tmp, audio, sr)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-ac", "1", "-ar", "44100",
                    "-c:a", "aac", "-b:a", "80k", "-movflags", "+faststart", m4a_out], check=True)
    os.remove(tmp)
    # Measure what was actually written.
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", m4a_out],
                           capture_output=True, text=True, check=True)
    decoded = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", m4a_out, "-f", "f32le", "-ac", "1", "-"],
                             capture_output=True, check=True).stdout
    y = np.frombuffer(decoded, dtype="float32")
    env = np.array([np.sqrt(np.mean(y[i:i + 441] ** 2)) for i in range(0, max(len(y) - 441, 1), 441)])
    active = env[env > (env.max() if len(env) else 0) * 10 ** (-30 / 20)]
    stats.update(dur=round(float(probe.stdout.strip() or 0), 3),
                 active_rms_db=round(20 * np.log10(max(float(np.sqrt(np.mean(active ** 2))) if len(active) else 0, 1e-6)), 1),
                 peak_db=round(20 * np.log10(max(float(np.max(np.abs(y))) if len(y) else 0, 1e-6)), 1))
    return stats


def cmd_finalize(args):
    engine_name = json.load(open(os.path.join(WORK, "plan.json"), encoding="utf-8"))["engine"]
    engine = ENGINES[engine_name]
    manifest = load_manifest()
    old = manifest.get("clips", {})
    needed = requests()
    raw_dir = os.path.join(WORK, "raw")
    os.makedirs(AUDIO_DIR, exist_ok=True)
    clips, problems, report = {}, [], []
    for voice, text in needed:
        k, fname = key(voice, text), file_name(voice, text)
        base = fname.replace(".m4a", "")
        wav = os.path.join(raw_dir, base + ".wav")
        if os.path.exists(wav):
            meta = json.load(open(os.path.join(raw_dir, base + ".json"), encoding="utf-8"))
            stats = process(wav, os.path.join(AUDIO_DIR, fname))
            entry = {"file": fname, "duration": stats["dur"], "engine": engine["id"],
                     "cer": meta.get("cer"), "asr": meta.get("asr"), "tries": meta.get("candidates_tried"),
                     "active_rms_db": stats["active_rms_db"], "peak_db": stats["peak_db"]}
        elif k in old and old[k].get("engine") == engine["id"] and os.path.exists(os.path.join(AUDIO_DIR, old[k]["file"])):
            entry = old[k]
        else:
            problems.append(f"MISSING {k}")
            continue
        bad = None
        if entry["duration"] < 0.25:
            bad = f"TOO SHORT ({entry['duration']}s) {k}"
        elif entry.get("active_rms_db", 0) < -40 or entry.get("peak_db", 0) < -20:
            bad = f"NEAR-SILENT (rms {entry.get('active_rms_db')} dB, peak {entry.get('peak_db')} dB) {k}"
        if bad:
            problems.append(bad)  # never ship it; the next run records it again
            continue
        clips[k] = entry
        report.append((k, entry))
    # Remove clips nothing asks for any more.
    keep = {e["file"] for e in clips.values()}
    for f in os.listdir(AUDIO_DIR):
        if f.endswith(".m4a") and f not in keep:
            os.remove(os.path.join(AUDIO_DIR, f))
    manifest = {"model": engine["model"], "engine": engine["id"], "clips": dict(sorted(clips.items()))}
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    open(MANIFEST, "a").write("\n")

    durs = [e["duration"] for _, e in report]
    cers = [e["cer"] for _, e in report if e.get("cer") is not None]
    summary = (f"{len(clips)}/{len(needed)} clips with {engine['model']}; duration {min(durs, default=0):.2f}-"
               f"{max(durs, default=0):.2f}s (mean {sum(durs) / max(len(durs), 1):.2f}s); "
               f"quietest speech {min((e.get('active_rms_db', 0) for _, e in report), default=0)} dBFS RMS")
    if cers:
        summary += (f"; ASR round-trip CER mean {sum(cers) / len(cers):.3f}, "
                    f"{sum(1 for c in cers if c == 0)}/{len(cers)} exact, {sum(1 for c in cers if c > 0.5)} above 0.5")
    print(summary)
    for k, e in report:
        print(f"{e['duration']:5.2f}s rms {e.get('active_rms_db')} cer {e.get('cer')} {k} => {e.get('asr')}")
    step = os.environ.get("GITHUB_STEP_SUMMARY")
    if step:
        with open(step, "a", encoding="utf-8") as f:
            f.write(f"### Audio\n\n{summary}\n\n| clip | s | CER | heard |\n|---|---|---|---|\n")
            for k, e in report:
                f.write(f"| {k} | {e['duration']} | {e.get('cer')} | {e.get('asr') or ''} |\n")
    # Good clips are committed even when others are missing, so a re-run only has to record the rest.
    # The workflow fails afterwards if problems.txt lists anything.
    open(os.path.join(WORK, "problems.txt"), "w", encoding="utf-8").write("\n".join(problems))
    if problems:
        print(f"::error title=Audio::{len(problems)} of {len(needed)} clips missing or unusable:%0A" + "%0A".join(problems[:40]))
    else:
        print(f"::notice title=Audio::{summary}")
    doubtful = [(k, e) for k, e in report if (e.get("cer") or 0) > 0.5]
    if doubtful:
        print("::warning title=Audio (recognizer could not confirm these clips)::" + "%0A".join(
            f"{e['cer']:.2f} {k} heard {e.get('asr') or '(nothing)'}" for k, e in doubtful[:30]))
    worst = sorted((e for _, e in report if e.get("cer") is not None), key=lambda e: -e["cer"])[:8]
    if worst:
        print("::notice title=Audio (least intelligible to the recognizer)::" + "%0A".join(
            f"{e['cer']:.2f} {e['file']} heard {e.get('asr') or '(nothing)'}" for e in worst))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--shards", type=int, default=4)
    p.add_argument("--force", action="store_true")
    g = sub.add_parser("generate")
    g.add_argument("--shard", type=int, required=True)
    g.add_argument("--candidates", type=int, default=0)
    g.add_argument("--score", action="store_true", help="score the chosen clip with the recognizer")
    g.add_argument("--budget-minutes", type=float, default=0, help="stop starting new clips after this long")
    sub.add_parser("finalize")
    args = ap.parse_args()
    {"plan": cmd_plan, "generate": cmd_generate, "finalize": cmd_finalize}[args.cmd](args)


if __name__ == "__main__":
    main()
