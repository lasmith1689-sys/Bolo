"""Research probe: which open Gujarati TTS works on a GitHub runner, how fast, and how intelligible.

Writes probe-out/report.json plus every WAV it made. Intelligibility is measured by a round trip
through Meta's MMS speech recognizer (Gujarati adapter): character error rate between the text we
asked for and what the recognizer hears. Low CER means the words are there; it says nothing about
how natural the voice sounds.
"""
import json, os, sys, time, unicodedata, urllib.request

import numpy as np
import soundfile as sf
import torch

OUT = "probe-out"
os.makedirs(OUT, exist_ok=True)
torch.set_num_threads(os.cpu_count() or 4)
report = {"models": {}, "clips": []}

LINES = ["કેમ છો?", "હા", "મજામાં, આભાર. તમે?", "તમારું નામ શું છે?", "દૂધ ક્યાં છે?", "મને ગુજરાતી થોડું આવડે છે."]
VOICES = {
    "yash": "Yash speaks in a warm, natural, conversational tone at a slightly slow pace. The recording is of very high quality, with the speaker's voice sounding clear and very close up, with no background noise.",
    "neha": "Neha speaks in a warm, natural, conversational tone at a slightly slow pace. The recording is of very high quality, with the speaker's voice sounding clear and very close up, with no background noise.",
}


def hf_info(repo):
    try:
        with urllib.request.urlopen(f"https://huggingface.co/api/models/{repo}", timeout=30) as r:
            d = json.load(r)
        card = d.get("cardData") or {}
        return {"gated": d.get("gated"), "license": card.get("license"), "downloads": d.get("downloads"),
                "lastModified": d.get("lastModified"), "tags": [t for t in d.get("tags", []) if t.startswith("license")]}
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


for repo in ["ai4bharat/indic-parler-tts", "facebook/mms-tts-guj", "facebook/mms-1b-all", "ai4bharat/IndicF5",
             "ai4bharat/indic-parler-tts-pretrained"]:
    report["models"][repo] = hf_info(repo)
    print(repo, report["models"][repo], flush=True)


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


def save(name, audio, sr):
    path = f"{OUT}/{name}.wav"
    sf.write(path, audio.astype(np.float32), sr)
    return path


# ---------------- Indic Parler-TTS ----------------
try:
    from parler_tts import ParlerTTSForConditionalGeneration
    from transformers import AutoTokenizer

    t0 = time.time()
    model = ParlerTTSForConditionalGeneration.from_pretrained("ai4bharat/indic-parler-tts").eval()
    tok = AutoTokenizer.from_pretrained("ai4bharat/indic-parler-tts")
    dtok = AutoTokenizer.from_pretrained(model.config.text_encoder._name_or_path)
    sr = model.config.sampling_rate
    report["parler_load_s"] = round(time.time() - t0, 1)
    print("parler loaded", report["parler_load_s"], "s, sr", sr, flush=True)
    K = 2
    for vi, (voice, desc) in enumerate(VOICES.items()):
        for li, text in enumerate(LINES):
            d = dtok([desc] * K, return_tensors="pt", padding=True)
            p = tok([text] * K, return_tensors="pt", padding=True)
            torch.manual_seed(1000 + li * 10 + vi)
            t0 = time.time()
            with torch.inference_mode():
                g = model.generate(input_ids=d.input_ids, attention_mask=d.attention_mask,
                                   prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask,
                                   do_sample=True, return_dict_in_generate=True)
            dt = time.time() - t0
            for k in range(K):
                n = int(g.audios_length[k]) if hasattr(g, "audios_length") else g.sequences.shape[-1]
                audio = g.sequences[k, :n].cpu().float().numpy()
                name = f"parler-{voice}-{li}-{k}"
                save(name, audio, sr)
                report["clips"].append({"name": name, "model": "indic-parler-tts", "voice": voice, "text": text,
                                        "sr": sr, "dur": round(len(audio) / sr, 2), "gen_s_batch": round(dt, 1)})
            print(f"parler {voice} {li} batch{K} {dt:.1f}s", flush=True)
    del model
except Exception as e:  # noqa: BLE001
    import traceback
    traceback.print_exc()
    report["parler_error"] = repr(e)

# ---------------- MMS-TTS Gujarati ----------------
try:
    from transformers import VitsModel, AutoTokenizer as AT

    t0 = time.time()
    mm = VitsModel.from_pretrained("facebook/mms-tts-guj").eval()
    mt = AT.from_pretrained("facebook/mms-tts-guj")
    report["mms_tts_load_s"] = round(time.time() - t0, 1)
    for li, text in enumerate(LINES):
        torch.manual_seed(7 + li)
        t0 = time.time()
        with torch.inference_mode():
            wav = mm(**mt(text, return_tensors="pt")).waveform[0].numpy()
        dt = time.time() - t0
        name = f"mms-{li}"
        save(name, wav, mm.config.sampling_rate)
        report["clips"].append({"name": name, "model": "mms-tts-guj", "voice": "mms", "text": text,
                                "sr": mm.config.sampling_rate, "dur": round(len(wav) / mm.config.sampling_rate, 2),
                                "gen_s_batch": round(dt, 2)})
    del mm
except Exception as e:  # noqa: BLE001
    import traceback
    traceback.print_exc()
    report["mms_tts_error"] = repr(e)

# ---------------- ASR round trip ----------------
try:
    import librosa
    from transformers import AutoProcessor, Wav2Vec2ForCTC

    proc = AutoProcessor.from_pretrained("facebook/mms-1b-all", target_lang="guj")
    asr = Wav2Vec2ForCTC.from_pretrained("facebook/mms-1b-all", target_lang="guj", ignore_mismatched_sizes=True).eval()
    for c in report["clips"]:
        y, _ = librosa.load(f"{OUT}/{c['name']}.wav", sr=16000)
        inp = proc(y, sampling_rate=16000, return_tensors="pt")
        with torch.inference_mode():
            ids = asr(**inp).logits.argmax(-1)[0]
        hyp = proc.decode(ids)
        c["asr"] = hyp
        c["cer"] = round(cer(c["text"], hyp), 3)
        rms = float(np.sqrt(np.mean(y ** 2))) if len(y) else 0.0
        c["rms"] = round(rms, 4)
        print(c["name"], c["dur"], c["cer"], c["text"], "=>", hyp, flush=True)
except Exception as e:  # noqa: BLE001
    import traceback
    traceback.print_exc()
    report["asr_error"] = repr(e)

json.dump(report, open(f"{OUT}/report.json", "w"), ensure_ascii=False, indent=1)
print("done")
