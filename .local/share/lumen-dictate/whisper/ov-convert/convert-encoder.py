import os, gc, torch, openvino as ov
import torch.nn.functional as F
from whisper.model import AudioEncoder, ModelDimensions

class DynEncoder(AudioEncoder):
    """Same maths as Whisper's encoder, but any window length (whisper.cpp audio_ctx):
    positional embedding sliced to the window instead of asserting 30 s."""
    def forward(self, x):
        x = F.gelu(self.conv1(x))
        x = F.gelu(self.conv2(x))
        x = x.permute(0, 2, 1)
        x = (x + self.positional_embedding[: x.shape[1]]).to(x.dtype)
        for block in self.blocks:
            x = block(x)
        return self.ln_post(x)

def main():
    torch.set_num_threads(8)
    here = os.path.dirname(os.path.abspath(__file__))
    ck = torch.load(os.path.join(here, "pt", "large-v3.pt"), map_location="cpu", mmap=True, weights_only=True)
    d = ModelDimensions(**ck["dims"])
    with torch.device("meta"):
        enc = DynEncoder(d.n_mels, d.n_audio_ctx, d.n_audio_state, d.n_audio_head, d.n_audio_layer)
    enc.load_state_dict({k[8:]: v for k, v in ck["model_state_dict"].items() if k.startswith("encoder.")}, assign=True)
    enc.float()  # fp32 trace: fast multi-threaded on CPU; saved as fp16 below
    print("dtype", next(enc.parameters()).dtype, enc.positional_embedding.dtype, flush=True)
    del ck; gc.collect(); enc.eval()
    with torch.no_grad():
        om = ov.convert_model(enc, example_input=torch.zeros((1, d.n_mels, 3000)), input=[ov.PartialShape([1, d.n_mels, -1])])
    del enc; gc.collect()
    om.inputs[0].get_tensor().set_names({"mel"}); om.outputs[0].get_tensor().set_names({"output_features"})
    ov.save_model(om, os.path.join(here, "ggml-large-v3-encoder-openvino-dyn.xml"), compress_to_fp16=True)
    print("saved")

if __name__ == "__main__":
    main()
