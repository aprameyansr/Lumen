#!/bin/sh
#
# Lumen dictation setup: everything the hold-to-talk service needs, in one
# folder, without root. Safe to run again: finished steps are skipped, and your
# vocabulary (vocab.json) and history (history.json) are never touched.
#
#   sh ~/.local/share/lumen-dictate/setup.sh
#
# What it does:
#   1. venv/        Python environment with sherpa-onnx + numpy (~125 MB)
#   2. models/      NVIDIA Parakeet TDT 0.6B v2, English, int8 (~630 MB)
#   3. common-words.txt   top ~10k English words, used to flag vocabulary
#                         forms that would rewrite normal speech
#
# Needs: python, curl, tar with bzip2, plus pipewire-audio (pw-record), wtype,
# wl-clipboard, libpulse (pactl), cava and zenity for the shell side.
# To remove it all: rm -rf ~/.local/share/lumen-dictate

set -eu

DIR="${LUMEN_DICTATE_DIR:-$(cd "$(dirname "$0")" && pwd)}"
MODEL="sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$MODEL.tar.bz2"
WORDS_URL="https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-no-swears.txt"

say() { printf '  · %s\n' "$*"; }
die() { printf '  ! %s\n' "$*" >&2; exit 1; }

for c in python3 curl tar; do
    command -v "$c" >/dev/null 2>&1 || die "$c not found"
done

mkdir -p "$DIR/models"

if [ -x "$DIR/venv/bin/python" ] && "$DIR/venv/bin/python" -c "import sherpa_onnx, numpy" 2>/dev/null; then
    say "Python environment already set up"
else
    say "Creating the Python environment"
    python3 -m venv "$DIR/venv"
    "$DIR/venv/bin/pip" install --quiet --no-cache-dir --disable-pip-version-check sherpa-onnx numpy
fi

if [ -f "$DIR/models/$MODEL/encoder.int8.onnx" ]; then
    say "Speech model already downloaded"
else
    say "Downloading the speech model (~630 MB)"
    tmp="$DIR/models/.download.tar.bz2"
    curl -fL --progress-bar -o "$tmp" "$MODEL_URL"
    tar xjf "$tmp" -C "$DIR/models"
    rm -f "$tmp"
fi

if [ -s "$DIR/common-words.txt" ]; then
    say "Word list already downloaded"
else
    say "Downloading the common-words list"
    curl -fsSL -o "$DIR/common-words.txt" "$WORDS_URL"
fi

[ -f "$DIR/dictated.py" ] || die "dictated.py is missing from $DIR (copy it from the dotfiles)"

say "Done. Turn it on in Settings → Dictation, then hold Right Alt and talk."
