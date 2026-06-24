# Reflection — Lab 20 (Personal Report)

> **Đây là báo cáo cá nhân.** Mỗi học viên chạy lab trên laptop của mình, với spec của mình. Số liệu của bạn không so sánh được với bạn cùng lớp — chỉ so sánh **before vs after trên chính máy bạn**.

---

**Họ Tên:** Dương Quang Khải
**Cohort:** AICB-P2T2 · Ngày 20 (Track 2)
**Ngày submit:** 2026-06-24

---

## 1. Hardware spec (từ `00-setup/detect-hardware.py`)

- **OS:** Windows 10 (build 19045)
- **CPU:** AMD Ryzen 5 5500U with Radeon Graphics (Zen 2)
- **Cores:** 6 physical / 12 logical
- **CPU extensions:** AVX2
- **RAM:** 15.3 GB
- **Accelerator:** NVIDIA GeForce GTX 1650, 4 GB VRAM, Turing (compute 7.5)
- **llama.cpp backend đã chọn:** CUDA (native prebuilt CUDA 12.4 binaries)
- **Recommended model tier:** Qwen2.5-1.5B-Instruct (Q4_K_M)

**Setup story:** Driver (572.60) chỉ chạy CUDA ≤ 12.8 nhưng toolkit cài là 13.1, và wheel CUDA của
`llama-cpp-python` quá cũ (0.2.67, không nạp được Qwen2.5). Nên dùng **native llama.cpp CUDA 12.4
binaries** (cudart 12.4 ≤ driver 12.8) để serve GPU, và **build `llama-cpp-python` từ source (CPU)**
cho bench. Python 3.12 (conda) vì `python` hệ thống là 3.14 quá mới. Model tải bằng `curl` trực tiếp
(hf-xet bị stall).

---

## 2. Track 01 — Quickstart numbers (từ `benchmarks/01-quickstart-results.md`)

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|--:|--:|--:|--:|--:|
| qwen2.5-1.5b-instruct-q4_k_m.gguf | 1 152 | 110 / 125 | 31.5 / 34.3 | 2 080 / 2 207 / 2 261 | 31.8 |
| qwen2.5-1.5b-instruct-q2_k.gguf | 542 | 154 / 186 | 26.4 / 26.6 | 1 822 / 1 860 / 1 860 | 37.9 |

> Track 01 `benchmark.py` chạy qua `llama-cpp-python` **build CPU** (in-process), nên đây là số liệu
> CPU baseline. Đường GPU đo riêng bằng native `llama-bench` ở §5.

**Quan sát:** Q2_K nhanh hơn ~19% decode (37.9 vs 31.8 tok/s) và load nhẹ hơn một nửa, nhưng Q4_K_M
cho text tốt hơn rõ. Trên 15 GB RAM, chênh lệch tốc độ nhỏ này không đáng để hi sinh quality —
Q4_K_M là default đúng; Q2_K chỉ dành cho khi RAM thực sự ngặt.

---

## 3. Track 02 — llama-server load test

Native `llama-server` (CUDA, `-ngl 99 --parallel 4 --cont-batching --ctx-size 4096 --metrics`),
locust headless 60 s. Request không streaming nên "TTFB P50" ≈ full-response median.

| Concurrency | Total RPS | TTFB/Median P50 (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 1.93 | 3 700 | 5 700 | 6 200 | 0 |
| 50 | 2.15 | 20 000 | 22 000 | 23 000 | 0 |

**Batching observation** (từ `record-metrics.py` → `benchmarks/02-server-metrics.csv`, trong lúc load u50):
peak `llamacpp:n_busy_slots_per_decode` = **3.87** (của 4 slot), `requests_processing` = **4**,
`requests_deferred` = **46**.

Nghĩa là: engine chỉ có 4 decode slot. Đi từ 10 → 50 user, throughput gần như đứng yên
(1.93 → 2.15 req/s) vì cả 4 slot đã bận liên tục; ~46 request còn lại chỉ **xếp hàng**
(`requests_deferred`). Latency vì thế nổ tung (P50 3.7 s → 20 s, P95 5.7 s → 22 s) trong khi
useful work không tăng. Đây chính là **goodput sụp đổ dù throughput đã bão hòa** — thêm concurrency
vào một engine 4-slot cố định không mua được gì ngoài độ trễ.

---

## 4. Track 03 — Milestone integration

- **N16 (Cloud/IaC):** stub — chạy localhost, không cluster.
- **N17 (Data pipeline):** stub — không có ingestion job.
- **N18 (Lakehouse):** stub — không có Delta/Iceberg.
- **N19 (Vector + Feature Store):** stub — `TOY_DOCS` + keyword-overlap retrieval (chưa cắm vector index thật).
- **llama-server (N20, track này):** **real** — native CUDA `llama-server` trên :8080, gọi qua OpenAI-compat API.

**Nơi tốn nhiều ms nhất** (đo bằng `time.perf_counter` trong `pipeline.py`, 3 query):

- embed: — (không có embedder, dùng keyword overlap)
- retrieve: ~0.0 ms (toy, in-memory)
- llama-server: 2 685 / 3 593 / 4 973 ms (median ~3 593 ms)

**Reflection:** Bottleneck nằm gần như hoàn toàn ở **llama-server** (LLM generation), đúng kỳ vọng —
retrieval toy là tức thời, còn sinh 200 token trên một model 1.5B mới là phần đắt. Trong hệ thật,
khi N19 là vector index thật thì retrieve sẽ tốn vài chục ms, nhưng LLM call vẫn sẽ là phần lớn nhất.

---

## 5. Bonus — The single change that mattered most

**Change:** Bật **full GPU offload** (`-ngl 99`) bằng native llama.cpp **CUDA build**, thay cho chạy CPU.

**Before vs after** (native `llama-bench`, Qwen2.5-1.5B Q4_K_M, decode `tg128`):

```
before (-ngl 0,  CPU, 6 threads):  34.4 tok/s
after  (-ngl 99, GPU GTX 1650):    95.0 tok/s
speedup: ~2.7×
```

Offload sweep (`benchmarks/bonus-gpu-offload-sweep.md`) cho thấy đường cong rõ:
`-ngl` 0 → 8 → 16 → 24 → 32 → 99 = 35.2 → 44.4 → 51.1 → 71.6 → 94.8 → 95.0 tok/s.

**Tại sao nó work:** Decode (sinh từng token) **bị chặn bởi memory bandwidth**, không phải compute.
Mỗi token phải đọc toàn bộ ~1 tỷ tham số (quantized) từ bộ nhớ một lần. GDDR6 của GTX 1650 (~192 GB/s)
nhanh hơn nhiều DDR4 dual-channel của Ryzen (~50 GB/s), nên khi mọi layer nằm trên GPU, token sinh ra
nhanh hơn ~2.7×. Đường cong sweep cũng khớp mental model: mỗi layer đẩy lên GPU thêm một ít bandwidth,
và **phẳng sau ~ngl 32** vì model chỉ có ~29 layer — thêm `-ngl` sau đó không còn gì để offload.

Một nuance đáng nói: prefill (`pp512`) gần như **không** nhanh hơn trên GPU (357 → 414 tok/s) vì prefill
là compute-bound và đã batch tốt; trên model 1.5B nhỏ, CPU không bị bandwidth-starve ở prefill. Và GTX
1650 (TU117) **không có tensor core**, nên tốc độ GPU này vẫn thấp hơn một GPU có tensor core — 2.7×
ở đây thuần là nhờ memory bandwidth, không phải matmul acceleration.

---

## 6. (Optional) Điều ngạc nhiên nhất

Throughput hầu như không nhúc nhích khi tăng concurrency 10 → 50 (1.93 → 2.15 req/s) trong khi latency
tăng ~5.5×. Nhìn `requests_deferred = 46` mới thấy rõ: 50 user nhưng chỉ 4 slot, 46 cái còn lại chỉ
ngồi chờ. "Goodput chứ không phải throughput" từ deck §0/§8 hiện ra rất cụ thể bằng đúng một con số.

---

## 7. Self-graded checklist

- [x] `hardware.json` đã commit
- [x] `models/active.json` đã commit
- [x] `benchmarks/01-quickstart-results.md` đã commit
- [x] `benchmarks/02-server-results.md` + CSV từ `record-metrics.py` đã commit
- [x] `benchmarks/bonus-*.md` đã commit (gpu-offload sweep)
- [x] ≥ 6 screenshots trong `submission/screenshots/`
- [x] `make verify` exit 0
- [ ] Repo trên GitHub ở chế độ **public**
- [ ] Đã paste public repo URL vào VinUni LMS

---

**Quan trọng:** repo phải **public** đến khi điểm được công bố.
