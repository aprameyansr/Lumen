"""Recognize local inference workers using their launch arguments."""

from pathlib import Path

AI_ICON = "@ai"
MODEL_FILES = {".gguf", ".safetensors", ".onnx", ".tflite"}
LLAMA_CPP = {"llama-server", "llama-cli", "llama-run", "llama-mtmd-cli", "main-llama", "koboldcpp"}


def option(args, *names):
    for index, arg in enumerate(args):
        name, separator, value = arg.partition("=")
        if name in names:
            value = value if separator else args[index + 1] if index + 1 < len(args) else ""
            return value if not value.startswith("-") else ""
    return ""


def model_label(model):
    filename = Path(model.rstrip("/")).name
    lower = filename.lower()
    if lower.startswith("ggml-") and "large-v3-turbo" in lower:
        return "Whisper Turbo"
    suffix = Path(filename).suffix.lower()
    return Path(filename).stem if suffix in MODEL_FILES or suffix == ".bin" else filename


def identify_model(args):
    """Return (runtime, model identifier) for a supported inference command."""
    executable = Path(args[0]).name.lower()
    cli_model = option(args, "--model", "--model-path", "--model-id")
    if executable in {"whisper-server", "whisper-cli", "whisper.cpp"}:
        model = cli_model or option(args, "-m")
        return ("Whisper", model) if model else None

    if (executable == "ollama" and args[1:2] == ["runner"]) or executable == "ollama_llama_server":
        return "Ollama", ""

    if executable in LLAMA_CPP:
        model = cli_model or option(args, "-m", "-hf", "--hf-repo")
        # llama-run also takes the model as its first positional argument.
        if not model and executable == "llama-run" and len(args) > 1 and not args[1].startswith("-"):
            model = args[1]
        return ("llama.cpp", model) if model else None

    # Python entry points are often invoked as a script or as “python -m module”.
    launchers = args[:1]
    if executable.startswith("python"):
        if args[1:2] == ["-m"]:
            launchers = args[2:3]
        else:
            launchers = next(([arg] for arg in args[1:] if not arg.startswith("-")), [])
    launcher = Path(launchers[0]).name.lower().removesuffix(".py") if launchers else ""
    runtime = {
        "vllm": "vLLM", "vllm.entrypoints.openai.api_server": "vLLM",
        "sglang.launch_server": "SGLang", "sglang.serve": "SGLang",
        "mlx_lm.server": "MLX", "mlx_lm.generate": "MLX", "mlx_lm.chat": "MLX",
        "mlx_lm": "MLX", "mlx_lm.server_cli": "MLX", "mlx_lm.generate_cli": "MLX",
        "text-generation-launcher": "Text Generation Inference",
        "text-generation-server": "Text Generation Inference",
    }.get(launcher)
    if runtime:
        if not cli_model and runtime == "vLLM" and "serve" in args:
            index = args.index("serve") + 1
            if index < len(args) and not args[index].startswith("-"):
                cli_model = args[index]
        return (runtime, cli_model) if cli_model else None

    # A dedicated command that opens a model through an explicit option still
    # has a useful identity even when its runtime has no recognizer.
    checkpoint = cli_model or option(args, "--checkpoint")
    if checkpoint and Path(checkpoint).suffix.lower() in MODEL_FILES:
        return executable, checkpoint
    return None


def display_name(runtime, model):
    return model_label(model) or runtime
