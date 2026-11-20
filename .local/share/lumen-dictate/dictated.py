#!/usr/bin/env python3
"""
Lumen dictation service. Spawned by Quickshell (Singletons/Dictate.qml) while
dictation is enabled; talks over stdin/stdout, one JSON object per line.

  in   {"cmd": "start"}                 begin recording from the default mic
       {"cmd": "stop", "mode": "type"}  finish: transcribe, apply vocabulary,
                                        type into the focused app + copy
       {"cmd": "stop", "mode": "teach"} finish: transcribe raw, report only
       {"cmd": "cancel"}                drop the take
  out  {"event": "ready"}
       {"event": "done", "text": "...", "raw": "..."}
       {"event": "heard", "text": "..."}
       {"event": "empty"}               nothing intelligible was said
       {"event": "error", "msg": "..."}

Model: NVIDIA Parakeet TDT 0.6B v2 (int8) through sherpa-onnx, on the CPU.
The vocabulary (vocab.json next to this file) maps how the model mishears a
word back to its real spelling; see apply_vocab.
"""

import difflib
import json
import os
import re
import subprocess
import sys
import threading

import numpy as np
import sherpa_onnx

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "models", "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8")
VOCAB = os.path.join(HERE, "vocab.json")
COMMON = os.path.join(HERE, "common-words.txt")
RATE = 16000
MIN_SAMPLES = int(RATE * 0.3)

out_lock = threading.Lock()


def emit(**obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


# ── vocabulary ──

_vocab_cache = {"stamp": None, "entries": []}

CONTRACTIONS = {
    "i'm", "i've", "i'll", "i'd", "don't", "can't", "won't", "it's", "isn't", "didn't", "doesn't",
    "wasn't", "aren't", "weren't", "couldn't", "wouldn't", "shouldn't", "haven't", "hasn't", "hadn't",
    "you're", "you'll", "you've", "you'd", "we're", "we'll", "we've", "they're", "they'll", "they've",
    "that's", "there's", "what's", "let's", "he's", "she's", "who's", "here's",
}


def _load_common():
    try:
        with open(COMMON) as f:
            return {w.strip().lower() for w in f if w.strip()} | CONTRACTIONS
    except OSError:
        return set(CONTRACTIONS)


COMMON_WORDS = _load_common()


def is_common(phrase):
    """Every word of the phrase is everyday English (top ~10k words)."""
    words = norm(phrase).split()
    return bool(words) and all(w in COMMON_WORDS or w.replace("'", "") in COMMON_WORDS for w in words)


def norm(s):
    s = s.lower().replace("-", " ")
    s = re.sub(r"[^\w' ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def load_vocab(force=False):
    """
    Forms made only of everyday English ("April", "I know") would rewrite normal
    speech, so they are left out unless the word pins them.
    """
    try:
        st = os.stat(VOCAB)
        stamp = (st.st_mtime_ns, st.st_size, st.st_ino)
    except OSError:
        _vocab_cache.update(stamp=None, entries=[])
        return []
    if force or stamp != _vocab_cache["stamp"]:
        try:
            with open(VOCAB) as f:
                data = json.load(f)
            entries = []
            for e in data.get("words", []):
                word = (e.get("word") or "").strip()
                if not word:
                    continue
                pinned = {norm(p) for p in e.get("pinned", [])}
                forms = {norm(h) for h in e.get("heard", [])
                         if norm(h) and (not is_common(h) or norm(h) in pinned)}
                forms.add(norm(word))
                entries.append({"word": word, "forms": forms,
                                "squashed": {f.replace(" ", "") for f in forms}})
            _vocab_cache.update(stamp=stamp, entries=entries)
        except (OSError, ValueError) as err:
            emit(event="log", msg="vocab unreadable: %s" % err)
    return _vocab_cache["entries"]


def apply_vocab(text, entries):
    """
    Replace any run of 1-4 words that matches how a vocabulary word was heard
    (exactly, ignoring case, punctuation and spacing) with its real spelling.
    If no run matches exactly, a run of 5+ letters that comes very close to a
    learned form (difflib >= 0.86, similar length, no more words than that
    form) counts too, so a slightly new mishearing still lands without eating
    the words around it. Longest runs win, left to right; leading and trailing
    punctuation and a possessive 's are kept.
    """
    if not entries or not text:
        return text
    toks = list(re.finditer(r"\S+", text))

    def window(i, n):
        seg = " ".join(t.group() for t in toks[i:i + n])
        poss = ""
        m = re.search(r"['\u2019]s([^\w]*)$", seg)
        if m:
            poss = "'s"
            seg = seg[: m.start()] + m.group(1)
        return norm(seg), poss

    def match(i):
        top = min(4, len(toks) - i)
        for n in range(top, 0, -1):
            words, poss = window(i, n)
            if not words:
                continue
            sq = words.replace(" ", "")
            for e in entries:
                if words in e["forms"] or sq in e["squashed"]:
                    return n, e["word"], poss
        for n in range(top, 0, -1):
            words, poss = window(i, n)
            sq = words.replace(" ", "")
            if len(sq) < 5 or is_common(words):
                continue
            for e in entries:
                for f in e["forms"]:
                    fs = f.replace(" ", "")
                    if n > len(f.split()) or not (0.8 <= len(sq) / len(fs) <= 1.25):
                        continue
                    if difflib.SequenceMatcher(None, sq, fs).ratio() >= 0.86:
                        return n, e["word"], poss
        return None

    out = []
    i = 0
    while i < len(toks):
        hit = match(i)
        if hit:
            n, word, poss = hit
            last = toks[i + n - 1].group()
            tail = re.search(r"[^\w']*$", last).group()
            lead = re.match(r"^[^\w']*", toks[i].group()).group()
            out.append(lead + word + poss + tail)
            i += n
        else:
            out.append(toks[i].group())
            i += 1
    return " ".join(out)


# ── voice commands ──

_SENT_END = re.compile(r"[.!?]\s+")


def _clean_item(s):
    s = s.strip().strip(".,;:!?").strip()
    s = re.sub(r"^(and|then|also)\s+", "", s, flags=re.I)
    return s[:1].upper() + s[1:] if s else s


def _split_items(body):
    parts = [p for p in re.split(r"\s*[,;]\s*|\.\s+|\.$|\s+next item\s+", body, flags=re.I) if p and p.strip(" .")]
    if not parts:
        return []
    if len(parts) == 1:
        parts = re.split(r"\s+and\s+", parts[0], flags=re.I)
    else:
        last = parts[-1]
        if re.match(r"^\s*and\s+", last, flags=re.I):
            parts[-1] = last
        elif re.search(r"\s+and\s+", last, flags=re.I):
            parts[-1:] = re.split(r"\s+and\s+", last, maxsplit=1, flags=re.I)
    return [i for i in (_clean_item(p) for p in parts) if i]


_LIST_RE = re.compile(r"(?:^|(?<=[.!?]\s))(?P<kind>numbered list|bullet(?:ed)? list|list)\b[:,.]?\s*", re.I)
_END_LIST_RE = re.compile(r"[,.]?\s*\bend (?:of )?list\b[,.:]?\s*", re.I)


def apply_lists(text):
    """
    "List: banana, apple, carrot" -> bullet lines, "numbered list ..." -> 1. 2. 3.
    The command must open the take or a sentence, so "make a list of" stays
    prose. Items run to "end list" or the end of the take, split on commas,
    pauses (full stops) or a final "and"; text before the command stays as
    its own line, text after "end list" carries on below.
    """
    m = _LIST_RE.search(text)
    if not m:
        return text
    before = text[: m.start()].rstrip()
    rest = text[m.end():]
    after = ""
    e = _END_LIST_RE.search(rest)
    if e:
        rest, after = rest[: e.start()], rest[e.end():].strip()
    items = _split_items(rest)
    if not items:
        return text
    numbered = m.group("kind").lower().startswith("numbered")
    lines = [("%d. %s" % (n + 1, it)) if numbered else ("- " + it) for n, it in enumerate(items)]
    out = "\n".join(lines)
    if before:
        out = before + "\n" + out
    if after:
        out = out + "\n" + apply_lists(after[:1].upper() + after[1:])
    return out


def apply_quotes(text):
    """
    open quote ... close quote / end quote / unquote -> "..." hugging the words.
    A close only counts after an open, so the idiom "quote unquote" and a
    stray "unquote" stay as spoken.
    """
    opener = re.compile(r"\bopen (?:quote|quotation)s?(?: marks?)?\b[,.:]?\s*", re.I)
    closer = re.compile(r"[,.]?\s*\b(?:(?:close|end) (?:quote|quotation)s?(?: marks?)?|unquote)\b", re.I)
    out = ""
    while True:
        o = opener.search(text)
        if not o:
            break
        c = closer.search(text, o.end())
        if not c:
            break
        out += text[: o.start()] + '"' + text[o.end(): c.start()] + '"'
        text = text[c.end():]
    out += text
    # A stop the model put after the closing quote stays outside it, and a
    # quote that opens a sentence starts with a capital.
    out = re.sub(r'"\s+([.,!?])', r'"\1', out)
    return re.sub(r'(^|[.!?]\s+)"([a-z])', lambda m: m.group(1) + '"' + m.group(2).upper(), out)


def apply_breaks(text):
    """new line / new paragraph -> line breaks, the next word capitalised."""
    def brk(n):
        def f(m):
            return "\n" * n
        return f
    text = re.sub(r"[,.]?\s*\bnew paragraph\b[,.:]?\s*", brk(2), text, flags=re.I)
    text = re.sub(r"[,.]?\s*\bnew line\b[,.:]?\s*", brk(1), text, flags=re.I)
    return re.sub(r"\n([a-z])", lambda m: "\n" + m.group(1).upper(), text)


def apply_commands(text):
    text = apply_quotes(text)
    text = apply_lists(text)
    text = apply_breaks(text)
    return re.sub(r"[ \t]+\n", "\n", text).strip()


def type_text(text):
    """
    Type into the focused app. Line breaks go out as Shift+Enter so a list
    dictated into a chat box doesn't send the message halfway.
    """
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if i:
            subprocess.run(["wtype", "-M", "shift", "-k", "Return", "-m", "shift"], check=False, timeout=5)
        if line:
            subprocess.run(["wtype", "--", line], check=False, timeout=30)
    if lines and lines[-1]:
        subprocess.run(["wtype", "--", " "], check=False, timeout=5)


# ── recording ──

class Take:
    def __init__(self):
        self.chunks = []
        self.proc = subprocess.Popen(
            ["pw-record", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        while True:
            b = self.proc.stdout.read(3200)
            if not b:
                break
            self.chunks.append(b)

    def finish(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.reader.join(timeout=1)
        raw = b"".join(self.chunks)
        raw = raw[: len(raw) - (len(raw) % 2)]
        return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


# ── main ──

def main():
    try:
        rec = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=os.path.join(MODEL, "encoder.int8.onnx"),
            decoder=os.path.join(MODEL, "decoder.int8.onnx"),
            joiner=os.path.join(MODEL, "joiner.int8.onnx"),
            tokens=os.path.join(MODEL, "tokens.txt"),
            model_type="nemo_transducer",
            num_threads=min(8, os.cpu_count() or 4),
        )
    except Exception as err:  # noqa: BLE001
        emit(event="error", msg="model failed to load: %s" % err)
        return 1

    # Warm the graph so the first real take is as fast as the rest.
    s = rec.create_stream()
    s.accept_waveform(RATE, np.zeros(RATE // 2, dtype=np.float32))
    rec.decode_stream(s)
    emit(event="ready")

    take = None
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        cmd = msg.get("cmd")
        if cmd == "start":
            if take:
                take.finish()
            try:
                take = Take()
            except OSError as err:
                take = None
                emit(event="error", msg="mic unavailable: %s" % err)
        elif cmd == "reload":
            load_vocab(force=True)
        elif cmd == "cancel":
            if take:
                take.finish()
                take = None
        elif cmd == "stop":
            if not take:
                emit(event="empty")
                continue
            audio = take.finish()
            take = None
            if len(audio) < MIN_SAMPLES:
                emit(event="empty")
                continue
            # A short tail of silence helps the decoder close the last word.
            audio = np.concatenate([audio, np.zeros(RATE // 4, dtype=np.float32)])
            st = rec.create_stream()
            st.accept_waveform(RATE, audio)
            rec.decode_stream(st)
            raw = st.result.text.strip()
            if not raw:
                emit(event="empty")
                continue
            if msg.get("mode") == "teach":
                emit(event="heard", text=raw)
                continue
            text = apply_commands(apply_vocab(raw, load_vocab()))
            try:
                subprocess.run(["wl-copy", "--", text], check=False, timeout=3)
                type_text(text)
            except (OSError, subprocess.TimeoutExpired) as err:
                emit(event="error", msg="could not type: %s" % err)
                continue
            emit(event="done", text=text, raw=raw)
    if take:
        take.finish()
    return 0


if __name__ == "__main__":
    sys.exit(main())
