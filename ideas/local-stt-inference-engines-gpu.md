# Local STT inference engines — GPU acceleration on NVIDIA vs AMD

**Question:** [`questions/local-stt-inference-engines-gpu.md`](../questions/local-stt-inference-engines-gpu.md)
**Written:** 14/04/26
**Stack:** Desktop live dictation on Linux (Ubuntu 25.10 / KDE). Focus: local inference, GPU-accelerated where possible. Hardware assumption — either an NVIDIA GPU (CUDA) or an AMD GPU (RDNA2/3/4 via ROCm, HIP, or Vulkan).

## TL;DR

Picking a **model** ([`live-typing-models-saas-and-local`](live-typing-models-saas-and-local.md)) is only half the decision — you also pick an **inference engine**, and that's what determines whether your GPU actually gets used.

- **NVIDIA side is boring and easy**: almost every engine has a first-class CUDA path. cuBLAS/cuDNN for general work, TensorRT for squeezed-out latency, ORT's CUDA/TensorRT execution providers for ONNX models.
- **AMD side is where the architecture decisions bite**. Three distinct paths exist — **ROCm/HIP** (closest to CUDA parity, but fragile), **Vulkan compute** (cross-vendor, shipped by whisper.cpp), and **CPU fallback** (sometimes faster than fighting ROCm). Engine by engine, exactly one of those three is usually viable.
- **Short version for AMD users**: `whisper.cpp` with the Vulkan backend is the least painful GPU path for Whisper-family. For Parakeet/Moonshine/Canary you're usually on **ONNX Runtime CPU** unless you rebuild ORT against ROCm.

## Background

A local STT stack has three layers:

1. **Model** — the weights (Whisper, Parakeet, Moonshine, …) and their architecture.
2. **Runtime / inference engine** — what actually executes the graph (whisper.cpp, ONNX Runtime, PyTorch, CTranslate2, NeMo, sherpa-onnx…).
3. **Backend / execution provider** — how the runtime reaches the hardware (CUDA, HIP, Vulkan, CPU SIMD).

Model and runtime are usually coupled (Parakeet runs in NeMo or ONNX; Moonshine ships ONNX + Keras + MLX; Whisper runs basically everywhere). Runtime and backend are more loosely coupled — but not as loosely as vendor marketing suggests, especially on AMD.

## The engines — what they are and what they accelerate on

### whisper.cpp / whisper-rs

- **Runtime**: C/C++ on GGML; GGUF model format.
- **NVIDIA**: `GGML_CUDA=1` (cuBLAS, optional cuDNN).
- **AMD**: two options — `GGML_HIP=1` (requires ROCm toolchain) **or** `GGML_VULKAN=1` (cross-vendor, works without ROCm).
- **CPU**: heavily tuned — AVX/AVX2/AVX512, ARM NEON.
- **Models**: Whisper family only (and Distil-Whisper ports).
- **Streaming**: the `stream` example does sliding-window + VAD — it's *pseudo-streaming*, not true streaming ASR.
- **Why it matters**: **the Vulkan backend is the least-painful GPU path on AMD Linux**. Upstream ships Vulkan binaries; no ROCm install required.

### faster-whisper (CTranslate2)

- **NVIDIA**: CUDA + cuDNN; uses cuBLAS.
- **AMD**: **no official ROCm/HIP path**. CTranslate2's GPU path is CUDA-only — on AMD you're on CPU.
- **CPU**: excellent — int8 / int8_float16 quantisation, typically faster than reference Whisper on equivalent hardware.
- **Models**: Whisper family + Distil-Whisper.
- **Streaming**: batch-oriented; word timestamps and batched inference from v1.0.
- **Verdict**: best Whisper runtime on NVIDIA. On AMD, use CPU or switch to whisper.cpp.

### WhisperX

- Thin layer over faster-whisper + wav2vec2 alignment + pyannote diarization.
- Inherits faster-whisper's CUDA-only GPU situation. pyannote is PyTorch, so ROCm-PyTorch *should* work for that stage — **unverified**.
- Batch-only; aimed at timestamped transcripts, not live typing.

### openai-whisper (reference PyTorch)

- **NVIDIA**: CUDA via PyTorch wheels.
- **AMD**: ROCm via PyTorch ROCm wheels — works on RDNA2/3; RDNA4 is landing in PyTorch 2.5+/ROCm 6.2+ (**verify per release**).
- Reference implementation — slow compared to whisper.cpp or faster-whisper.

### ONNX Runtime (ORT)

This is the quiet workhorse — it's what Handy uses under the hood for Parakeet/Moonshine/Canary/etc via `transcribe-rs`.

- **NVIDIA EPs**: `CUDAExecutionProvider`, `TensorrtExecutionProvider`, cuDNN-backed.
- **AMD EPs**: `ROCmExecutionProvider` (HIP), `MIGraphXExecutionProvider`. Windows-only: `DmlExecutionProvider` (DirectML).
- **No upstream Vulkan EP** — community forks exist but aren't production-grade.
- **Gotcha**: ROCm EP requires **building ORT from source against a matching ROCm version** — pip wheels don't include it. This is the single biggest friction point for local Parakeet/Moonshine on AMD.

### NVIDIA NeMo

- PyTorch + NeMo toolkit; exportable to ONNX / TensorRT.
- **NVIDIA-only** in the official stack (CUDA/cuDNN/TensorRT).
- On AMD: export to ONNX and run via sherpa-onnx or an ORT-ROCm build — NeMo itself won't run on AMD officially.
- Models: Parakeet (CTC/RNN-T/TDT), Canary, FastConformer, Citrinet.
- RNN-T / TDT variants support **true streaming**.

### sherpa-onnx (k2-fsa)

- Built on ONNX Runtime + custom C++ decoding (FST/LG graphs).
- **NVIDIA**: CUDA EP.
- **AMD**: inherits ORT — ROCm EP if you've rebuilt ORT; otherwise CPU.
- Models: Whisper, Moonshine, Parakeet (exported), SenseVoice, Zipformer, Paraformer.
- **Strongest true-streaming support of the OSS engines** — streaming Zipformer and streaming Paraformer are designed for it.

### vLLM / TensorRT-LLM

- vLLM has experimental Whisper/audio support; TensorRT-LLM has Whisper examples.
- NVIDIA-only in practice. vLLM has a ROCm path for LLMs, but **Whisper on ROCm is unverified**.
- No broadly adopted local equivalent of `gpt-4o-transcribe` — that model isn't released. Open analogues are Parakeet-TDT and Canary, not vLLM-deployed.

### Moonshine's own runtimes

- Useful Sensors ship **ONNX**, **Keras/TF**, **MLX** (Apple Silicon), and a PyTorch reference.
- No dedicated CUDA runtime — acceleration is whatever the chosen backend does (ONNX → ORT EPs; Keras → TF GPU).
- Tiny enough (27M–~200M params) that CPU is often fine for live typing.

### transcribe-rs (cjpais — used by Handy)

- Rust wrapper over ONNX Runtime plus whisper.cpp for Whisper models.
- EPs: CPU by default; CUDA available via `ort` crate features; **ROCm EP is not wired up in the default Handy build** — verify per release.
- **Practical upshot for Handy on AMD**: Whisper models can use Vulkan (via whisper.cpp); Parakeet/Moonshine/Canary/etc run on CPU unless you rebuild.

## The arch split — engine × vendor × backend

| Engine | Runtime / format | NVIDIA path | AMD path | CPU path | Models |
|---|---|---|---|---|---|
| **whisper.cpp / whisper-rs** | GGML | CUDA (cuBLAS, cuDNN) | **HIP (ROCm)** or **Vulkan** ✅ | AVX/AVX2/AVX512, NEON | Whisper (+ Distil) |
| **faster-whisper** | CTranslate2 | CUDA + cuDNN | **CPU only** (no ROCm) | int8 / int8_f16 — very fast | Whisper (+ Distil) |
| **WhisperX** | faster-whisper + pyannote | CUDA | CPU (pyannote-on-ROCm unverified) | via faster-whisper | Whisper + alignment/diarization |
| **openai-whisper** | PyTorch | CUDA | ROCm PyTorch (RDNA2/3 OK; RDNA4 2.5+) | Yes, slow | Whisper |
| **ONNX Runtime** | ONNX | CUDA EP, TensorRT EP | ROCm EP, MIGraphX EP — **rebuild required** | Default CPU EP, OpenVINO EP | Any ONNX-exported model |
| **NVIDIA NeMo** | PyTorch + NeMo | CUDA / cuDNN / TensorRT | **Not officially supported** | Yes | Parakeet, Canary, FastConformer, Citrinet |
| **sherpa-onnx** | ONNX Runtime + C++ decoder | CUDA EP | ROCm EP (rebuild) | Default CPU | Whisper, Moonshine, Parakeet, SenseVoice, Zipformer, Paraformer |
| **vLLM / TensorRT-LLM** | Custom | CUDA / TensorRT | Unverified for Whisper on ROCm | No | Whisper (experimental) |
| **Moonshine runtimes** | ONNX / Keras / MLX / PyTorch | via chosen backend (CUDA) | via chosen backend (ROCm-ORT if built) | Yes, often sufficient | Moonshine only |
| **transcribe-rs (Handy)** | ONNX + whisper.cpp | CUDA (ort feature) | Whisper → Vulkan/HIP via whisper.cpp; others → CPU | Yes — default | Whisper, Parakeet, Moonshine, Canary, SenseVoice, GigaAM, Cohere |

## Commonalities and points of difference

**Common ground:**
- Every engine has a working **CPU** path. For small streaming models (Moonshine-tiny/small, Parakeet-TDT-0.6B int8), CPU is often enough for live typing — the GPU question matters more for Whisper-large/turbo batch finals.
- Every engine with NVIDIA support uses some combination of **CUDA + cuBLAS + cuDNN**; the optional TensorRT layer is where you squeeze latency but also where breakage lives.
- **ONNX is the lingua franca for non-Whisper local STT.** If the model isn't Whisper, odds are you're going through ORT — directly (NeMo export, Moonshine), or via a wrapper (sherpa-onnx, transcribe-rs).

**Where they diverge:**
- **GGML world** (whisper.cpp + friends) has a Vulkan backend. The ONNX world does not. That's the single biggest practical AMD-vs-NVIDIA asymmetry.
- **Streaming-native engines** are sherpa-onnx, NeMo (for RNN-T/TDT models), and Moonshine's own runtimes. Everything else fakes streaming via chunking.
- **Bundled-vs-BYO model** — whisper.cpp and faster-whisper ship with one model family. ORT/sherpa-onnx/transcribe-rs run anything you can export.

## ROCm reality check on consumer AMD

- **RDNA3** (7900 XTX/XT, 7800/7700/7600) — supported since ROCm 5.7, but consumer SKUs often need `HSA_OVERRIDE_GFX_VERSION` set for PyTorch to recognise the device.
- **RDNA4** (RX 9070 series) — ROCm 6.3+/6.4+ required; **verify against the current ROCm release notes**. PyTorch ROCm wheels lag ROCm itself by 1–2 minor versions.
- **RDNA2** and older — legacy path; patchy support.

If you're on AMD and want GPU-accelerated Whisper today without fighting ROCm, the pragmatic answer is: **whisper.cpp with `GGML_VULKAN=1`**. Everything else is either CPU (which is often fine), or a ROCm build project.

## Recommendation

Given the live-typing goal and the two vendor cases:

| Vendor | Whisper-family (batch-on-endpoint) | Streaming partials (Parakeet/Moonshine) |
|---|---|---|
| **NVIDIA** | `faster-whisper` on CUDA (best throughput) or `whisper.cpp` CUDA (simpler) | `sherpa-onnx` with CUDA EP, or Handy (`transcribe-rs`) with CUDA feature |
| **AMD** | `whisper.cpp` with **Vulkan** | `transcribe-rs` / `sherpa-onnx` on **CPU** (usually fine for Moonshine-small and Parakeet-TDT-0.6B int8) — ROCm-ORT rebuild only if you need the headroom |

For Daniel's current setup this lines up cleanly with Handy: Whisper uses GPU via whisper.cpp, Parakeet-TDT-0.6B-v3 runs on CPU at int8 — no ROCm required.

## References

- whisper.cpp: [github.com/ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) — see `Vulkan` and `HIP` sections of the README.
- faster-whisper: [github.com/SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper); CTranslate2: [github.com/OpenNMT/CTranslate2](https://github.com/OpenNMT/CTranslate2)
- ONNX Runtime execution providers: [onnxruntime.ai/docs/execution-providers](https://onnxruntime.ai/docs/execution-providers/) — ROCm EP build instructions live under the "Build for inferencing" guide.
- NVIDIA NeMo: [github.com/NVIDIA/NeMo](https://github.com/NVIDIA/NeMo)
- sherpa-onnx: [github.com/k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- Moonshine runtimes: [github.com/usefulsensors/moonshine](https://github.com/usefulsensors/moonshine)
- Handy / transcribe-rs: [github.com/cjpais/Handy](https://github.com/cjpais/Handy), [github.com/cjpais/transcribe-rs](https://github.com/cjpais/transcribe-rs)
- Related topics:
  - [`live-typing-models-saas-and-local`](live-typing-models-saas-and-local.md) — the model-side counterpart to this doc.
  - [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — why streaming engines matter for live typing.
