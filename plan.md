# Plan — Cài llama.cpp chạy GPU (Day 20 Lab) trên máy này

> Mục tiêu (yêu cầu của bạn): đọc `HARDWARE-GUIDE.md` + `README.md`, rồi **cài llama chạy GPU** cho máy tính này.
> File này ghi lại **toàn bộ** những gì đã làm, vì sao, và cách dùng.

---

## 0. Phần cứng phát hiện được

| Thành phần | Giá trị | Ý nghĩa |
|---|---|---|
| GPU | NVIDIA GeForce **GTX 1650**, 4 GB VRAM, Turing (compute 7.5) | Đủ offload model nhỏ (1.5–3B Q4) |
| Driver NVIDIA | 572.60 → tối đa **CUDA runtime 12.8** | Trần CUDA chạy được |
| CUDA Toolkit (nvcc) | **13.1** (cài sẵn, *cao hơn* mức driver hỗ trợ) | ⚠️ Build/binary CUDA 13.1 sẽ lỗi runtime |
| CPU | AMD Ryzen 5 5500U, 6 nhân / 12 luồng | `-t 6` |
| RAM | 15.3 GB → tier **Qwen2.5-1.5B-Instruct Q4_K_M** | model ~1 GB |
| Toolchain | cmake 4.3.1, MSVC Build Tools 2022, git, conda | có sẵn |
| Python | `python`=3.14 (quá mới), 3.13, conda | lab cần 3.10–3.12 → tạo env 3.12 |

→ `hardware.json` đã được ghi (GPU nhận đúng là backend **CUDA**).

---

## 1. Quyết định kỹ thuật cốt lõi

**Vấn đề:** driver chỉ chạy CUDA ≤ 12.8, nhưng toolkit cài là 13.1. Đồng thời wheel CUDA
dựng sẵn của `llama-cpp-python` chỉ tới bản 0.2.67 (giữa 2024) — quá cũ, không nạp được
GGUF Qwen2.5 / Llama-3.2 mà lab dùng.

**3 hướng đã cân nhắc:**
1. ✅ **Native CUDA 12.4 binaries** (đã chọn) — tải binary `llama.cpp` dựng sẵn (cudart 12.4 ≤ 12.8 ✓). Không cần build, hỗ trợ model mới, chạy ngay trên driver hiện tại.
2. Build `llama-cpp-python` từ source với CUDA — cần CUDA 12.x toolkit (~3GB) hoặc nâng driver, build 15–30', dễ vướng lỗi trên Windows.
3. Cả hai.

**Bạn đã chọn hướng 1.** Lý do hợp lý: nhanh nhất, chắc nhất, phủ phần lớn lab
(`serve-native`, §2 `/metrics`, các sweep bonus), và né hoàn toàn xung đột CUDA 13.1.

---

## 2. Các bước đã thực hiện

### Bước 1 — Probe phần cứng ✅
```powershell
$env:PYTHONUTF8='1'; python .\00-setup\detect-hardware.py
```
→ ghi `hardware.json`. (Phải set `PYTHONUTF8=1` vì console cp1252 không in được ký tự `─`.)

### Bước 2 — Môi trường Python 3.12 ✅
`python` mặc định là 3.14 (quá mới cho wheel của lab) → tạo conda env riêng:
```powershell
conda create -n day20 python=3.12 -y
C:\Users\Kaito\miniconda3\envs\day20\python.exe -m pip install -r requirements.txt
```
`requirements.txt` **không** chứa `llama-cpp-python` (lab cài riêng theo backend) → đường
native không cần build gì. Deps: huggingface_hub, locust, httpx, numpy, matplotlib…

### Bước 3 — Tải + giải nén binary GPU ✅
Từ release **b9771** của `ggml-org/llama.cpp` (đúng bản lab pin trong `make build-llama`):
```
llama-b9771-bin-win-cuda-12.4-x64.zip   (249.5 MB)
cudart-llama-bin-win-cuda-12.4-x64.zip  (373.3 MB)  ← runtime CUDA 12.4
```
Tải bằng `curl.exe` (có `--retry`/resume — `Invoke-WebRequest` bị treo giữa chừng do CDN
GitHub chập chờn). Giải nén vào:
```
BONUS-llama-cpp-optimization\llama.cpp\build\bin\
```
(đúng đường `start-server-native.sh` kỳ vọng). Có đủ `llama-server.exe`, `llama-cli.exe`,
`llama-bench.exe`, `ggml-cuda.dll`, `cudart64_12.dll`, `cublas64_12.dll`, `cublasLt64_12.dll`.

**Kiểm tra GPU nhận diện:**
```
llama-bench.exe --list-devices
→ found 1 CUDA devices: NVIDIA GeForce GTX 1650, compute capability 7.5
→ load_backend: loaded CUDA backend from ...ggml-cuda.dll
→ CUDA0: NVIDIA GeForce GTX 1650 (4095 MiB, 3296 MiB free)
```
✅ GPU chạy được llama.cpp qua CUDA backend.

### Bước 4 — Tải model GGUF ⏳ (đang chạy)
Tier theo RAM = **Qwen2.5-1.5B-Instruct** (q4_k_m ~1 GB + q2_k ~0.7 GB cho quant-sweep).
`huggingface_hub` 1.20 dùng **hf-xet** mặc định và bị **stall ở 0 MB** trên mạng này
→ chuyển sang tải thẳng `.gguf` bằng `curl.exe` từ URL resolve của HuggingFace (≈2.3 MB/s, ổn).
```powershell
curl.exe -L --fail --retry 8 -C - -o models\qwen2.5-1.5b-instruct-q4_k_m.gguf `
  https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
```
Sau khi tải xong sẽ chạy `download-model.py --skip-download` để ghi `models/active.json`.

### Bước 5 — Verify GPU offload thật ⏳ (chờ model)
Sẽ chạy:
```powershell
$model = (Get-Content models\active.json -Raw | ConvertFrom-Json).primary_model
build\bin\llama-bench.exe -m $model -ngl 99      # đo tok/s prefill + decode
build\bin\llama-cli.exe   -m $model -ngl 99 -p "..." -n 64
```
và kiểm `nvidia-smi` thấy VRAM tăng + log `offloaded N/N layers to GPU`.

---

## 3. File đã tạo / thay đổi

| File | Mục đích |
|---|---|
| `hardware.json` | Kết quả probe (các script khác đọc) |
| `models/` + `models/active.json` | Model GGUF + con trỏ |
| `BONUS-llama-cpp-optimization/llama.cpp/build/bin/*` | Binary GPU (55 file) |
| `02-llama-cpp-server/start-server-native.ps1` | **Mới** — launcher GPU server cho Windows (bản .ps1 còn thiếu của `start-server-native.sh`) |
| `SETUP-GPU-WINDOWS.md` | **Mới** — tài liệu cài đặt GPU + cách dùng |
| `plan.md` | **Mới** — file này |
| conda env `day20` (ngoài repo) | Python 3.12 + deps |

> Không sửa file gốc nào của lab. `.dl/` là thư mục tạm chứa zip đã tải (có thể xoá sau).

---

## 4. Cách dùng (sau khi model tải xong)

```powershell
$bin = "BONUS-llama-cpp-optimization\llama.cpp\build\bin"
$model = (Get-Content models\active.json -Raw | ConvertFrom-Json).primary_model

# Sinh văn bản, offload toàn bộ lên GPU
& "$bin\llama-cli.exe" -m $model -ngl 99 -p "Explain KV cache in one sentence." -n 64

# Benchmark throughput
& "$bin\llama-bench.exe" -m $model -ngl 99

# Server OpenAI-compat + Prometheus /metrics trên :8080 (GPU)
pwsh -File 02-llama-cpp-server\start-server-native.ps1
```

`-ngl 99` = đẩy hết layer lên GPU (model 1.5B ~1 GB vừa khít 4 GB VRAM). Model lớn không
vừa VRAM thì giảm `-ngl` (vd `-ngl 20`) để offload một phần.

> GTX 1650 (TU117) **không có tensor core** → llama.cpp in cảnh báo "suboptimal performance".
> Vẫn chạy đầy đủ trên GPU, đó chỉ là thông tin, không phải lỗi.

---

## 5. Trạng thái — ✅ HOÀN TẤT

- [x] Probe hardware → `hardware.json`
- [x] Tải + giải nén binary GPU CUDA 12.4 (b9771), xác nhận `--list-devices` thấy GTX 1650
- [x] Env Python 3.12 (`day20`) + deps
- [x] Script GPU server Windows + tài liệu
- [x] Tải model Qwen2.5-1.5B GGUF (q4_k_m 1065 MB + q2_k 718 MB) → `models/active.json`
- [x] **Verify GPU offload inference** — `llama-bench -ngl 99` (build b9771):

  | test | CPU (`-ngl 0 -t 6`) | GPU (`-ngl 99`) | Speedup |
  |---|---|---|---|
  | pp512 (prefill) | 357.5 t/s | 414.2 t/s | 1.16× |
  | **tg128 (decode)** | 34.4 t/s | **93.4 t/s** | **2.71×** |

**Kết quả:** GPU GTX 1650 chạy llama.cpp qua CUDA, offload toàn bộ Qwen2.5-1.5B Q4_K_M
(~1 GB, vừa 4 GB VRAM) → **~93 tokens/s decode, nhanh ~2.7× so với CPU**. Mục tiêu "cài
llama chạy GPU" đã đạt và kiểm chứng bằng số đo thật.
</content>
