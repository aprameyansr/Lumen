#!/usr/bin/env python3
"""
Lumen dictation service. Spawned by Quickshell (Singletons/Dictate.qml) while
dictation is enabled; talks over stdin/stdout, one JSON object per line.

  in   {"cmd": "start", "mic": "<source node name>"}
                                        begin recording from that mic (falls
                                        back to the laptop mic if it's gone)
       {"cmd": "stop", "mode": "type"}  finish: transcribe, apply vocabulary,
                                        type into the focused app + copy
       {"cmd": "stop", "mode": "teach"} finish: transcribe raw, report only
       {"cmd": "cancel"}                drop the take
  out  {"event": "engine", "name": "whisper"|"parakeet", "note": "..."}
       {"event": "ready"}
       {"event": "hot"}                 real sound is arriving (a Bluetooth
                                        mic is silent for ~1 s while it
                                        switches to headset mode)
       {"event": "done", "text": "...", "raw": "..."}
       {"event": "heard", "text": "..."}
       {"event": "empty"}               nothing intelligible was said
       {"event": "error", "msg": "..."}

Two engines, picked with --engine (Settings → Dictation → Engine):
  whisper   Whisper large-v3-turbo on the GPU (whisper.cpp + Vulkan), the most
            accurate, ~1 s a take. Runs as a private whisper-server child on a
            unix socket (no network port) that dies with this process. Your
            Vocabulary words are passed to it as hints.
  parakeet  NVIDIA Parakeet TDT 0.6B v2 (int8) through sherpa-onnx on the CPU,
            the fastest, ~0.5 s a take.
If Whisper can't start (not built, no GPU driver) the service falls back to
Parakeet and reports it with an "engine" event.

The vocabulary (vocab.json next to this file) maps how the model mishears a
word back to its real spelling; see apply_vocab.
"""

import atexit
import ctypes
import difflib
import http.client
import io
import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid
import wave

import numpy as np
import sherpa_onnx

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "models", "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8")
WHISPER_SERVER = os.path.join(HERE, "whisper", "whisper-server")
# Full large-v3 (5-bit): most accurate on your voice in the 2026-11-26 test (bakeoff/). Was large-v3-turbo-q8_0.
WHISPER_MODEL = os.path.join(HERE, "models", "ggml-large-v3-q5_0.bin")
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
    s = re.sub(r"^(?:\d+[.)]|[-•*])\s*", "", s)
    s = re.sub(r"^(and|then|also)\s+", "", s, flags=re.I)
    return s[:1].upper() + s[1:] if s else s


def _split_items(body):
    # Whisper sometimes writes the numbers itself ("1. Banana, 2. Apple").
    body = re.sub(r"(^|[\s,;])\d+[.)]\s+", r"\1, ", body)
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
# Only searched for after a list has started, so the looser forms Whisper
# tends to write for "end list" ("and list", "endless") are safe here.
_END_LIST_RE = re.compile(r"[,.]?\s*\b(?:end (?:of (?:the )?)?list|end the list|and list|endless|stop (?:the )?list)\b[,.:!]?\s*", re.I)


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


# "court" too: Whisper often hears "quote" that way in Indian English.
_QUOTE_OPEN = re.compile(r"\bopen (?:quote|quotation|court)s?(?: marks?)?\b[,.:]?\s*", re.I)
_QUOTE_CLOSE = re.compile(r"[,.]?\s*\b(?:(?:close|end) (?:quote|quotation|court)s?(?: marks?)?|unquote|uncourt)\b", re.I)
_SPEECH = (r"said|says|say|asked|asks|ask|told (?:me|him|her|them|us|you)|tells (?:me|him|her|them|us|you)|"
           r"wrote|writes|replied|replies|answered|added|goes|went|was like|is like|shouted|yelled|"
           r"whispered|texted|messaged|tweeted|posted|repeat|repeated|quoting")
# "quote" on its own starts a quote only after a speech word or at a sentence
# start, so "get a quote from the plumber" stays prose.
_QUOTE_BARE = re.compile(r"(?P<pre>^|[.!?]\s+)(?:quote\b|court(?=\s*[,.:]))(?!\s*,?\s*unquote)[,.:]?\s*"
                         r"|(?P<pre2>\b(?:" + _SPEECH + r")\s*,?\s+)(?:quote|court)\b(?!\s*,?\s*unquote)[,.:]?\s*", re.I)


# "quote," with a pause after it starts a quote anywhere, unless it's a noun:
# "a quote, …", "the quote, …", "your quote, …" stay prose.
_QUOTE_PAUSE = re.compile(r"\b(?:quote|court)\s*[,:]\s*(?=\w)", re.I)
_DETERMINERS = {"a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her", "its",
                "our", "their", "another", "any", "each", "every", "which", "what", "no", "one", "first", "best"}


def _find_bare_quote(text):
    """The earliest bare-quote command: (start, body_start, text kept before the quote mark)."""
    found = []
    q = _QUOTE_BARE.search(text)
    if q:
        found.append((q.start(), q.end(), q.group("pre") or q.group("pre2") or ""))
    for m in _QUOTE_PAUSE.finditer(text):
        prev = re.search(r"(\w+)\W*$", text[:m.start()])
        if prev and prev.group(1).lower() in _DETERMINERS:
            continue
        found.append((m.start(), m.end(), ""))
        break
    return min(found) if found else None


def _cap(s):
    return s[:1].upper() + s[1:]


def apply_quotes(text):
    """
    Two ways to quote:
      open quote ... close quote / end quote / unquote   -> "..."
      he said quote I am him                              -> he said "I am him"
    The second runs to "unquote"/"end quote" if one is said, otherwise to the
    next pause, i.e. the next comma or full stop the model wrote. The idiom
    "quote unquote" and a stray "unquote" stay as spoken.
    """
    out = ""
    while True:
        o = _QUOTE_OPEN.search(text)
        if not o:
            break
        c = _QUOTE_CLOSE.search(text, o.end())
        if not c:
            break
        out += text[: o.start()] + '"' + text[o.end(): c.start()] + '"'
        text = text[c.end():]
    text = out + text

    out = ""
    while True:
        q = _find_bare_quote(text)
        if not q:
            break
        q_start, start, keep = q
        c = _QUOTE_CLOSE.search(text, start)
        p = re.search(r"\w[^,.;:!?]*?(?=[,.;:!?]|$)", text[start:])
        stop = start + p.end() if p else len(text)
        if c and c.start() <= stop:
            body, rest = text[start:c.start()], text[c.end():]
        else:
            body, rest = text[start:stop], text[stop:]
        body = body.strip()
        if not body:
            out += text[:start]
            text = text[start:]
            continue
        out += text[:q_start] + keep + '"' + _cap(body) + '"'
        text = rest
    out += text

    # A stop the model put after the closing quote stays outside it, and a
    # quote that opens a sentence starts with a capital.
    out = re.sub(r'"\s+([.,!?;:])', r'"\1', out)
    out = re.sub(r'\s{2,}', " ", out)
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

def resolve_mic(choice):
    """
    The PipeWire source to record from. `choice` is a source's node name picked
    in Settings → Dictation; if that mic isn't there (earbuds off), fall back to
    the laptop's own mic, then the system default. "builtin" means the laptop
    mic and "default" the system default, as older settings stored them.
    Returns a target, or None for the system default.
    """
    try:
        out = subprocess.run(["pactl", "list", "sources", "short"], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    names = [l.split()[1] for l in out.splitlines() if len(l.split()) > 1 and ".monitor" not in l.split()[1]]
    if choice and choice not in ("builtin", "default") and choice in names:
        return choice
    if choice == "default":
        return None
    for n in names:
        if n.startswith("alsa_input."):
            return n
    return None


class Take:
    def __init__(self, target=None):
        self.chunks = []
        self.hot = False
        cmd = ["pw-record", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16"]
        if target:
            cmd += ["--target", target]
        self.proc = subprocess.Popen(cmd + ["-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        while True:
            b = self.proc.stdout.read(3200)
            if not b:
                break
            self.chunks.append(b)
            if not self.hot and len(b) >= 2 and np.abs(np.frombuffer(b[: len(b) // 2 * 2], dtype=np.int16)).max() > 3:
                self.hot = True
                emit(event="hot")

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


# ── engines ──

class Parakeet:
    name = "parakeet"

    def __init__(self):
        self.rec = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=os.path.join(MODEL, "encoder.int8.onnx"),
            decoder=os.path.join(MODEL, "decoder.int8.onnx"),
            joiner=os.path.join(MODEL, "joiner.int8.onnx"),
            tokens=os.path.join(MODEL, "tokens.txt"),
            model_type="nemo_transducer",
            num_threads=min(8, os.cpu_count() or 4),
        )
        self.transcribe(np.zeros(RATE // 2, dtype=np.float32))

    def transcribe(self, audio):
        # A short tail of silence helps the decoder close the last word.
        audio = np.concatenate([audio, np.zeros(RATE // 4, dtype=np.float32)])
        st = self.rec.create_stream()
        st.accept_waveform(RATE, audio)
        self.rec.decode_stream(st)
        return st.result.text.strip()


class _UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=120)
        self.unix_path = path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(120)
        s.connect(self.unix_path)
        self.sock = s


def _die_with_parent():
    ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


# Whisper's habit on near-silence: polite phrases nobody said.
_HALLUCINATIONS = {"thank you.", "thank you", "thanks for watching!", "thanks for watching.", "you", "bye.", "."}


def collapse_repeats(text):
    """Safety net: a phrase of 1-8 words said 3+ times back to back is kept once."""
    words = text.split()
    changed = True
    while changed:
        changed = False
        for n in range(1, 9):
            i = 0
            while i + 3 * n <= len(words):
                chunk = words[i:i + n]
                k = 1
                while words[i + k * n:i + (k + 1) * n] == chunk:
                    k += 1
                if k >= 3:
                    words = words[:i + n] + words[i + k * n:]
                    changed = True
                i += 1
    return " ".join(words)


class Whisper:
    """
    Loaded only when needed: the first Right Alt press starts whisper-server
    while you speak (~0.7 s, well under a sentence), and it is shut down again
    after IDLE seconds unused, which gives back ~1.1 GB of RAM.
    """
    name = "whisper"
    IDLE = float("inf")  # kept loaded always (was 600 s); ~1.85 GB RAM

    def __init__(self, sock=None):
        for f in (WHISPER_SERVER, WHISPER_MODEL):
            if not os.path.exists(f):
                raise RuntimeError("it isn't installed, run setup.sh")
        self.proc = None
        self.lock = threading.Lock()
        self.busy = False          # a take is being recorded
        self.last = time.time()
        if sock:                   # borrow a server someone else runs (voice test)
            self.sock, self.external = sock, True
            return
        self.external = False
        run = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        # Sockets left by a service that was killed outright (no cleanup).
        for f in os.listdir(run):
            m = re.fullmatch(r"lumen-whisper-(\d+)\.sock", f)
            if m and not os.path.exists("/proc/" + m.group(1)):
                try:
                    os.unlink(os.path.join(run, f))
                except OSError:
                    pass
        self.sock = os.path.join(run, "lumen-whisper-%d.sock" % os.getpid())
        atexit.register(self.stop)
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        self.want = threading.Event()   # someone needs the server loaded
        self.tried = threading.Event()  # a load attempt finished
        self.err = None
        # One long-lived thread starts and stops the server: whisper-server is
        # tied to the thread that spawned it (PR_SET_PDEATHSIG), so a short-lived
        # loader thread would take it down with it when it ended.
        threading.Thread(target=self._keeper, daemon=True).start()
        self.want.set()  # load at start so the first take is instant

    def _ensure(self):
        """Start the server if it isn't running. Call with self.lock held."""
        if self.external or (self.proc and self.proc.poll() is None):
            return
        self.proc = subprocess.Popen(
            [WHISPER_SERVER, "-m", WHISPER_MODEL, "--host", self.sock, "-l", "en", "-nt", "-t", "4"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=_die_with_parent)
        for _ in range(600):
            if self.proc.poll() is not None:
                raise RuntimeError("the GPU driver may be missing")
            if os.path.exists(self.sock):
                try:
                    c = _UnixHTTP(self.sock)
                    c.connect()
                    c.close()
                    break
                except OSError:
                    pass
            time.sleep(0.05)
        else:
            self._kill()
            raise RuntimeError("it didn't start in time")
        self._request(np.zeros(RATE // 2, dtype=np.float32))

    def _running(self):
        return self.external or (self.proc is not None and self.proc.poll() is None)

    def _load(self):
        """Ask the keeper to load and wait for it. Raises if loading failed."""
        if self._running():
            return
        self.tried.clear()
        self.want.set()
        self.tried.wait()
        if self.err:
            raise self.err

    def _keeper(self):
        while True:
            if self.want.wait(timeout=30):
                self.want.clear()
                with self.lock:
                    try:
                        self._ensure()
                        self.err = None
                    except Exception as err:  # noqa: BLE001
                        self.err = err
                self.tried.set()
            elif self.proc and not self.busy and time.time() - self.last > self.IDLE:
                with self.lock:
                    if not self.busy and time.time() - self.last > self.IDLE:
                        self._kill()

    def prepare(self):
        """Right Alt went down: load in the background while you talk."""
        self.busy = True
        self.last = time.time()
        if not self._running():
            self.want.set()

    def done(self):
        self.busy = False
        self.last = time.time()

    def _kill(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None
        try:
            os.unlink(self.sock)
        except OSError:
            pass

    @staticmethod
    def prompt(words):
        """
        Punctuated so Whisper punctuates, plus your Vocabulary so it spells them
        right. The quote line makes it expect the word "quote", which it
        otherwise hears as "coat" or "court" in Indian English.
        """
        base = "Hello, how are you? I'm doing well. He said, quote, I'll be there."
        return base + (" Names: " + ", ".join(words) + "." if words else "")

    def stop(self):
        if not self.external:
            self._kill()

    def transcribe(self, audio):
        self._load()
        with self.lock:
            try:
                return self._request(audio)
            finally:
                self.last = time.time()

    def _request(self, audio):
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
        words = [e["word"] for e in load_vocab()]
        fields = {
            "language": "en",
            "prompt": self.prompt(words),
            "response_format": "json",
            "no_timestamps": "true",
            "temperature": "0",
            # Retries rescue unclear speech, so they stay on, but in big steps
            # (0 → 0.4 → 0.8): at most 3 passes instead of 6, which is what made
            # long lists crawl.
            "temperature_inc": "0.4",
            # Size the encoder window to the take instead of a fixed 30 s, but
            # never below 768: a tight window on a short take makes Whisper loop
            # ("hello hello hello…") and take seconds doing it.
            "audio_ctx": str(max(768, min(1500, int(len(audio) / RATE * 50) + 128))),
        }
        b = uuid.uuid4().hex
        body = io.BytesIO()
        for k, v in fields.items():
            body.write(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (b, k, v)).encode())
        body.write(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"take.wav\"\r\n"
                    "Content-Type: audio/wav\r\n\r\n" % b).encode())
        body.write(buf.getvalue())
        body.write(("\r\n--%s--\r\n" % b).encode())
        c = _UnixHTTP(self.sock)
        c.request("POST", "/inference", body.getvalue(), {"Content-Type": "multipart/form-data; boundary=" + b})
        r = c.getresponse()
        data = r.read()
        c.close()
        if r.status != 200:
            raise RuntimeError("whisper-server %d" % r.status)
        text = collapse_repeats(" ".join(json.loads(data).get("text", "").split()).strip())
        return "" if text.lower() in _HALLUCINATIONS else text


def pick_engine():
    want = "whisper"
    if "--engine" in sys.argv:
        i = sys.argv.index("--engine")
        if i + 1 < len(sys.argv):
            want = sys.argv[i + 1]
    if want == "whisper":
        try:
            eng = Whisper()
            emit(event="engine", name="whisper", note="")
            return eng
        except Exception as err:  # noqa: BLE001
            note = "Whisper couldn't start: %s. Using Parakeet instead." % err
    else:
        note = ""
    eng = Parakeet()
    emit(event="engine", name="parakeet", note=note)
    return eng


# ── main ──

def main():
    try:
        engine = pick_engine()
    except Exception as err:  # noqa: BLE001
        emit(event="error", msg="model failed to load: %s" % err)
        return 1
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
            if hasattr(engine, "prepare"):
                engine.prepare()
            try:
                take = Take(resolve_mic(msg.get("mic", "default")))
            except OSError as err:
                take = None
                emit(event="error", msg="mic unavailable: %s" % err)
        elif cmd == "reload":
            load_vocab(force=True)
        elif cmd == "cancel":
            if take:
                take.finish()
                take = None
            if hasattr(engine, "done"):
                engine.done()
        elif cmd == "stop":
            if not take:
                emit(event="empty")
                continue
            audio = take.finish()
            take = None
            if hasattr(engine, "done"):
                engine.done()
            if len(audio) < MIN_SAMPLES:
                emit(event="empty")
                continue
            try:
                raw = engine.transcribe(audio)
            except Exception as err:  # noqa: BLE001
                emit(event="error", msg="%s: %s" % (engine.name, err))
                continue
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
