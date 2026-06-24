# GPU Setup (Windows + NVIDIA) — this machine

Native llama.cpp **CUDA** path for a Windows laptop whose NVIDIA driver caps at CUDA 12.8.
Written for the hardware detected here; the reasoning generalises to any GTX/RTX Windows box.

## Detected hardware

| Component | Value |
|---|---|
| GPU | NVIDIA GeForce GTX 1650 — **4 GB VRAM**, Turing (compute 7.5) |
| Driver | 572.60 → max CUDA **runtime 12.8** |
| CUDA Toolkit (nvcc) | 13.1 *(installed, but newer than the driver supports)* |
| CPU | AMD Ryzen 5 5500U — 6 physical / 12 logical cores |
| RAM | 15.3 GB → model tier **Qwen2.5-1.5B-Instruct Q4_K_M** |

## Why prebuilt CUDA 12.4 binaries (not a source build / not pip wheels)

- The driver (572.60) only runs CUDA **≤ 12.8**. Anything compiled against the installed
  CUDA **13.1** toolkit would fail at runtime (`CUDA driver version is insufficient`).
- `llama-cpp-python`'s prebuilt CUDA wheels stop at **0.2.67 (mid-2024)** — too old to load
  Qwen2.5 / Llama-3.2 GGUFs.
- So the robust path is the **official llama.cpp prebuilt Windows CUDA 12.4 binaries**
  (`cudart 12.4` ≤ driver 12.8 ✓). No compiler, no Python-version juggling, current model support.

## What was installed

1. **Python env** (`conda` env `day20`, Python 3.12) with `requirements.txt`
   (the system `python` is 3.14 — too new for the lab's wheels).
   ```powershell
   conda create -n day20 python=3.12 -y
   C:\Users\Kaito\miniconda3\envs\day20\python.exe -m pip install -r requirements.txt
   ```
2. **GPU binaries** — `llama-b9771-bin-win-cuda-12.4-x64.zip` + `cudart-llama-bin-win-cuda-12.4-x64.zip`
   from `ggml-org/llama.cpp` release **b9771** (matches the lab's `make build-llama` pin),
   extracted to:
   ```
   BONUS-llama-cpp-optimization\llama.cpp\build\bin\
   ```
   Key files: `llama-server.exe`, `llama-cli.exe`, `llama-bench.exe`, `ggml-cuda.dll`,
   `cudart64_12.dll`, `cublas64_12.dll`, `cublasLt64_12.dll`.
3. **Model** — `qwen2.5-1.5b-instruct-q4_k_m.gguf` (+ `q2_k` for the quant-sweep) in `models\`,
   recorded in `models\active.json`.

> GPU sanity check: `build\bin\llama-bench.exe --list-devices`
> → `CUDA0: NVIDIA GeForce GTX 1650 (4095 MiB, ... free)`

## Run it on the GPU

```powershell
$bin = "BONUS-llama-cpp-optimization\llama.cpp\build\bin"
$model = (Get-Content models\active.json -Raw | ConvertFrom-Json).primary_model

# Interactive chat, fully GPU-offloaded (-ngl 99 = all layers on GPU). Type /exit to quit.
& "$bin\llama-cli.exe" -m $model -ngl 99 -t 6 -p "Explain KV cache in one sentence."

# Throughput benchmark — NON-interactive, prints prompt+decode tok/s and exits.
& "$bin\llama-bench.exe" -m $model -ngl 99 -p 512 -n 128

# OpenAI-compatible server with Prometheus /metrics on :8080 (GPU) — the main serving path.
pwsh -File 02-llama-cpp-server\start-server-native.ps1
#   chat: POST http://localhost:8080/v1/chat/completions
#   metrics: http://localhost:8080/metrics
```

`-ngl 99` offloads every layer to the GPU. The 1.5B Q4 model (~1 GB) fits comfortably in the
4 GB VRAM. For a bigger model that doesn't fit, lower `-ngl` (e.g. `-ngl 20`) for partial offload.

> In this build `llama-cli` / `llama-completion` open an **interactive** chat (they answer your
> prompt, then wait — exit with `/exit` or Ctrl+C). For scripted/automated runs use
> `llama-bench` (non-interactive) or hit the **server** HTTP API.

> Note: GTX 1650 (TU117) has **no tensor cores**, so llama.cpp prints a "suboptimal performance"
> hint. It still runs fully on the GPU — that warning is informational, not an error.

## Benchmark (this machine)

`llama-bench.exe -m qwen2.5-1.5b-instruct-q4_k_m.gguf -p 512 -n 128`, build b9771:

| test | CPU (`-ngl 0 -t 6`) | GPU (`-ngl 99`) | GPU speedup |
|---|---|---|---|
| pp512 (prefill) | 357.5 t/s | 414.2 t/s | 1.16× |
| **tg128 (decode)** | 34.4 t/s | **93.4 t/s** | **2.71×** |

Decode (the latency a user feels token-by-token) is **~2.7× faster on the GPU**. Prefill is
already compute-fast on this small model so the GPU edge there is small. Headline: full GPU
offload of Qwen2.5-1.5B Q4_K_M on a 4 GB GTX 1650 → **~93 tokens/s decode**.
