"""Second TTS probe: the candidates the first probe could not reach.

  python probe2.py svara      kenpath/svara-tts-v1 (Apache-2.0, Orpheus-style 3B, Gujarati male + female)
  python probe2.py indictts   AI4Bharat Indic-TTS FastPitch + HiFi-GAN (MIT, GitHub release, gu male + female)
  python probe2.py parler     ai4bharat/indic-parler-tts (Apache-2.0, gated: needs HF_TOKEN)

Each run writes probe-out/<engine>/report.json and its WAVs. Every clip is scored two ways:
  cer    character error rate of a round trip through Meta's MMS recognizer (Gujarati adapter).
         Low means the words are there. It says nothing about naturalness.
  utmos  UTMOS22 predicted MOS (1-5). Trained on English, so only a rough naturalness proxy.
"""
import json, os, sys, time, traceback, unicodedata, urllib.request

import numpy as np
import soundfile as sf
import torch

ENGINE = sys.argv[1]
OUT = f"probe-out/{ENGINE}"
os.makedirs(OUT, exist_ok=True)
torch.set_num_threads(os.cpu_count() or 4)
report = {"engine": ENGINE, "clips": [], "notes": []}

LINES = ["કેમ છો?", "હા, આભાર.", "મજામાં, આભાર. તમે?", "તમારું નામ શું છે?", "દૂધ ક્યાં છે?",
         "મને ગુજરાતી થોડું આવડે છે.", "ના.", "આ કેટલા પૈસા?"]


def note(msg):
    print(msg, flush=True)
    report["notes"].append(msg)


def hf_info(repo):
    try:
        req = urllib.request.Request(f"https://huggingface.co/api/models/{repo}")
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.load(r)
        card = d.get("cardData") or {}
        return {"gated": d.get("gated"), "license": card.get("license"), "downloads": d.get("downloads")}
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


def save(name, audio, sr, voice, text, gen_s):
    audio = np.asarray(audio, dtype=np.float32).reshape(-1)
    sf.write(f"{OUT}/{name}.wav", audio, sr)
    report["clips"].append({"name": name, "voice": voice, "text": text, "sr": sr,
                            "dur": round(len(audio) / sr, 2), "gen_s": round(gen_s, 1)})
    print(f"{name}: {len(audio) / sr:.2f}s audio in {gen_s:.1f}s", flush=True)


# --------------------------------------------------------------------------------------------
def run_svara():
    from transformers import AutoModelForCausalLM, AutoTokenizer
    repo = "kenpath/svara-tts-v1"
    report["model"] = hf_info(repo)
    try:
        with urllib.request.urlopen("https://huggingface.co/api/models?search=svara-tts&limit=30", timeout=30) as r:
            report["related"] = [m["id"] for m in json.load(r)]
    except Exception as e:  # noqa: BLE001
        report["related"] = str(e)
    note(f"svara model info {report['model']} related {report.get('related')}")
    t0 = time.time()
    tok = AutoTokenizer.from_pretrained(repo)
    model = AutoModelForCausalLM.from_pretrained(repo, torch_dtype=torch.bfloat16, low_cpu_mem_usage=True).eval()
    note(f"svara loaded in {time.time() - t0:.0f}s")
    from snac import SNAC
    snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").eval()

    def ids_for(text, speaker):
        body = tok(f"{speaker}: {text}", add_special_tokens=False).input_ids
        return [128000, 128259, 156939] + body + [128260, 128009, 128261, 128257]

    def decode(gen):
        codes = [t - 128266 for t in gen if 128266 <= t < 128266 + 7 * 4096]
        frames = len(codes) // 7
        if frames == 0:
            return np.zeros(1, dtype=np.float32)
        c = [codes[i] - (i % 7) * 4096 for i in range(frames * 7)]
        t = torch.tensor(c, dtype=torch.int64).view(frames, 7)
        l0 = t[:, 0].reshape(1, -1)
        l1 = t[:, [1, 4]].reshape(1, -1)
        l2 = t[:, [2, 3, 5, 6]].reshape(1, -1)
        if any(((x < 0) | (x > 4095)).any() for x in (l0, l1, l2)):
            note("svara produced out-of-range codes")
            return np.zeros(1, dtype=np.float32)
        with torch.inference_mode():
            return snac.decode([l0, l1, l2]).reshape(-1).numpy()

    for voice in ["Gujarati (Female)", "Gujarati (Male)"]:
        tag = "f" if "Female" in voice else "m"
        for li, text in enumerate(LINES):
            torch.manual_seed(100 + li)
            ids = torch.tensor([ids_for(text, voice)])
            t0 = time.time()
            with torch.inference_mode():
                out = model.generate(ids, attention_mask=torch.ones_like(ids), max_new_tokens=900,
                                     do_sample=True, temperature=0.6, top_p=0.9, top_k=40,
                                     repetition_penalty=1.1, eos_token_id=[128258, 128262], pad_token_id=128263)
            dt = time.time() - t0
            gen = out[0, ids.shape[1]:].tolist()
            note(f"svara {tag}{li}: {len(gen)} tokens in {dt:.0f}s ({len(gen) / max(dt, 1e-3):.1f} tok/s)")
            save(f"svara-{tag}-{li}", decode(gen), 24000, voice, text, dt)
            if li == 3 and time.time() - T_START > 60 * 60:
                note("svara: stopping early to leave time for scoring")
                break


# --------------------------------------------------------------------------------------------
def run_indictts():
    import glob, subprocess, zipfile
    url = "https://github.com/AI4Bharat/Indic-TTS/releases/download/v1-checkpoints-release/gu.zip"
    t0 = time.time()
    subprocess.run(["curl", "-sSL", "-o", "/tmp/gu.zip", url], check=True)
    note(f"downloaded gu.zip {os.path.getsize('/tmp/gu.zip') / 1e9:.2f} GB in {time.time() - t0:.0f}s")
    with zipfile.ZipFile("/tmp/gu.zip") as z:
        names = z.namelist()
        report["zip"] = names
        z.extractall("/tmp/indictts")
    note(f"zip contents: {names}")
    os.remove("/tmp/gu.zip")

    def find(pattern):
        hits = sorted(glob.glob(f"/tmp/indictts/**/{pattern}", recursive=True))
        return hits

    tts_ckpt = [p for p in find("best_model.pth") if "fastpitch" in p.lower()][0]
    voc_ckpt = [p for p in find("best_model.pth") if "hifigan" in p.lower()][0]
    tts_cfg = os.path.join(os.path.dirname(tts_ckpt), "config.json")
    voc_cfg = os.path.join(os.path.dirname(voc_ckpt), "config.json")
    spk = [p for p in find("speakers.pth") if "fastpitch" in p.lower()]
    note(f"fastpitch {tts_ckpt} hifigan {voc_ckpt} speakers {spk}")

    def patch(path, speakers):
        cfg = json.load(open(path))

        def walk(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    if isinstance(v, str) and v.endswith("speakers.pth") and speakers:
                        o[k] = speakers
                    else:
                        walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)
        walk(cfg)
        json.dump(cfg, open(path, "w"), indent=1)
        return cfg

    cfg = patch(tts_cfg, spk[0] if spk else None)
    report["tts_config_keys"] = {k: cfg.get(k) for k in ["model", "use_speaker_embedding", "speakers_file",
                                                          "characters", "text_cleaner", "phonemizer"]}
    from TTS.utils.synthesizer import Synthesizer
    syn = Synthesizer(tts_checkpoint=tts_ckpt, tts_config_path=tts_cfg,
                      tts_speakers_file=spk[0] if spk else None,
                      vocoder_checkpoint=voc_ckpt, vocoder_config=voc_cfg, use_cuda=False)
    names = []
    try:
        names = list(syn.tts_model.speaker_manager.name_to_id.keys())
    except Exception:  # noqa: BLE001
        pass
    note(f"indictts speakers: {names}")
    sr = syn.output_sample_rate
    for voice in (names or [None]):
        for li, text in enumerate(LINES):
            t0 = time.time()
            wav = syn.tts(text, speaker_name=voice) if voice else syn.tts(text)
            save(f"indictts-{voice or 'default'}-{li}", np.array(wav), sr, voice or "default", text, time.time() - t0)


# --------------------------------------------------------------------------------------------
def run_parler():
    if not os.environ.get("HF_TOKEN"):
        note("HF_TOKEN not set: indic-parler-tts is gated, skipping")
        return
    from parler_tts import ParlerTTSForConditionalGeneration
    from transformers import AutoTokenizer
    repo = "ai4bharat/indic-parler-tts"
    model = ParlerTTSForConditionalGeneration.from_pretrained(repo).eval()
    tok = AutoTokenizer.from_pretrained(repo)
    dtok = AutoTokenizer.from_pretrained(model.config.text_encoder._name_or_path)
    sr = model.config.sampling_rate
    for voice in ["Neha", "Yash"]:
        desc = (f"{voice} speaks in a warm, natural, conversational tone at a slightly slow pace. The recording is "
                "of very high quality, with the speaker's voice sounding clear and very close up.")
        for li, text in enumerate(LINES):
            torch.manual_seed(10 + li)
            d = dtok(desc, return_tensors="pt")
            p = tok(text, return_tensors="pt")
            t0 = time.time()
            with torch.inference_mode():
                a = model.generate(input_ids=d.input_ids, attention_mask=d.attention_mask,
                                   prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask)
            save(f"parler-{voice}-{li}", a.cpu().numpy().squeeze(), sr, voice, text, time.time() - t0)


# --------------------------------------------------------------------------------------------
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


def score():
    import librosa
    if not report["clips"]:
        return
    try:
        from transformers import AutoProcessor, Wav2Vec2ForCTC
        proc = AutoProcessor.from_pretrained("facebook/mms-1b-all", target_lang="guj")
        asr = Wav2Vec2ForCTC.from_pretrained("facebook/mms-1b-all", target_lang="guj",
                                             ignore_mismatched_sizes=True).eval()
        for c in report["clips"]:
            y, _ = librosa.load(f"{OUT}/{c['name']}.wav", sr=16000)
            c["rms"] = round(float(np.sqrt(np.mean(y ** 2))) if len(y) else 0.0, 4)
            with torch.inference_mode():
                ids = asr(**proc(y, sampling_rate=16000, return_tensors="pt")).logits.argmax(-1)[0]
            c["asr"] = proc.decode(ids)
            c["cer"] = round(cer(c["text"], c["asr"]), 3)
            print(c["name"], c["dur"], c["cer"], c["text"], "=>", c["asr"], flush=True)
        del asr
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        report["asr_error"] = repr(e)
    try:
        predictor = torch.hub.load("tarepan/SpeechMOS:v1.2.0", "utmos22_strong", trust_repo=True)
        for c in report["clips"]:
            y, _ = librosa.load(f"{OUT}/{c['name']}.wav", sr=16000)
            with torch.inference_mode():
                c["utmos"] = round(float(predictor(torch.from_numpy(y).unsqueeze(0), 16000)), 2)
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        report["utmos_error"] = repr(e)
    for key in ["cer", "utmos", "dur", "gen_s"]:
        vals = [c[key] for c in report["clips"] if key in c]
        if vals:
            report[f"mean_{key}"] = round(float(np.mean(vals)), 3)


T_START = time.time()
try:
    {"svara": run_svara, "indictts": run_indictts, "parler": run_parler}[ENGINE]()
except Exception as e:  # noqa: BLE001
    traceback.print_exc()
    report["error"] = repr(e)[:2000]
score()
json.dump(report, open(f"{OUT}/report.json", "w"), ensure_ascii=False, indent=1)
print(json.dumps({k: v for k, v in report.items() if k != "clips"}, ensure_ascii=False)[:3000])
