"""Gujarati speech recognizers that check the recorded clips. Used only for scoring, never shipped.

Two independent families, so one model's blind spots don't decide alone:
  mms       Meta MMS-1B-all, Gujarati adapter (wav2vec2 CTC). Gives character timings too.
  whisper   vasista22/whisper-gujarati-medium (Whisper fine-tuned on Gujarati, SPRING Lab, IIT Madras).
Also available for comparison: vakyansh (a Gujarati wav2vec2 CTC model) and whisper-v3 (OpenAI
Whisper large-v3, multilingual).

Every recognizer takes mono float32 audio at 16 kHz.
"""
import gc
import re
import unicodedata

SR = 16000


class CTC:
    """A wav2vec2 CTC recognizer with greedy decoding."""

    def __init__(self, repo, target_lang=None):
        import torch
        from transformers import AutoProcessor, Wav2Vec2ForCTC
        self.torch = torch
        kw = {"target_lang": target_lang, "ignore_mismatched_sizes": True} if target_lang else {}
        self.proc = AutoProcessor.from_pretrained(repo, **({"target_lang": target_lang} if target_lang else {}))
        self.model = Wav2Vec2ForCTC.from_pretrained(repo, **kw).eval()
        self.tok = self.proc.tokenizer
        self.blank = self.tok.pad_token_id
        self.delim = getattr(self.tok, "word_delimiter_token", "|")

    def logits(self, y):
        with self.torch.inference_mode():
            return self.model(**self.proc(y, sampling_rate=SR, return_tensors="pt")).logits[0]

    def hear(self, y):
        return self.proc.decode(self.logits(y).argmax(-1)).strip()

    def hear_many(self, ys):
        return [self.hear(y) for y in ys]

    def hear_aligned(self, y):
        """Greedy transcript plus [char, start_s, end_s] for every emitted character ('|' = space)."""
        ids = self.logits(y).argmax(-1).tolist()
        frame = len(y) / SR / max(len(ids), 1)
        out, prev = [], None
        for i, t in enumerate(ids):
            if t != self.blank and t != prev:
                out.append([self.tok.convert_ids_to_tokens(t), i * frame, (i + 1) * frame])
            elif t == prev and t != self.blank and out:
                out[-1][2] = (i + 1) * frame
            prev = t
        text = "".join(" " if c == self.delim else c for c, _, _ in out)
        return re.sub(r"\s+", " ", text).strip(), out


class Whisper:
    def __init__(self, repo, language="gu", batch=8, base=None):
        import torch
        from transformers import WhisperForConditionalGeneration, WhisperProcessor
        self.torch = torch
        from transformers import GenerationConfig
        self.proc = WhisperProcessor.from_pretrained(repo)
        self.model = WhisperForConditionalGeneration.from_pretrained(repo).eval()
        if not hasattr(self.model.generation_config, "lang_to_id"):
            # Fine-tuned checkpoints saved before the language argument existed: borrow the base
            # model's generation config (same tokenizer), as transformers issue 25084 advises.
            self.model.generation_config = GenerationConfig.from_pretrained(base or "openai/whisper-medium")
        self.model.generation_config.forced_decoder_ids = None
        self.model.config.forced_decoder_ids = None
        self.language = language
        self.batch = batch

    def hear_many(self, ys):
        out, batch = [], self.batch
        for i in range(0, len(ys), batch):
            feats = self.proc([y for y in ys[i:i + batch]], sampling_rate=SR, return_tensors="pt").input_features
            with self.torch.inference_mode():
                ids = self.model.generate(feats, language=self.language, task="transcribe", max_new_tokens=60)
            out += [t.strip() for t in self.proc.batch_decode(ids, skip_special_tokens=True)]
        return out

    def hear(self, y):
        return self.hear_many([y])[0]


class FastWhisper:
    """The same Gujarati Whisper converted to CTranslate2 int8 (faster-whisper): several times faster
    on a CPU, greedy decoding, no timestamps, no conditioning on earlier text."""

    def __init__(self, repo, out="/tmp/ct2-whisper-gu"):
        import os
        import subprocess
        if not os.path.exists(os.path.join(out, "model.bin")):
            subprocess.run(["ct2-transformers-converter", "--model", repo, "--output_dir", out,
                            "--quantization", "int8", "--force"], check=True)
        from faster_whisper import WhisperModel
        self.model = WhisperModel(out, device="cpu", compute_type="int8", cpu_threads=os.cpu_count() or 4)

    def hear(self, y):
        segs, _ = self.model.transcribe(y, language="gu", task="transcribe", beam_size=1, best_of=1, temperature=0.0,
                                        condition_on_previous_text=False, without_timestamps=True, vad_filter=False)
        return " ".join(s.text.strip() for s in segs).strip()

    def hear_many(self, ys):
        return [self.hear(y) for y in ys]


RECOGNIZERS = {
    "mms": lambda: CTC("facebook/mms-1b-all", target_lang="guj"),
    "whisper": lambda: Whisper("vasista22/whisper-gujarati-medium", base="openai/whisper-medium"),
    "whisper-ct2": lambda: FastWhisper("vasista22/whisper-gujarati-medium"),
    "vakyansh": lambda: CTC("Harveenchadha/vakyansh-wav2vec2-gujarati-gnm-100"),
    "whisper-v3": lambda: Whisper("openai/whisper-large-v3", batch=4),
}


def load(name):
    return RECOGNIZERS[name]()


def free(obj):
    del obj
    gc.collect()


# ---------------------------------------------------------------------------------------------
# Text comparison.
NUMBERS = {"0": "શૂન્ય", "1": "એક", "2": "બે", "3": "ત્રણ", "4": "ચાર", "5": "પાંચ", "6": "છ", "7": "સાત",
           "8": "આઠ", "9": "નવ", "10": "દસ", "100": "સો"}
GU_DIGITS = str.maketrans("૦૧૨૩૪૫૬૭૮૯", "0123456789")
# Spellings recognizers routinely swap for the same sound: vowel length, nasal marks, nukta.
FOLD = str.maketrans({"ી": "િ", "ૂ": "ુ", "ઈ": "ઇ", "ઊ": "ઉ", "ં": None, "ઁ": None, "઼": None})


def norm(s, fold=False):
    s = unicodedata.normalize("NFC", s).translate(GU_DIGITS)
    s = re.sub(r"\d+", lambda m: f" {NUMBERS.get(m.group(0), m.group(0))} ", s)
    s = "".join(ch for ch in s if not (unicodedata.category(ch)[0] in "PS" or ch.isspace()))
    # Anything that is not Gujarati script (Latin letters, stray marks) counts as noise, not text.
    s = "".join(ch for ch in s if "઀" <= ch <= "૿" or ch.isdigit())
    return s.translate(FOLD) if fold else s


def edits(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def cer(ref, hyp, fold=True):
    a, b = norm(ref, fold), norm(hyp, fold)
    return edits(a, b) / len(a) if a else 0.0


def locate(ref, chars):
    """Finds the target text inside a CTC transcript with timings (free text before and after it).
    chars: [[char, start, end], ...] from CTC.hear_aligned. Returns (cost, start_s, end_s) or None."""
    target = norm(ref, fold=True)
    seq = [(norm(c, fold=True), s, e) for c, s, e in chars]
    seq = [x for x in seq if x[0]]
    if not target or not seq:
        return None
    hyp = [x[0] for x in seq]
    n, m = len(target), len(hyp)
    # Semi-global edit distance: the whole target against any substring of the transcript.
    INF = 10 ** 9
    d = [[0] * (m + 1)] + [[INF] * (m + 1) for _ in range(n)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        d[i][0] = i
        back[i][0] = "up"
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            opts = [(d[i - 1][j - 1] + (target[i - 1] != hyp[j - 1]), "diag"),
                    (d[i - 1][j] + 1, "up"), (d[i][j - 1] + 1, "left")]
            d[i][j], back[i][j] = min(opts)
    j_end = min(range(1, m + 1), key=lambda j: (d[n][j], -j))
    cost = d[n][j_end]
    i, j = n, j_end
    first = None
    while i > 0:
        step = back[i][j]
        if step == "diag":
            first = j - 1
            i, j = i - 1, j - 1
        elif step == "up":
            i -= 1
        else:
            j -= 1
    if first is None:
        return None
    return cost / n, seq[first][1], seq[j_end - 1][2]
