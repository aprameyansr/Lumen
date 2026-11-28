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
  whisper   Whisper large-v3 on the GPU (whisper.cpp; encoder via OpenVINO,
            decoder via Vulkan), the most accurate, ~1 s a take. Long takes
            are transcribed in pieces while you talk (Streamer), so they
            finish about as fast as short ones. Runs as a private whisper-server child on a
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
# 2026-11-27: build with Intel OpenVINO; the encoder runs through OpenVINO on the Arc GPU
# (models/Whisper Large-encoder-openvino.xml, ~25% faster takes, same accuracy). Falls back to the Vulkan-only build.
WHISPER_SERVER_OV = os.path.join(HERE, "whisper", "whisper-server-ov")
WHISPER_OV_LIBS = os.path.join(HERE, "whisper", "ov-libs")
# Full large-v3 (5-bit): most accurate on your voice in the 2026-11-26 test (bakeoff/). Was large-v3-turbo-q8_0.
# Named link to ggml-large-v3-q5_0.bin so the system monitor shows "Whisper Large".
WHISPER_MODEL = os.path.join(HERE, "models", "Whisper Large.bin")
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


_BRACKET_WORD = r"(?:bracket|parenthesis|parentheses|paren)"
_BRACKET_OPEN = re.compile(r"[,.]?\s*\bopen " + _BRACKET_WORD + r"s?\b[,.:]?\s*", re.I)
_BRACKET_CLOSE = re.compile(r"[,.]?\s*\b(?:close|end) " + _BRACKET_WORD + r"s?\b", re.I)
_BRACKET_BARE = re.compile(r"[,.]?\s*\b" + _BRACKET_WORD + r"\b[,.:]?\s*(?=\w)", re.I)
# "bracket" as a noun stays prose: "a bracket", "tax bracket", "the age bracket, …"
_BRACKET_NOUN = _DETERMINERS | {"tax", "age", "income", "price", "salary", "wall", "shelf", "metal", "steel", "mounting",
                                "lower", "higher", "upper", "top", "bottom", "same", "different", "winners", "losers",
                                "tournament", "playoff", "square", "curly", "round", "angle", "closing", "opening", "in"}


def apply_brackets(text):
    """
    Two ways to bracket, like quotes:
      open bracket ... close bracket            -> (...)
      continuous assessment bracket CIA, ...    -> continuous assessment (CIA), ...
    The short form runs to "close bracket" if said, otherwise to the next
    pause (comma or full stop). After a/the/tax/age… it's the noun and stays.
    """
    out = ""
    while True:
        o = _BRACKET_OPEN.search(text)
        c = _BRACKET_CLOSE.search(text, o.end()) if o else None
        if not c:
            break
        out += text[: o.start()] + " (" + text[o.end(): c.start()].strip() + ")"
        text = text[c.end():]
    text = out + text

    out = ""
    pos = 0
    for m in _BRACKET_BARE.finditer(text):
        if m.start() < pos:
            continue
        prev = re.search(r"(\w+)\W*$", text[:m.start()])
        # a pause before it ("Part A, bracket, three marks") makes it the command
        paused = text[m.start()] in ",."
        if prev and not paused and prev.group(1).lower() in _BRACKET_NOUN:
            continue
        c = _BRACKET_CLOSE.search(text, m.end())
        p = re.search(r"[,.;:!?]|$", text[m.end():])
        stop = m.end() + p.start()
        if c and c.start() <= stop:
            body, after = text[m.end():c.start()], c.end()
        else:
            body, after = text[m.end():stop], stop
        if not body.strip():
            continue
        out += text[pos:m.start()] + " (" + body.strip() + ")"
        pos = after
    out += text[pos:]
    out = re.sub(r"\(\s+", "(", out)
    out = re.sub(r"\s+\)", ")", out)
    out = re.sub(r"\s+([,.;:!?])", r"\1", out)
    return re.sub(r"^\s+|(?<=\S)\s{2,}", lambda m: "" if m.start() == 0 else " ", out)


# A lettered part: a single letter opening the take, a sentence or a clause,
# then a hyphen/stop/bracket/colon/comma ("A-construct", "B. Construct", "C) Convert").
# A letter followed straight by another lone letter ("C-A", "C-I-A") is a
# spelled-out abbreviation, not a part.
_LETTER = re.compile(r"(?:^|(?<=[.:;!?,]\s)|(?<=following\s))(?P<l>[A-Za-z])\s*[-–.):,]\s*(?=[A-Za-z])(?![A-Za-z](?:\W|$))")


def apply_letters(text):
    """
    A, B, C... said in order become lettered parts on their own lines:
      "Perform the following: A-construct x. B-construct y. C-convert z."
      -> Perform the following:\nA. Construct x.\nB. Construct y.\nC. Convert z.
    Only a run starting at A with at least A and B counts, so letters used
    as labels out of order ("C - continuous …, M - mid-semester …") stay as
    they are. The last part ends at its first full stop or at "end list".
    """
    marks = [m for m in _LETTER.finditer(text)]
    best = []
    for i, m in enumerate(marks):
        if m.group("l").upper() != "A":
            continue
        run = [m]
        for n in marks[i + 1:]:
            if n.group("l").upper() == chr(ord(run[-1].group("l").upper()) + 1):
                run.append(n)
        if len(run) >= 2:
            best = run
            break
    if not best:
        return text
    bodies = []
    for k, m in enumerate(best):
        end = best[k + 1].start() if k + 1 < len(best) else None
        if end is None:
            tail = text[m.end():]
            e = _END_LIST_RE.search(tail)
            s_ = re.search(r"[.!?](?=\s|$)", tail)
            cut = min([x for x in (e.start() if e else None, s_.end() if s_ else None) if x is not None], default=len(tail))
            body = tail[:cut]
            after = tail[e.end():] if e and e.start() == cut else tail[cut:]
        else:
            body = text[m.end():end]
        body = body.strip().rstrip(",;").strip()
        if len(body.split()) < 2:
            return text
        bodies.append(body)
    before = text[: best[0].start()].rstrip()
    lines = ["%s. %s" % (m.group("l").upper(), _cap(b)) for m, b in zip(best, bodies)]
    out = "\n".join(lines)
    if before:
        out = before + "\n" + out
    after = after.strip()
    if after:
        out += "\n" + _cap(after)
    return out


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
    text = apply_brackets(text)
    text = apply_letters(text)
    text = apply_lists(text)
    text = apply_breaks(text)
    return re.sub(r"[ \t]+\n", "\n", text).strip()


_TERMINALS = {"kitty", "foot", "footclient", "alacritty", "wezterm", "org.wezfurlong.wezterm", "ghostty",
              "com.mitchellh.ghostty", "konsole", "org.kde.konsole", "gnome-terminal", "org.gnome.terminal",
              "org.gnome.ptyxis", "xterm", "urxvt", "st", "terminator", "tilix", "com.gexperts.tilix"}


def _focused_is_terminal():
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=1).stdout
        w = json.loads(out or "{}")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return False
    return (w.get("class") or w.get("initialClass") or "").lower() in _TERMINALS


def _type_out(text):
    """Fallback: type letter by letter; line breaks as Shift+Enter so a chat box doesn't send."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if i:
            subprocess.run(["wtype", "-M", "shift", "-k", "Return", "-m", "shift"], check=False, timeout=5)
        if line:
            subprocess.run(["wtype", "--", line], check=False, timeout=30)
    if lines and lines[-1]:
        subprocess.run(["wtype", "--", " "], check=False, timeout=5)


def type_text(text):
    """
    Put the text into the focused app by pasting it (it's already on the
    clipboard): instant at any length, where typing it out letter by letter
    took ~2 s for a long take. Terminals paste with Ctrl+Shift+V, other apps
    with Ctrl+V. A pasted list keeps its line breaks without pressing Enter,
    so a chat box doesn't send halfway. The trailing space is typed.
    """
    if _focused_is_terminal():
        # Hyprland sends it straight to the window: wtype's Ctrl+Shift+V reaches
        # your Hyprland shortcuts as Ctrl+Shift+Escape (its "v" is read as
        # Escape) and opened Resources.
        r = subprocess.run(["hyprctl", "dispatch", "hl.dsp.send_shortcut({mods='CTRL SHIFT', key='V'})"],
                           capture_output=True, text=True, timeout=3)
        if r.returncode != 0 or "error" in (r.stdout + r.stderr).lower():
            _type_out(text)
            return
    else:
        # wtype, because apps like VSCodium ignore Hyprland's sent shortcut.
        # Hyprland sees this as Ctrl+Escape, which isn't bound.
        subprocess.run(["wtype", "-M", "ctrl", "-k", "v", "-m", "ctrl"], check=False, timeout=5)
    if text and not text.endswith("\n"):
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


class Streamer:
    """
    Transcribe while you talk (Whisper only). Every quarter second it looks at
    the audio since the last cut; once there's at least MIN_SEG of it, it cuts
    in the middle of a natural pause and transcribes that piece in the
    background, with the text before it as context. On release only the last
    stretch is left, so a long take finishes about as fast as a short one.
    Takes shorter than MIN_SEG (4 s) are never cut: they work exactly as before.
    """
    FRAME = RATE // 50        # 20 ms frames for the loudness check
    MIN_SEG = 4 * RATE        # never cut a piece shorter than this (keeps context)
    MAX_SEG = 8 * RATE        # no pause by here (fluent speech): cut at the quietest gap between words
    PAUSE = 0.4               # seconds of quiet that count as a pause (0.25 cut inside words)

    def __init__(self, engine, take):
        self.engine, self.take = engine, take
        self.audio = np.zeros(0, dtype=np.float32)
        self.seen = 0               # take.chunks already copied into self.audio
        self.cut = 0                # samples already handed to the worker
        self.texts = []
        self.jobs = []
        self.cv = threading.Condition()
        self.stopped = False
        threading.Thread(target=self._watch, daemon=True).start()
        threading.Thread(target=self._work, daemon=True).start()

    def _grow(self):
        n = len(self.take.chunks)
        if n > self.seen:
            raw = b"".join(self.take.chunks[self.seen:n])
            self.seen = n
            raw = raw[: len(raw) - (len(raw) % 2)]
            self.audio = np.concatenate([self.audio, np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0])

    @classmethod
    def find_cut(cls, pending):
        """Where to cut `pending` (samples from its start), or None to keep listening."""
        if len(pending) < cls.MIN_SEG:
            return None
        f = cls.FRAME
        n = len(pending) // f
        rms = np.sqrt(np.mean(pending[: n * f].reshape(n, f) ** 2, axis=1))
        floor, speech = np.percentile(rms, 10), np.percentile(rms, 90)
        # relative to this take's own levels: the laptop mic has a loud noise floor
        quiet = rms < floor + 0.35 * (speech - floor)
        need = int(cls.PAUSE * 50)
        first = cls.MIN_SEG // f
        run = 0
        for i in range(n):
            run = run + 1 if quiet[i] else 0
            if run >= need and i - run + 1 + run // 2 >= first:
                start = i - run + 1
                # keep going to the end of this pause, then cut in its middle
                j = i
                while j + 1 < n and quiet[j + 1]:
                    j += 1
                if j + 1 >= n:      # pause still going on: cut a little into it
                    return (start + need // 2) * f
                return (start + (j - start + 1) // 2) * f
        if len(pending) >= cls.MAX_SEG:
            # quietest 120 ms between MIN_SEG and MAX_SEG, cut in its middle
            lo, hi, w = first, cls.MAX_SEG // f, 6
            sm = np.convolve(rms[lo:hi], np.ones(w) / w, mode="valid")
            return int(lo + np.argmin(sm) + w // 2) * f
        return None

    @classmethod
    def has_speech(cls, piece, levels):
        """At least 0.25 s clearly louder than the take's background. A piece of
        silence or breath sent to Whisper comes back as made-up text ("I don't
        know.", "Subtitles by…"), so such pieces are skipped."""
        f = cls.FRAME
        n = len(piece) // f
        if n == 0:
            return False
        floor, speech = levels
        if speech < 1.8 * floor:       # the whole take so far is just background
            return False
        rms = np.sqrt(np.mean(piece[: n * f].reshape(n, f) ** 2, axis=1))
        # 0.01 ≈ -40 dB: a near-silent mic (Bluetooth between words) has no speech at all
        return np.sum(rms > max(floor + 0.5 * (speech - floor), 0.01)) >= int(0.25 * 50)

    def levels(self):
        f = self.FRAME
        n = len(self.audio) // f
        rms = np.sqrt(np.mean(self.audio[: n * f].reshape(n, f) ** 2, axis=1))
        return np.percentile(rms, 10), np.percentile(rms, 90)

    def _watch(self):
        while not self.stopped:
            time.sleep(0.25)
            self._grow()
            c = self.find_cut(self.audio[self.cut:])
            if c:
                with self.cv:
                    if self.stopped:
                        return
                    self.jobs.append((self.audio[self.cut: self.cut + c], self.levels()))
                    self.cut += c
                    self.cv.notify_all()

    def _work(self):
        while True:
            with self.cv:
                while not self.jobs and not self.stopped:
                    self.cv.wait()
                if not self.jobs:
                    return
                seg, lv = self.jobs[0]
            try:
                t = self.engine.transcribe(seg, " ".join(self.texts)) if self.has_speech(seg, lv) else ""
            except Exception as err:  # noqa: BLE001
                t, self.err = "", err
            with self.cv:
                if t:
                    self.texts.append(t)
                self.jobs.pop(0)
                self.cv.notify_all()

    @staticmethod
    def join(texts):
        """Glue pieces back together: no space before a stop the next piece
        starts with, a word split across a cut ("mid-" + "semester") rejoined,
        and an everyday word capitalised only because it opened a piece
        ("…the following The…") lowered again when no sentence ended."""
        out = ""
        for t in texts:
            t = t.strip()
            if not t:
                continue
            if not out:
                out = t
            elif t[0] in ".,;:!?":
                out = out.rstrip(" .,;:") + t
            elif out.endswith("-"):
                out += t
            else:
                w = re.match(r"[A-Z][a-z']*\b", t)
                if w and out[-1] not in ".!?" and w.group(0).lower() in COMMON_WORDS and w.group(0) not in ("I", "I'm", "I'll", "I've", "I'd"):
                    t = t[0].lower() + t[1:]
                out += " " + t
        return out

    def finish(self, audio):
        """Recording ended with the whole take `audio`: wait for the pieces, add the rest."""
        with self.cv:
            self.stopped = True
            self.cv.notify_all()
            while self.jobs:
                self.cv.wait()
        if getattr(self, "err", None):
            raise self.err
        rest = audio[self.cut:]
        if self.cut:   # earlier pieces exist: skip a tail that is only silence
            self.audio = audio
            if not self.has_speech(rest, self.levels()):
                rest = rest[:0]
        if len(rest) >= MIN_SAMPLES:
            t = self.engine.transcribe(rest, " ".join(self.texts))
            if t:
                self.texts.append(t)
        return self.join(self.texts)

    def cancel(self):
        with self.cv:
            self.stopped = True
            self.jobs.clear()
            self.cv.notify_all()


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
    Loaded at service start, shut down after IDLE seconds unused (gives back
    ~2.8 GB of RAM), and started again the moment Right Alt goes down: it
    reloads in ~2.8 s while you speak, so only a very short first take after
    a break waits a little.
    """
    name = "whisper"
    IDLE = 600  # unloaded after 10 min unused (~2.8 GB back); reloads when Right Alt goes down

    def __init__(self, sock=None):
        for f in (WHISPER_SERVER, WHISPER_MODEL):
            if not os.path.exists(f):
                raise RuntimeError("it isn't installed, run setup.sh")
        self.proc = None
        self.lock = threading.Lock()
        self.busy = False          # a take is being recorded
        self.keep = False          # tray: "Keep model loaded" pauses the idle unload
        self.loading = False
        self.on_change = None      # tray refresh hook
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
        cmd, env = [WHISPER_SERVER], None
        if os.path.exists(WHISPER_SERVER_OV) and os.path.exists(WHISPER_MODEL[:-4] + "-encoder-openvino.xml"):
            cmd = [WHISPER_SERVER_OV, "--ov-e-device", "GPU"]
            # WHISPER_SKIP_ENCODER: our patched whisper.cpp doesn't load its own copy
            # of the encoder, which OpenVINO replaces (~0.5 GB less RAM).
            env = dict(os.environ, LD_LIBRARY_PATH=WHISPER_OV_LIBS, WHISPER_SKIP_ENCODER="1")
        self.proc = subprocess.Popen(
            cmd + ["-m", WHISPER_MODEL, "--host", self.sock, "-l", "en", "-nt", "-t", "4"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=_die_with_parent, env=env)
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
        # A short warm-up is enough again: the crash that needed a full 30 s first
        # request came from the unused encoder copy, which is no longer loaded.
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

    def _changed(self):
        if self.on_change:
            try:
                self.on_change()
            except Exception:  # noqa: BLE001
                pass

    def _keeper(self):
        while True:
            if self.want.wait(timeout=30):
                self.want.clear()
                self.loading = not self._running()
                self._changed()
                with self.lock:
                    try:
                        self._ensure()
                        self.err = None
                    except Exception as err:  # noqa: BLE001
                        self.err = err
                self.loading = False
                self._changed()
                self.tried.set()
            elif self.proc and not self.busy and not self.keep and time.time() - self.last > self.IDLE:
                with self.lock:
                    if not self.busy and not self.keep and time.time() - self.last > self.IDLE:
                        self._kill()
                self._changed()

    def load(self):
        """Tray: load now, in the keeper thread (the server dies with the thread that started it)."""
        if not self._running():
            self.want.set()

    def unload(self):
        """Tray: give the RAM back now. Skipped mid-take; your next Right Alt reloads it."""
        if self.external or self.busy:
            return False
        with self.lock:
            if self.busy:
                return False
            self._kill()
        self._changed()
        return True

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
    def prompt(words, context=""):
        """
        Punctuated so Whisper punctuates, plus your Vocabulary so it spells them
        right. The quote line makes it expect the word "quote", which it
        otherwise hears as "coat" or "court" in Indian English; the bracket
        line keeps the spoken word "bracket". `context` is
        what was already said earlier in this take (see Streamer); it goes
        last so Whisper reads the new audio as its continuation.
        """
        # The bracket line does for "bracket" what the quote line does for "quote":
        # without it Whisper leaves the spoken word out (tested 2026-11-27; this
        # example was the one it didn't copy into your text).
        base = ("Hello, how are you? I'm doing well. He said, quote, I'll be there. "
                "Read chapter two, bracket, page 40.")
        p = base + (" Names: " + ", ".join(words) + "." if words else "")
        return p + (" " + context[-400:] if context else "")

    def stop(self):
        if not self.external:
            self._kill()

    def transcribe(self, audio, context=""):
        self._load()
        with self.lock:
            try:
                return self._request(audio, context)
            finally:
                self.last = time.time()

    def _request(self, audio, context=""):
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
        words = [e["word"] for e in load_vocab()]
        fields = {
            "language": "en",
            "prompt": self.prompt(words, context),
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


# ── tray icon ──

FLAGS = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "lumen", "flags.json")
ICONS = os.path.join(HERE, "icons")


def dictation_off():
    """Tray: same as switching dictation off in Settings. The pill watches this
    file, stops this service, and the tray icon goes with it."""
    with open(FLAGS) as f:
        flags = json.load(f)
    flags["dictateEnabled"] = False
    with open(FLAGS, "w") as f:   # in place, so the pill's file watch keeps working
        json.dump(flags, f, indent=4)


def start_tray(engine):
    """A standard tray icon (StatusNotifierItem) shown while dictation is on:
    which engine and whether it's loaded, load/unload, keep loaded, dictation off. It lives on this
    process's D-Bus connection, so it disappears when the service stops.
    Optional: if D-Bus isn't there, dictation works without it."""
    try:
        import asyncio
        from dbus_fast import Message, Variant
        from dbus_fast.aio import MessageBus
        from dbus_fast.service import PropertyAccess, ServiceInterface, dbus_property, method, signal as dbus_signal
    except ImportError:
        return

    whisper = isinstance(engine, Whisper)

    def pixmap(name):
        """The icon as image data (32 and 64 px). Sent instead of an icon name:
        your tray couldn't resolve a name from our own icon folder and showed
        Qt's purple-and-black placeholder."""
        out = []
        for n in (32, 64):
            try:   # rsvg draws the slash's cut-out (an SVG mask) correctly
                png = subprocess.run(["rsvg-convert", "-w", str(n), "-h", str(n),
                                      os.path.join(ICONS, "hicolor", "scalable", "status", name + ".svg")],
                                     capture_output=True, timeout=5).stdout
                raw = subprocess.run(["magick", "png:-", "-depth", "8", "rgba:-"], input=png,
                                     capture_output=True, timeout=5).stdout
            except (OSError, subprocess.TimeoutExpired):
                continue
            if len(raw) == n * n * 4:
                a = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 4)
                out.append([n, n, a[:, [3, 0, 1, 2]].tobytes()])   # ARGB, network byte order
        return out

    pix = {n: pixmap(n) for n in ("lumen-dictation-loaded", "lumen-dictation-unloaded")}

    def state():
        """(icon state, status line): names the engine actually running, so a
        switch to Parakeet (or a fallback to it) reads "Parakeet"."""
        if not whisper:
            return "loaded", "Parakeet"
        if engine._running():
            return "loaded", "Whisper loaded"
        if engine.loading:
            return "loading", "Whisper loading…"
        return "unloaded", "Whisper unloaded"

    def icon_name():
        return "lumen-dictation-unloaded" if state()[0] != "loaded" else "lumen-dictation-loaded"

    class Item(ServiceInterface):
        def __init__(self):
            super().__init__("org.kde.StatusNotifierItem")

        @dbus_property(access=PropertyAccess.READ)
        def Category(self) -> "s":
            return "Hardware"

        @dbus_property(access=PropertyAccess.READ)
        def Id(self) -> "s":
            return "lumen-dictation"

        @dbus_property(access=PropertyAccess.READ)
        def Title(self) -> "s":
            return "Dictation"

        @dbus_property(access=PropertyAccess.READ)
        def Status(self) -> "s":
            return "Active"

        @dbus_property(access=PropertyAccess.READ)
        def WindowId(self) -> "i":
            return 0

        @dbus_property(access=PropertyAccess.READ)
        def IconThemePath(self) -> "s":
            return ICONS

        @dbus_property(access=PropertyAccess.READ)
        def IconName(self) -> "s":
            return ""   # image data only, see pixmap()

        @dbus_property(access=PropertyAccess.READ)
        def IconPixmap(self) -> "a(iiay)":
            return pix[icon_name()]

        @dbus_property(access=PropertyAccess.READ)
        def OverlayIconName(self) -> "s":
            return ""

        @dbus_property(access=PropertyAccess.READ)
        def AttentionIconName(self) -> "s":
            return ""

        @dbus_property(access=PropertyAccess.READ)
        def ToolTip(self) -> "(sa(iiay)ss)":
            return ["", [], "Dictation", state()[1]]

        @dbus_property(access=PropertyAccess.READ)
        def ItemIsMenu(self) -> "b":
            return True

        @dbus_property(access=PropertyAccess.READ)
        def Menu(self) -> "o":
            return "/MenuBar"

        @method()
        def ContextMenu(self, x: "i", y: "i"):
            pass

        @method()
        def Activate(self, x: "i", y: "i"):
            pass

        @method()
        def SecondaryActivate(self, x: "i", y: "i"):
            pass

        @method()
        def Scroll(self, delta: "i", orientation: "s"):
            pass

        @dbus_signal()
        def NewIcon(self):
            pass

        @dbus_signal()
        def NewToolTip(self):
            pass

        @dbus_signal()
        def NewStatus(self) -> "s":
            return "Active"

    STATUS, SEP1, LOADER, KEEP, SEP2, OFF = 1, 2, 3, 4, 5, 6

    def entries():
        st, text = state()
        out = [(STATUS, {"label": Variant("s", text), "enabled": Variant("b", False)}),
               (SEP1, {"type": Variant("s", "separator")})]
        if whisper:
            if st == "loaded":
                out.append((LOADER, {"label": Variant("s", "Unload model now"), "enabled": Variant("b", not engine.busy)}))
            else:
                out.append((LOADER, {"label": Variant("s", "Load model now"), "enabled": Variant("b", st == "unloaded")}))
            out.append((KEEP, {"label": Variant("s", "Keep model loaded"), "toggle-type": Variant("s", "checkmark"),
                               "toggle-state": Variant("i", 1 if engine.keep else 0)}))
            out.append((SEP2, {"type": Variant("s", "separator")}))
        out.append((OFF, {"label": Variant("s", "Turn dictation off")}))
        return out

    class Menu(ServiceInterface):
        def __init__(self):
            super().__init__("com.canonical.dbusmenu")
            self.revision = 1

        @dbus_property(access=PropertyAccess.READ)
        def Version(self) -> "u":
            return 3

        @dbus_property(access=PropertyAccess.READ)
        def TextDirection(self) -> "s":
            return "ltr"

        @dbus_property(access=PropertyAccess.READ)
        def Status(self) -> "s":
            return "normal"

        @dbus_property(access=PropertyAccess.READ)
        def IconThemePath(self) -> "as":
            return [ICONS]

        @method()
        def GetLayout(self, parent: "i", depth: "i", names: "as") -> "u(ia{sv}av)":
            kids = [Variant("(ia{sv}av)", [i, props, []]) for i, props in entries()]
            if parent != 0:
                kids = []
            return [self.revision, [parent, {"children-display": Variant("s", "submenu")} if parent == 0 else {}, kids]]

        @method()
        def GetGroupProperties(self, ids: "ai", names: "as") -> "a(ia{sv})":
            e = dict(entries())
            return [[i, e[i]] for i in (ids or list(e)) if i in e]

        @method()
        def GetProperty(self, id_: "i", name: "s") -> "v":
            return dict(entries()).get(id_, {}).get(name, Variant("s", ""))

        @method()
        def Event(self, id_: "i", event: "s", data: "v", timestamp: "u"):
            if event == "clicked":
                threading.Thread(target=clicked, args=(id_,), daemon=True).start()

        @method()
        def EventGroup(self, events: "a(isvu)") -> "ai":
            for id_, event, _data, _ts in events:
                if event == "clicked":
                    threading.Thread(target=clicked, args=(id_,), daemon=True).start()
            return []

        @method()
        def AboutToShow(self, id_: "i") -> "b":
            return True   # status is read fresh on every open

        @method()
        def AboutToShowGroup(self, ids: "ai") -> "aiai":
            return [ids, []]

        @dbus_signal()
        def LayoutUpdated(self) -> "ui":
            self.revision += 1
            return [self.revision, 0]

    item, menu = Item(), Menu()
    loop_box = {}

    def clicked(id_):
        if id_ == LOADER and whisper:
            if engine._running():
                engine.unload()
            else:
                engine.load()
        elif id_ == KEEP and whisper:
            engine.keep = not engine.keep
            engine.last = time.time()
        elif id_ == OFF:
            try:
                dictation_off()
            except (OSError, ValueError) as err:
                emit(event="error", msg="couldn't turn dictation off: %s" % err)
        refresh()

    def refresh():
        loop = loop_box.get("loop")
        if loop:
            loop.call_soon_threadsafe(lambda: (item.NewIcon(), item.NewToolTip(), menu.LayoutUpdated()))

    async def run():
        bus = await MessageBus().connect()
        name = "org.kde.StatusNotifierItem-%d-1" % os.getpid()
        bus.export("/StatusNotifierItem", item)
        bus.export("/MenuBar", menu)
        await bus.request_name(name)
        await bus.call(Message(destination="org.kde.StatusNotifierWatcher", path="/StatusNotifierWatcher",
                               interface="org.kde.StatusNotifierWatcher", member="RegisterStatusNotifierItem",
                               signature="s", body=[name]))
        last = None
        while True:   # a server that stopped on its own shows up within a few seconds
            await asyncio.sleep(5)
            now = state()
            if now != last:
                last = now
                item.NewIcon()
                item.NewToolTip()
                menu.LayoutUpdated()

    def thread():
        loop = asyncio.new_event_loop()
        loop_box["loop"] = loop
        try:
            loop.run_until_complete(run())
        except Exception as err:  # noqa: BLE001
            sys.stderr.write("tray icon unavailable: %s\n" % err)

    if whisper:
        engine.on_change = refresh
    threading.Thread(target=thread, daemon=True).start()


# ── main ──

def main():
    try:
        engine = pick_engine()
    except Exception as err:  # noqa: BLE001
        emit(event="error", msg="model failed to load: %s" % err)
        return 1
    emit(event="ready")
    start_tray(engine)

    take = stream = None
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
            if stream:
                stream.cancel()
                stream = None
            try:
                take = Take(resolve_mic(msg.get("mic", "default")))
                if engine.name == "whisper":
                    stream = Streamer(engine, take)
            except OSError as err:
                take = None
                emit(event="error", msg="mic unavailable: %s" % err)
        elif cmd == "reload":
            load_vocab(force=True)
        elif cmd == "cancel":
            if stream:
                stream.cancel()
                stream = None
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
            st, stream = stream, None
            if hasattr(engine, "done"):
                engine.done()
            if len(audio) < MIN_SAMPLES:
                if st:
                    st.cancel()
                emit(event="empty")
                continue
            try:
                raw = st.finish(audio) if st else engine.transcribe(audio)
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
