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
#   2. models/      Parakeet TDT 0.6B v2, English, int8 (~630 MB): the fast engine
#   3. whisper/     whisper.cpp server built for your GPU (Vulkan) and
#      models/      Whisper large-v3-turbo, q8_0 (~875 MB): the accurate engine
#   4. common-words.txt   top ~10k English words, used to flag vocabulary
#                         forms that would rewrite normal speech
#
# Needs: python, curl, tar with bzip2, plus pipewire-audio (pw-record), wtype,
# wl-clipboard, libpulse (pactl), cava and zenity for the shell side. Whisper
# also needs git, a C++ compiler, shaderc (glslc), vulkan-icd-loader and your
# GPU's Vulkan driver (vulkan-intel, vulkan-radeon or nvidia-utils). Without
# them step 3 is skipped and dictation uses Parakeet.
# To remove it all: rm -rf ~/.local/share/lumen-dictate

set -eu

DIR="${LUMEN_DICTATE_DIR:-$(cd "$(dirname "$0")" && pwd)}"
MODEL="sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$MODEL.tar.bz2"
# A tested whisper.cpp commit (after v1.9.5; adds the unix-socket server the
# service talks to, so Whisper never opens a network port).
WHISPER_REF="5eaee0cc9024eb9e9a99469199920c8b7f5cb9ec"
WHISPER_MODEL="ggml-large-v3-turbo-q8_0.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL"
WORDS_URL="https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-no-swears.txt"

say() { printf '  · %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf '  ! %s\n' "$*" >&2; exit 1; }

for c in python3 curl tar; do
    command -v "$c" >/dev/null 2>&1 || die "$c not found"
done

mkdir -p "$DIR/models"

# ── 1. Python environment ──
if [ -x "$DIR/venv/bin/python" ] && "$DIR/venv/bin/python" -c "import sherpa_onnx, numpy" 2>/dev/null; then
    say "Python environment already set up"
else
    say "Creating the Python environment"
    python3 -m venv "$DIR/venv"
    "$DIR/venv/bin/pip" install --quiet --no-cache-dir --disable-pip-version-check sherpa-onnx numpy
fi

# ── 2. Parakeet ──
if [ -f "$DIR/models/$MODEL/encoder.int8.onnx" ]; then
    say "Parakeet model already downloaded"
else
    say "Downloading the Parakeet model (~630 MB)"
    tmp="$DIR/models/.download.tar.bz2"
    curl -fL --progress-bar -o "$tmp" "$MODEL_URL"
    tar xjf "$tmp" -C "$DIR/models"
    rm -f "$tmp"
fi

# ── 3. Whisper (GPU) ──
whisper_deps() {
    for c in git cc c++ glslc; do
        command -v "$c" >/dev/null 2>&1 || { warn "Whisper skipped: $c not found"; return 1; }
    done
    [ -e /usr/lib/libvulkan.so ] || [ -e /usr/lib/libvulkan.so.1 ] || { warn "Whisper skipped: vulkan-icd-loader not installed"; return 1; }
    ls /usr/share/vulkan/icd.d/*.json >/dev/null 2>&1 || { warn "Whisper skipped: no Vulkan GPU driver installed"; return 1; }
}

if [ -x "$DIR/whisper/whisper-server" ]; then
    say "Whisper server already built"
elif whisper_deps; then
    say "Building the Whisper server for your GPU (a few minutes)"
    B="$DIR/.build"
    rm -rf "$B"
    mkdir -p "$B"
    python3 -m venv "$B/tools"
    "$B/tools/bin/pip" install --quiet --no-cache-dir --disable-pip-version-check cmake ninja
    git init -q "$B/whisper.cpp"
    git -C "$B/whisper.cpp" fetch -q --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_REF"
    git -C "$B/whisper.cpp" -c advice.detachedHead=false checkout -q FETCH_HEAD
    vk=$(sed -n 's/^Version: *//p' /usr/lib/pkgconfig/vulkan.pc 2>/dev/null || true)
    git clone -q --depth 1 ${vk:+-b v$vk} https://github.com/KhronosGroup/Vulkan-Headers.git "$B/Vulkan-Headers" 2>/dev/null ||
        git clone -q --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git "$B/Vulkan-Headers"
    git clone -q --depth 1 https://github.com/KhronosGroup/SPIRV-Headers.git "$B/SPIRV-Headers"
    PATH="$B/tools/bin:$PATH"
    cmake -S "$B/SPIRV-Headers" -B "$B/SPIRV-Headers/build" -G Ninja -Wno-deprecated -DCMAKE_INSTALL_PREFIX="$B/prefix" \
        -DSPIRV_HEADERS_ENABLE_TESTS=OFF >/dev/null
    cmake --install "$B/SPIRV-Headers/build" >/dev/null
    libvk=/usr/lib/libvulkan.so
    [ -e "$libvk" ] || libvk=/usr/lib/libvulkan.so.1
    cmake -S "$B/whisper.cpp" -B "$B/whisper.cpp/build" -G Ninja -Wno-deprecated -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DGGML_VULKAN=ON -DGGML_CCACHE=OFF -DWHISPER_BUILD_TESTS=OFF \
        -DCMAKE_PREFIX_PATH="$B/prefix" -DCMAKE_CXX_FLAGS="-I$B/prefix/include" \
        -DVulkan_INCLUDE_DIR="$B/Vulkan-Headers/include" -DVulkan_LIBRARY="$libvk" \
        -DVulkan_GLSLC_EXECUTABLE="$(command -v glslc)" >/dev/null
    if cmake --build "$B/whisper.cpp/build" --target whisper-server -j "$(nproc)" >"$B/build.log" 2>&1; then
        mkdir -p "$DIR/whisper"
        install -m755 "$B/whisper.cpp/build/bin/whisper-server" "$DIR/whisper/whisper-server"
        rm -rf "$B"
    else
        warn "Whisper build failed, see $B/build.log (dictation will use Parakeet)"
    fi
fi

if [ -x "$DIR/whisper/whisper-server" ]; then
    if [ -s "$DIR/models/$WHISPER_MODEL" ]; then
        say "Whisper model already downloaded"
    else
        say "Downloading the Whisper model (~875 MB)"
        curl -fL --progress-bar -o "$DIR/models/.$WHISPER_MODEL" "$WHISPER_MODEL_URL"
        mv "$DIR/models/.$WHISPER_MODEL" "$DIR/models/$WHISPER_MODEL"
    fi
fi

# ── 4. Word list ──
if [ -s "$DIR/common-words.txt" ]; then
    say "Word list already downloaded"
else
    say "Downloading the common-words list"
    curl -fsSL -o "$DIR/common-words.txt" "$WORDS_URL"
fi

[ -f "$DIR/dictated.py" ] || die "dictated.py is missing from $DIR (copy it from the dotfiles)"

say "Done. Turn it on in Settings → Dictation, then hold Right Alt and talk."
