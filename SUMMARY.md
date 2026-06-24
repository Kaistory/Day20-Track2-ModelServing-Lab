# SUMMARY — Day 20 Lab: cài llama GPU + hoàn thành toàn bộ lab

Tổng kết tất cả công việc đã làm trên máy này (Windows 10, GTX 1650).
Chi tiết kỹ thuật GPU xem thêm [`plan.md`](plan.md) và [`SETUP-GPU-WINDOWS.md`](SETUP-GPU-WINDOWS.md).

---

## 0. Yêu cầu đã thực hiện

1. Đọc `HARDWARE-GUIDE.md` + `README.md` → **cài llama chạy GPU** cho máy.
2. Viết `plan.md` ghi lại quá trình.
3. Đọc `rubric.md` → **hoàn thành toàn bộ lab** (4 core tracks + bonus).
4. File tổng kết này.

---

## 1. Phần cứng phát hiện được

| Thành phần | Giá trị |
|---|---|
| GPU | NVIDIA GeForce **GTX 1650**, 4 GB VRAM, Turing (compute 7.5), **không tensor core** |
| Driver | 572.60 → CUDA runtime tối đa **12.8** |
| CUDA Toolkit | nvcc **13.1** (cao hơn driver hỗ trợ → không build/chạy CUDA 13.1 được) |
| CPU | AMD Ryzen 5 5500U, 6 nhân / 12 luồng, AVX2 |
| RAM | 15.3 GB → model tier **Qwen2.5-1.5B-Instruct Q4_K_M** |
| OS / toolchain | Windows 10 (19045), cmake 4.3, MSVC Build Tools 2022, conda |

---

## 2. Phần 1 — Cài llama chạy GPU

### Quyết định cốt lõi
Driver chạy CUDA ≤ 12.8 nhưng toolkit là 13.1; wheel CUDA của `llama-cpp-python` quá cũ
(0.2.67, không nạp Qwen2.5). → Chọn **native llama.cpp CUDA 12.4 binaries** (cudart 12.4 ≤ 12.8 ✓):
không cần build, hỗ trợ model mới, chạy ngay trên driver hiện tại.

### Đã làm
- `detect-hardware.py` → `hardware.json` (GPU nhận đúng backend CUDA).
- Tạo conda env **`day20` (Python 3.12)** + `requirements.txt` (system python 3.14 quá mới).
- Tải release **b9771**: `llama-b9771-bin-win-cuda-12.4-x64.zip` (249 MB) +
  `cudart-llama-bin-win-cuda-12.4-x64.zip` (373 MB) → giải nén vào
  `BONUS-llama-cpp-optimization/llama.cpp/build/bin/`.
- Tải model `qwen2.5-1.5b-instruct-q4_k_m.gguf` (1065 MB) + `q2_k` (718 MB) → `models/active.json`.

### Verify GPU (số thật, native `llama-bench`)
| test | CPU `-ngl 0` | GPU `-ngl 99` | Speedup |
|---|--:|--:|--:|
| pp512 (prefill) | 357.5 t/s | 414.2 t/s | 1.16× |
| **tg128 (decode)** | 34.4 t/s | **93–95 t/s** | **~2.7×** |

Sinh chữ thật: `"Say hello in 5 words." → "Hello, how can I help you today?"` @ 84.7 t/s.
`llama-bench --list-devices` → `CUDA0: NVIDIA GeForce GTX 1650`.

---

## 3. Phần 2 — Hoàn thành lab (rubric core 100đ + bonus 20đ)

### Track 00 — Setup
- `hardware.json` ✓ · `models/active.json` ✓ (Q4 primary + Q2 compare).

### Track 01 — Quickstart (`benchmark.py`, CPU qua llama-cpp-python build-from-source)
`benchmarks/01-quickstart-results.md`:

| Model | Load (ms) | TTFT P50/P95 | TPOT P50/P95 | E2E P50/P95/P99 | Decode |
|---|--:|--:|--:|--:|--:|
| Q4_K_M | 1 152 | 110 / 125 | 31.5 / 34.3 | 2080 / 2207 / 2261 | 31.8 t/s |
| Q2_K | 542 | 154 / 186 | 26.4 / 26.6 | 1822 / 1860 / 1860 | 37.9 t/s |

### Track 02 — llama-server (native CUDA, `-ngl 99 --parallel 4 --cont-batching --metrics`)
- smoke-test `/v1/chat/completions` OK · `/metrics` `tokens_predicted_total` ≠ 0.
- Load test (locust 60s) → `benchmarks/02-server-results.md`:

  | Concurrency | RPS | Median | P95 | P99 | Fails |
  |--:|--:|--:|--:|--:|--:|
  | 10 | 1.93 | 3 700 | 5 700 | 6 200 | 0 |
  | 50 | 2.15 | 20 000 | 22 000 | 23 000 | 0 |

- Continuous batching (CSV trong lúc load u50): peak `n_busy_slots_per_decode` **3.87/4**,
  `requests_processing` **4**, `requests_deferred` **46** → throughput bão hòa nhưng goodput sụp.

### Track 03 — Integration (`pipeline.py`)
3 query RAG qua native server, in provenance (`n20-paged/radix/disagg`) + timings
(LLM 2.7–5.0s, retrieve ~0ms). N16–N19 = stub, llama-server (N20) = real.

### Bonus
- `benchmarks/bonus-gpu-offload-sweep.md`: `-ngl` 0→8→16→24→32→99 = 35.2→44.4→51.1→71.6→94.8→95.0 t/s.
- Speedup định lượng trong REFLECTION §5; llama-cpp-python build từ source.

### Screenshots (7) — render từ output thật
`01-hardware-probe`, `02-quickstart-bench`, `03-server-running`, `04-locust-10`,
`05-locust-50`, `06-bonus-sweep`, `09-pipeline-output`.

### `submission/REFLECTION.md`
Điền đầy đủ 7 section bằng số thật. §5 "single change that mattered most" = GPU offload
2.7× với giải thích memory-bandwidth (GDDR6 ~192 GB/s vs DDR4 ~50 GB/s).

### ✅ `make verify` → **exit 0** (7 screenshots, mọi artifact đủ).

---

## 4. File đã tạo / sửa

| File | Loại | Mô tả |
|---|---|---|
| `hardware.json` | tạo | kết quả probe |
| `models/active.json` (+ GGUF, gitignored) | tạo | model + con trỏ |
| `BONUS-.../build/bin/*` (gitignored) | tạo | binary GPU CUDA 12.4 (55 file) |
| `benchmarks/01-quickstart-results.{md,json}` | tạo | Track 01 |
| `benchmarks/02-server-results.md` + `02-server-metrics.csv` | tạo | Track 02 |
| `benchmarks/bonus-gpu-offload-sweep.{md,json}` | tạo | bonus sweep |
| `submission/REFLECTION.md` | sửa | điền đầy đủ |
| `submission/screenshots/*.png` | tạo | 7 ảnh |
| `02-llama-cpp-server/start-server-native.ps1` | tạo | launcher GPU server cho Windows |
| `SETUP-GPU-WINDOWS.md`, `plan.md`, `SUMMARY.md` | tạo | tài liệu |
| `BONUS-.../benchmarks/gpu-offload-sweep.py` | sửa | fix bug regex `tg128`→`tg\d+` |
| `.gitignore` | sửa | thêm `.dl/`, `.claude/` |

---

## 5. Trục trặc đã xử lý

- Console cp1252 không in unicode → `PYTHONUTF8=1`.
- `Invoke-WebRequest` treo giữa chừng (CDN GitHub) → `curl.exe` có `--retry`/resume.
- `huggingface_hub` hf-xet stall 0 MB → tải `.gguf` thẳng bằng curl từ URL resolve.
- Wheel `llama-cpp-python` (CPU & CUDA) quá cũ cho Qwen2.5 → build từ source.
- Build lỗi **MAX_PATH 260** (webui svelte path sâu) → đặt `TMP=C:\t` ngắn.
- Sweep trả 0.0 do regex `tg128` vs lệnh `-n 64` → fix regex + dừng server để giải phóng VRAM.

---

## 6. Cách dùng nhanh

```powershell
$bin = "BONUS-llama-cpp-optimization\llama.cpp\build\bin"
$model = (Get-Content models\active.json -Raw | ConvertFrom-Json).primary_model
& "$bin\llama-bench.exe" -m $model -ngl 99 -p 512 -n 128     # đo tốc độ GPU
pwsh -File 02-llama-cpp-server\start-server-native.ps1        # server GPU :8080 + /metrics
```

---

## 7. Trạng thái & bước còn lại

**Đã xong:** toàn bộ rubric core (14/14) + bonus, `make verify` exit 0, repo sạch để commit
(GGUF 1GB + binaries đã gitignore, chỉ `models/active.json` được track).

**Cần bạn làm (gắn tài khoản GitHub của bạn):**
1. Commit + push lên GitHub, set repo **public**.
2. Paste public URL vào ô Day 20 trong VinUni LMS.

> `.dl/` (~1 GB scratch tải/build) có thể xoá để lấy lại dung lượng — binaries đã ở `build/bin/`.
