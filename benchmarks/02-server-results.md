# 02 — llama-server Load Test Results

Server: **native llama.cpp `llama-server.exe`** (CUDA build b9771), GPU offload `-ngl 99`,
`--parallel 4 --cont-batching --ctx-size 4096 --metrics`, model `qwen2.5-1.5b-instruct-q4_k_m.gguf`
on NVIDIA GTX 1650 (4 GB). Driver via locust on the same machine (loopback).

## Load runs (locust, headless, 60 s)

| Concurrency | # reqs | Failures | RPS | Median (ms) | P95 (ms) | P99 (ms) | Max (ms) |
|--:|--:|--:|--:|--:|--:|--:|--:|
| 10 | 115 | 0 (0.00%) | 1.93 | 3 700 | 5 700 | 6 200 | 8 200 |
| 50 | 127 | 0 (0.00%) | 2.15 | 20 000 | 22 000 | 23 000 | 25 000 |

Per-route (P95): u10 → short 4 800 / long-rag 8 200; u50 → short 22 000 / long-rag 23 000.

## Continuous-batching observation (native `/metrics`, recorded during the u50 run)

`benchmarks/02-server-metrics.csv` (16 samples, 2 s interval):

| metric | peak |
|---|--:|
| `llamacpp:n_busy_slots_per_decode` | **3.87** (of 4 slots ≈ 97 % utilisation) |
| `llamacpp:requests_processing` | **4** (all slots busy) |
| `llamacpp:requests_deferred` | **46** (queued, waiting for a free slot) |
| `llamacpp:tokens_predicted_total` | 17 029 (cumulative) |

## Reading

The headline is the **goodput vs throughput** gap. Going 10 → 50 users barely moved
throughput (1.93 → 2.15 req/s) because the engine only has **4 decode slots** — once all 4
are busy (`requests_processing = 4`, `n_busy_slots ≈ 3.87`), the other ~46 requests sit in
`requests_deferred` and just wait. So the extra 40 users buy almost no extra useful work;
they only inflate latency (median 3.7 s → 20 s, P95 5.7 s → 22 s). Throughput saturated,
goodput@SLO collapsed. The fix in production is more slots / more replicas / disaggregated
prefill-decode, not more concurrency against a fixed 4-slot engine.
