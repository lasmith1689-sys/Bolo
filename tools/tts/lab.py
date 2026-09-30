"""Audio lab: experiments behind the recorded clips, run by .github/workflows/audio-lab.yml.
Results (transcripts, scores, the audio as m4a) are pushed to the lab/results branch.

  lab.py refs                         clips from git history, silence/noise/reversed controls, and
                                      real human Gujarati recordings to calibrate the recognizers
  lab.py gen-indic                    AI4Bharat Indic-TTS variants (no sentence split, slower, carrier cut)
  lab.py gen-svara --shard I --shards N   Svara TTS v1 through llama.cpp (GGUF Q8_0)
  lab.py score --rec NAME [--sets a,b]    transcribe every clip with one recognizer
  lab.py collect                      merge everything into results.json and summary.md

Each set is a folder lab-out/<set>/ with <id>.wav files and a meta.json list of
{"id", "text", "voice", "variant", ...}.
"""
import argparse
import gc
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asr  # noqa: E402
import synthesize as syn  # noqa: E402

ROOT = syn.ROOT
OUT = os.path.join(ROOT, "lab-out")


def gh_note(title, lines, level="notice"):
    body = "%0A".join(str(x).replace("%", "%25").replace("\n", " ") for x in lines)
    print(f"::{level} title={title}::{body}", flush=True)


def write_wav(path, audio, sr):
    import soundfile as sf
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, np.asarray(audio, dtype="float32"), sr)


def read16k(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="float32").copy()


def save_meta(set_name, items):
    d = os.path.join(OUT, set_name)
    os.makedirs(d, exist_ok=True)
    json.dump(items, open(os.path.join(d, "meta.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"{set_name}: {len(items)} clips", flush=True)


def cid(*parts):
    return hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()[:10]


# ---------------------------------------------------------------------------------------------
def cmd_refs(args):
    # 1. The 95 Indic-TTS clips that were on main at e70f4ac.
    try:
        manifest = json.loads(subprocess.run(["git", "show", "e70f4ac:App/Resources/Audio/manifest.json"],
                                             capture_output=True, check=True, cwd=ROOT).stdout)
        items = []
        for k, e in manifest["clips"].items():
            voice, text = k.split("|", 1)
            data = subprocess.run(["git", "show", f"e70f4ac:App/Resources/Audio/{e['file']}"], capture_output=True,
                                  check=True, cwd=ROOT).stdout
            i = cid("indic-old", k)
            p = os.path.join(OUT, "indic-old", i + ".m4a")
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(data)
            write_wav(p.replace(".m4a", ".wav"), read16k(p), 16000)
            os.remove(p)
            items.append({"id": i, "text": text, "voice": voice, "variant": "indic-old", "engine": "indictts"})
        save_meta("indic-old", items)
    except Exception as e:  # noqa: BLE001
        gh_note("refs: indic-old failed", [repr(e)], "warning")

    # 2. The Svara probe takes (bf16, first probe) with their texts.
    try:
        rep = json.loads(subprocess.run(["git", "show", "origin/probe/svara:report.json"], capture_output=True,
                                        check=True, cwd=ROOT).stdout)
        items = []
        for c in rep["clips"]:
            data = subprocess.run(["git", "show", f"origin/probe/svara:{c['name']}.wav"], capture_output=True,
                                  check=True, cwd=ROOT).stdout
            p = os.path.join(OUT, "svara-probe", c["name"] + ".wav")
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(data)
            items.append({"id": c["name"], "text": c["text"], "voice": "female" if "Female" in c["voice"] else "male",
                          "variant": "svara-probe-bf16", "engine": "svara"})
        save_meta("svara-probe", items)
    except Exception as e:  # noqa: BLE001
        gh_note("refs: svara-probe failed", [repr(e)], "warning")

    # 3. Controls. A trustworthy recognizer must NOT hear the target text in these.
    rng = np.random.default_rng(1)
    items = []
    write_wav(os.path.join(OUT, "controls", "silence.wav"), rng.normal(0, 1e-4, 16000), 16000)
    items.append({"id": "silence", "text": "ના.", "voice": "-", "variant": "silence"})
    write_wav(os.path.join(OUT, "controls", "noise.wav"), rng.normal(0, 0.03, 16000), 16000)
    items.append({"id": "noise", "text": "ના.", "voice": "-", "variant": "noise"})
    try:
        meta = json.load(open(os.path.join(OUT, "indic-old", "meta.json"), encoding="utf-8"))
        old = {m["text"] + "|" + m["voice"]: m for m in meta}
        for key in ["તમારું નામ શું છે?|male", "મને ભૂખ લાગી છે.|male", "ખાવાનું તૈયાર છે.|female",
                    "હું અમેરિકાથી છું.|female", "આજે કે કાલે?|male", "સો રૂપિયા.|female", "કેટલા પૈસા?|male",
                    "ખબર નથી.|female", "ના.|female", "આઠ.|female", "ઘર|male", "હા|female"]:
            m = old.get(key)
            if not m:
                continue
            import soundfile as sf
            y, sr = sf.read(os.path.join(OUT, "indic-old", m["id"] + ".wav"), dtype="float32")
            i = "rev-" + m["id"]
            write_wav(os.path.join(OUT, "controls", i + ".wav"), y[::-1], sr)
            items.append({"id": i, "text": m["text"], "voice": m["voice"], "variant": "reversed"})
    except Exception as e:  # noqa: BLE001
        gh_note("refs: reversed controls failed", [repr(e)], "warning")
    save_meta("controls", items)

    # 4. Real people saying single Gujarati words (Lingua Libre, on Wikimedia Commons).
    try:
        humans_lingualibre()
    except Exception as e:  # noqa: BLE001
        gh_note("refs: Lingua Libre failed", [repr(e)], "warning")
    # 5. Real people reading Gujarati sentences (Google FLEURS test set).
    try:
        humans_fleurs()
    except Exception as e:  # noqa: BLE001
        gh_note("refs: FLEURS failed", [repr(e)], "warning")


UA = {"User-Agent": "BoloAudioLab/1.0 (https://github.com/lasmith1689-sys/Bolo; research, low volume)"}


def http_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def humans_lingualibre(limit=80):
    titles, cont = [], {}
    while len(titles) < 500:
        q = {"action": "query", "list": "search", "srsearch": 'intitle:"LL-Q5137 (guj)"', "srnamespace": 6,
             "srlimit": 100, "format": "json", **cont}
        d = http_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(q))
        titles += [h["title"] for h in d["query"]["search"]]
        if "continue" not in d:
            break
        cont = {"sroffset": d["continue"]["sroffset"]}
    print(f"Lingua Libre: {len(titles)} Gujarati files", flush=True)
    rx = re.compile(r"^File:LL-Q5137 \(guj\)-(.+?)-(.+)\.(wav|ogg|flac|mp3)$")
    items, speakers = [], {}
    for t in titles:
        m = rx.match(t)
        if not m:
            continue
        speaker, word = m.group(1), m.group(2).strip()
        if not re.fullmatch(r"[઀-૿ ]+", word):
            continue
        # Spread the sample over speakers.
        if speakers.get(speaker, 0) >= max(8, limit // 6):
            continue
        url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(t[5:])
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                data = r.read()
        except Exception as e:  # noqa: BLE001
            print(f"skip {t}: {e}", flush=True)
            continue
        i = cid("ll", t)
        p = os.path.join(OUT, "humans-words", i + "." + m.group(3))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(data)
        try:
            write_wav(os.path.join(OUT, "humans-words", i + ".wav"), read16k(p), 16000)
        finally:
            os.remove(p)
        speakers[speaker] = speakers.get(speaker, 0) + 1
        items.append({"id": i, "text": word, "voice": speaker, "variant": "human-word", "source": t})
        if len(items) >= limit:
            break
        time.sleep(0.2)
    save_meta("humans-words", items)


def humans_fleurs(limit=30):
    import tarfile
    from huggingface_hub import hf_hub_download
    tsv = hf_hub_download("google/fleurs", "data/gu_in/test.tsv", repo_type="dataset")
    rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8") if l.strip()]
    tar = hf_hub_download("google/fleurs", "data/gu_in/audio/test.tar.gz", repo_type="dataset")
    want = {r[1]: r[2] for r in rows[:limit * 3]}
    items = []
    with tarfile.open(tar) as tf:
        for member in tf:
            name = os.path.basename(member.name)
            if name not in want or len(items) >= limit:
                continue
            p = os.path.join(OUT, "humans-sentences", name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(tf.extractfile(member).read())
            i = cid("fleurs", name)
            write_wav(os.path.join(OUT, "humans-sentences", i + ".wav"), read16k(p), 16000)
            os.remove(p)
            items.append({"id": i, "text": want[name], "voice": "fleurs", "variant": "human-sentence"})
    save_meta("humans-sentences", items)


# ---------------------------------------------------------------------------------------------
CARRIER = "આ શબ્દ સાંભળો."


def indic_detail(tts, text, voice, length_scale=1.0):
    """Indic-TTS without sentence splitting or trimming, plus the predicted duration (mel frames) of
    every input character."""
    model = tts.syn.tts_model
    captured = {}
    orig = model.format_durations

    def fd(o_dr_log, x_mask):
        d = orig(o_dr_log, x_mask)
        captured["dr"] = d.detach().reshape(-1).cpu().numpy().copy()
        return d

    audio_cfg = tts.syn.tts_config.audio
    trim = getattr(audio_cfg, "do_trim_silence", False)
    model.format_durations = fd
    model.length_scale = length_scale
    setattr(audio_cfg, "do_trim_silence", False)
    try:
        wav = np.asarray(tts.syn.tts(text, speaker_name=voice, split_sentences=False), dtype="float32")
    finally:
        del model.format_durations
        model.length_scale = 1.0
        setattr(audio_cfg, "do_trim_silence", trim)
    return wav, captured["dr"]


def cmd_gen_indic(args):
    import torch
    torch.set_num_threads(os.cpu_count() or 4)
    tts = syn.IndicTTS()
    tok = tts.syn.tts_model.tokenizer
    hop = 256
    sr = tts.sr
    sets = {"indic-nosplit": [], "indic-slow": [], "indic-carrier": []}
    ratios = []
    for voice, text in syn.requests():
        nwords = len(syn.words(text))
        wav, dr = indic_detail(tts, text, voice)
        ratios.append(len(wav) / max(dr.sum(), 1))
        i = cid("nosplit", voice, text)
        write_wav(os.path.join(OUT, "indic-nosplit", i + ".wav"), wav, sr)
        sets["indic-nosplit"].append({"id": i, "text": text, "voice": voice, "variant": "nosplit", "engine": "indictts",
                                      "dur_frames": dr.astype(int).tolist(), "n_ids": len(tok.text_to_ids(text))})
        if nwords > 2:
            continue
        wav, dr = indic_detail(tts, text, voice, length_scale=1.2)
        i = cid("slow", voice, text)
        write_wav(os.path.join(OUT, "indic-slow", i + ".wav"), wav, sr)
        sets["indic-slow"].append({"id": i, "text": text, "voice": voice, "variant": "slow1.2", "engine": "indictts",
                                   "dur_frames": dr.astype(int).tolist()})
        # Carrier: say it after a short sentence and cut it out in the pause between them.
        full = f"{CARRIER} {text}"
        wav, dr = indic_detail(tts, full, voice)
        n_prefix = len(tok.text_to_ids(CARRIER))  # the carrier ends with "."; a space token follows
        bounds = np.concatenate([[0], np.cumsum(dr)]) * hop
        pause_lo, pause_hi = int(bounds[n_prefix - 1]), int(bounds[n_prefix + 1])
        # Cut at the quietest 10 ms inside the pause, preferring the latest quiet point.
        frame = int(sr * 0.01)
        seg = wav[pause_lo:pause_hi]
        env = np.array([np.sqrt(np.mean(seg[j:j + frame] ** 2)) for j in range(0, max(len(seg) - frame, 1), frame)])
        quiet = np.where(env <= env.min() * 2 + 1e-5)[0]
        cut = pause_lo + int((quiet[-1] if len(quiet) else len(env) // 2) * frame)
        i = cid("carrier", voice, text)
        write_wav(os.path.join(OUT, "indic-carrier", i + ".wav"), wav[cut:], sr)
        write_wav(os.path.join(OUT, "indic-carrier-full", i + ".wav"), wav, sr)
        sets["indic-carrier"].append({"id": i, "text": text, "voice": voice, "variant": "carrier", "engine": "indictts",
                                      "cut_s": round(cut / sr, 3), "pause_s": [round(pause_lo / sr, 3), round(pause_hi / sr, 3)],
                                      "dur_frames": dr.astype(int).tolist(), "n_prefix": n_prefix})
    for k, v in sets.items():
        save_meta(k, v)
    gh_note("Indic-TTS lab", [f"samples per duration frame: {min(ratios):.1f}-{max(ratios):.1f} (hop {hop})"] +
            [f"{k}: {len(v)} clips" for k, v in sets.items()])


# ---------------------------------------------------------------------------------------------
SVARA_TEXTS = ["ના.", "આઠ.", "ચા", "ઘર", "હા", "આભાર.", "કેમ છો?", "ખબર નથી.", "બસ, થયું. આભાર.",
               "મજામાં, આભાર. તમે?", "તમે ગુજરાતી બોલો છો?", "મને ગુજરાતી થોડું આવડે છે."]
SVARA_VOICES = {"male": "Gujarati (Male)", "female": "Gujarati (Female)"}
# Clean takes from the first probe, used as the voice reference in "ref" mode.
SVARA_REFS = {"male": ("svara-m-3", "તમારું નામ શું છે?"), "female": ("svara-f-4", "દૂધ ક્યાં છે?")}
EOS = (128258, 128262)
AUDIO0 = 128266


class SvaraCpp:
    """Svara TTS v1 through llama.cpp, with Kenpath's prompt format and sampling defaults
    (temperature 0.75, top_k 40, top_p 0.9, repetition penalty 1.1 over prompt and output), one take per
    call. Sampling is done here so it is exact; tokens are restricted to the audio band each position
    of a 7-token SNAC frame expects (or end of speech)."""

    def __init__(self, quant="Q8_0"):
        import torch
        from huggingface_hub import hf_hub_download
        from llama_cpp import Llama
        from snac import SNAC
        from transformers import AutoTokenizer
        self.torch = torch
        t0 = time.time()
        path = hf_hub_download("mradermacher/svara-tts-v1-GGUF", f"svara-tts-v1.{quant}.gguf")
        self.llm = Llama(model_path=path, n_ctx=2048, n_threads=os.cpu_count() or 4, n_batch=512, verbose=False)
        self.n_vocab = self.llm.n_vocab()
        self.tok = AutoTokenizer.from_pretrained("kenpath/svara-tts-v1")
        self.snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").eval()
        self.sr = 24000
        self.load_s = time.time() - t0
        print(f"svara {quant} loaded in {self.load_s:.0f}s, vocab {self.n_vocab}", flush=True)

    def logits(self):
        import llama_cpp
        ptr = llama_cpp.llama_get_logits_ith(self.llm._ctx.ctx, -1)
        return np.ctypeslib.as_array(ptr, shape=(self.n_vocab,)).astype(np.float64)

    def text_ids(self, s):
        return self.tok(s, add_special_tokens=False).input_ids

    def prompt_label(self, text, voice):
        return [128000, 128259, 156939] + self.text_ids(f"{SVARA_VOICES[voice]}: {text}") + [128260, 128009, 128261, 128257]

    def prompt_ref(self, text, ref_text, ref_codes):
        return ([128000, 128259, 156939] + self.text_ids(ref_text) + [128260, 128009, 128261, 128257] + ref_codes +
                [128258, 128262, 128009, 128259, 156939] + self.text_ids(text) + [128260, 128009, 128261, 128257])

    def encode(self, audio):
        torch = self.torch
        with torch.inference_mode():
            codes = self.snac.encode(torch.from_numpy(np.asarray(audio, dtype="float32"))[None, None, :])
        c0, c1, c2 = [c[0].tolist() for c in codes]
        out = []
        for i in range(len(c0)):
            out += [c0[i], c1[2 * i] + 4096, c2[4 * i] + 8192, c2[4 * i + 1] + 12288, c1[2 * i + 1] + 16384,
                    c2[4 * i + 2] + 20480, c2[4 * i + 3] + 24576]
        return [AUDIO0 + c for c in out]

    def generate(self, prompt, max_new, seed, temperature=0.75, top_k=40, top_p=0.9, rep=1.1):
        rng = np.random.default_rng(seed)
        self.llm.reset()
        self.llm.eval(prompt)
        seen = set(prompt)
        out, stopped = [], False
        for _ in range(max_new):
            lg = self.logits()
            pos = len(out) % 7
            allowed = np.full(self.n_vocab, -np.inf)
            allowed[AUDIO0 + pos * 4096:AUDIO0 + (pos + 1) * 4096] = 0.0
            allowed[list(EOS)] = 0.0
            lg = lg + allowed
            idx = np.fromiter(seen, dtype=np.int64)
            v = lg[idx]
            lg[idx] = np.where(v > 0, v / rep, v * rep)
            lg = lg / temperature
            top = np.argpartition(-lg, top_k)[:top_k]
            top = top[np.argsort(-lg[top])]
            p = np.exp(lg[top] - lg[top[0]])
            p /= p.sum()
            keep = (np.cumsum(p) - p) < top_p
            top, p = top[keep], p[keep] / p[keep].sum()
            t = int(rng.choice(top, p=p))
            if t in EOS:
                stopped = True
                break
            out.append(t)
            seen.add(t)
            self.llm.eval([t])
        return out, stopped

    def decode(self, row):
        torch = self.torch
        codes = [t - AUDIO0 for t in row if AUDIO0 <= t < AUDIO0 + 7 * 4096]
        frames = len(codes) // 7
        if frames == 0:
            return np.zeros(1, dtype="float32")
        c = torch.tensor([codes[i] - (i % 7) * 4096 for i in range(frames * 7)]).view(frames, 7)
        layers = [c[:, 0].reshape(1, -1), c[:, [1, 4]].reshape(1, -1), c[:, [2, 3, 5, 6]].reshape(1, -1)]
        with torch.inference_mode():
            return self.snac.decode(layers).reshape(-1).numpy().astype("float32")


def token_budget(text):
    # About 84 audio tokens per second; allow a slow reading plus room for a spoken label to be trimmed.
    return int(84 * (1.3 + 0.2 * len(asr.norm(text)))) + 70


def load_ref(name):
    import librosa
    import soundfile as sf
    data = subprocess.run(["git", "show", f"origin/probe/svara:{name}.wav"], capture_output=True, check=True, cwd=ROOT).stdout
    p = f"/tmp/{name}.wav"
    open(p, "wb").write(data)
    y, sr = sf.read(p, dtype="float32")
    if sr != 24000:
        y = librosa.resample(y, orig_sr=sr, target_sr=24000)
    return trim_energy(y, 24000)


def trim_energy(y, sr, db=-35):
    frame = int(sr * 0.01)
    env = np.array([np.sqrt(np.mean(y[i:i + frame] ** 2)) for i in range(0, max(len(y) - frame, 1), frame)])
    if not len(env) or env.max() <= 0:
        return y
    loud = np.where(env > env.max() * 10 ** (db / 20))[0]
    return y[max(0, loud[0] * frame - int(sr * 0.05)):min(len(y), (loud[-1] + 1) * frame + int(sr * 0.1))]


def cmd_gen_svara(args):
    import torch
    torch.set_num_threads(os.cpu_count() or 4)
    jobs = [(t, v, mode, take) for t in SVARA_TEXTS for v in ("male", "female") for mode in ("label", "ref")
            for take in range(2)]
    mine = jobs[args.shard::args.shards]
    set_name = f"svara-{args.shard:02d}"
    tts = SvaraCpp(args.quant)
    refs = {}
    for v, (name, text) in SVARA_REFS.items():
        refs[v] = (text, tts.encode(load_ref(name)))
    items, rates = [], []
    for text, voice, mode, take in mine:
        prompt = tts.prompt_label(text, voice) if mode == "label" else tts.prompt_ref(text, refs[voice][0], refs[voice][1])
        seed = int(hashlib.sha1(f"{voice}|{text}|{mode}|{take}".encode()).hexdigest()[:8], 16)
        t0 = time.time()
        row, stopped = tts.generate(prompt, token_budget(text), seed)
        dt = time.time() - t0
        audio = tts.decode(row)
        rates.append(len(row) / max(dt, 1e-3))
        i = cid("svara", voice, text, mode, take)
        write_wav(os.path.join(OUT, set_name, i + ".wav"), audio, tts.sr)
        items.append({"id": i, "text": text, "voice": voice, "variant": f"svara-{mode}", "engine": "svara",
                      "take": take, "tokens": len(row), "stopped": stopped, "gen_s": round(dt, 1),
                      "prompt_tokens": len(prompt), "tok_s": round(len(row) / max(dt, 1e-3), 2)})
        print(f"{voice} {mode} {text} take {take}: {len(row)} tokens in {dt:.0f}s ({len(row) / max(dt, 1e-3):.1f} tok/s) "
              f"{'stopped' if stopped else 'HIT CAP'} {len(audio) / tts.sr:.2f}s", flush=True)
    load_s = tts.load_s
    del tts
    gc.collect()
    # Trim: cut the take down to where the recognizer hears the target line (a spoken label before it,
    # a repeat after it). The trimmed take is scored again like any other clip.
    rec = asr.load("mms")
    trimmed = []
    import librosa
    import soundfile as sf
    for it in items:
        y, sr = sf.read(os.path.join(OUT, set_name, it["id"] + ".wav"), dtype="float32")
        y16 = librosa.resample(y, orig_sr=sr, target_sr=16000) if len(y) > 10 else y
        heard, chars = rec.hear_aligned(y16) if len(y16) > 1600 else ("", [])
        it["mms_raw"] = heard
        loc = asr.locate(it["text"], chars)
        if not loc or loc[0] > 0.34:
            continue
        cost, s, e = loc
        a, b = snap(y, sr, s - 0.08, -1), snap(y, sr, e + 0.12, +1)
        if a < 0.12 and len(y) / sr - b < 0.2:
            continue  # nothing worth trimming
        cut = y[int(a * sr):int(b * sr)]
        j = it["id"] + "t"
        write_wav(os.path.join(OUT, set_name, j + ".wav"), cut, sr)
        trimmed.append({**{k: v for k, v in it.items() if k != "mms_raw"}, "id": j, "variant": it["variant"] + "-trim",
                        "trim_s": [round(a, 2), round(b, 2)], "raw_dur": round(len(y) / sr, 2)})
    save_meta(set_name, items + trimmed)
    gh_note(f"Svara shard {args.shard}", [f"loaded in {load_s:.0f}s; {len(items)} takes; tokens/s "
                                          f"{min(rates):.2f}-{max(rates):.2f} (mean {np.mean(rates):.2f}); "
                                          f"{sum(1 for x in items if not x['stopped'])} hit the cap; {len(trimmed)} trimmed"] +
            [f"{x['variant']} {x['voice']} {x['text']}: {x['tokens']} tok {'' if x['stopped'] else 'CAP '}"
             f"=> {x.get('mms_raw') or '(nothing)'}" for x in items])


def snap(y, sr, t, direction, window=0.08):
    """Moves a cut point to the quietest 10 ms within `window` seconds on the given side."""
    frame = int(sr * 0.01)
    t = min(max(t, 0.0), len(y) / sr)
    lo, hi = (t - window, t) if direction < 0 else (t, t + window)
    lo, hi = max(0, int(lo * sr)), min(len(y), int(hi * sr))
    if hi - lo < frame:
        return t
    env = [np.sqrt(np.mean(y[i:i + frame] ** 2)) for i in range(lo, hi - frame + 1, frame // 2)]
    k = int(np.argmin(env))
    return (lo + k * (frame // 2) + frame // 2) / sr


# ---------------------------------------------------------------------------------------------
def all_sets(only=None):
    out = []
    for meta in sorted(glob.glob(os.path.join(OUT, "*", "meta.json"))):
        name = os.path.basename(os.path.dirname(meta))
        if only and name not in only and not any(name.startswith(o.rstrip("*")) for o in only if o.endswith("*")):
            continue
        out.append((name, json.load(open(meta, encoding="utf-8"))))
    return out


def cmd_score(args):
    import torch
    torch.set_num_threads(os.cpu_count() or 4)
    only = set(args.sets.split(",")) if args.sets else None
    clips = []
    for name, items in all_sets(only):
        for it in items:
            p = os.path.join(OUT, name, it["id"] + ".wav")
            if os.path.exists(p):
                clips.append((f"{name}/{it['id']}", p))
    t0 = time.time()
    rec = asr.load(args.rec)
    load_s = time.time() - t0
    t0 = time.time()
    audio = [read16k(p) for _, p in clips]
    heard = {}
    step = 16
    for i in range(0, len(clips), step):
        batch = [a if len(a) > 1600 else np.pad(a, (0, 1600 - len(a))) for a in audio[i:i + step]]
        for (k, _), h in zip(clips[i:i + step], rec.hear_many(batch)):
            heard[k] = h
        print(f"{args.rec}: {min(i + step, len(clips))}/{len(clips)} in {time.time() - t0:.0f}s", flush=True)
    os.makedirs(os.path.join(OUT, "scores"), exist_ok=True)
    json.dump({"rec": args.rec, "load_s": round(load_s), "score_s": round(time.time() - t0), "heard": heard},
              open(os.path.join(OUT, "scores", f"{args.rec}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    gh_note(f"Scored with {args.rec}", [f"{len(clips)} clips in {time.time() - t0:.0f}s (model load {load_s:.0f}s)"])


def cmd_collect(args):
    scores = {}
    for f in glob.glob(os.path.join(OUT, "scores", "*.json")):
        d = json.load(open(f, encoding="utf-8"))
        scores[d["rec"]] = d["heard"]
    recs = sorted(scores)
    rows = []
    pub = os.path.join(ROOT, "lab-pub")
    for name, items in all_sets():
        for it in items:
            k = f"{name}/{it['id']}"
            wav = os.path.join(OUT, name, it["id"] + ".wav")
            if not os.path.exists(wav):
                continue
            y = read16k(wav)
            row = {**it, "set": name, "key": k, "dur": round(len(y) / 16000, 3)}
            for r in recs:
                if k in scores[r]:
                    row[f"{r}_heard"] = scores[r][k]
                    row[f"{r}_cer"] = round(asr.cer(it["text"], scores[r][k], fold=False), 3)
                    row[f"{r}_fcer"] = round(asr.cer(it["text"], scores[r][k], fold=True), 3)
            rows.append(row)
            m4a = os.path.join(pub, "audio", name, it["id"] + ".m4a")
            os.makedirs(os.path.dirname(m4a), exist_ok=True)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-ac", "1", "-c:a", "aac", "-b:a", "64k", m4a],
                           check=True)
    os.makedirs(pub, exist_ok=True)
    json.dump({"recs": recs, "rows": rows}, open(os.path.join(pub, "results.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=0)
    lines = ["| set | n | " + " | ".join(f"{r} fCER<=0.15 / empty" for r in recs) + " |",
             "|---|---|" + "---|" * len(recs)]
    notes = []
    by_set = {}
    for row in rows:
        group = row["variant"] if re.fullmatch(r"svara-\d+", row["set"]) else row["set"]
        by_set.setdefault(group, []).append(row)
    for s, rs in sorted(by_set.items()):
        cells = []
        for r in recs:
            got = [x for x in rs if f"{r}_fcer" in x]
            ok = sum(1 for x in got if x[f"{r}_fcer"] <= 0.15)
            empty = sum(1 for x in got if not asr.norm(x[f"{r}_heard"]))
            cells.append(f"{ok}/{len(got)} / {empty}")
        lines.append(f"| {s} | {len(rs)} | " + " | ".join(cells) + " |")
        notes.append(f"{s} ({len(rs)}): " + ", ".join(f"{r} {c}" for r, c in zip(recs, cells)))
    open(os.path.join(pub, "summary.md"), "w", encoding="utf-8").write(
        "# Audio lab\n\nfCER = character error rate after folding vowel length and nasal marks.\n\n" + "\n".join(lines) + "\n")
    gh_note("Audio lab: clips heard (fCER <= 0.15 / empty transcripts)", notes)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("refs")
    sub.add_parser("gen-indic")
    g = sub.add_parser("gen-svara")
    g.add_argument("--shard", type=int, required=True)
    g.add_argument("--shards", type=int, required=True)
    g.add_argument("--quant", default="Q8_0")
    s = sub.add_parser("score")
    s.add_argument("--rec", required=True)
    s.add_argument("--sets", default="")
    sub.add_parser("collect")
    args = ap.parse_args()
    try:
        run(args)
    except BaseException as e:  # noqa: BLE001
        import traceback
        tb = traceback.format_exc().strip().splitlines()
        gh_note(f"lab.py {args.cmd} failed: {type(e).__name__}", tb[-14:], "error")
        raise


def run(args):
    {"refs": cmd_refs, "gen-indic": cmd_gen_indic, "gen-svara": cmd_gen_svara, "score": cmd_score,
     "collect": cmd_collect}[args.cmd](args)


if __name__ == "__main__":
    main()
