# Bonus — GPU-offload sweep

Model: `qwen2.5-1.5b-instruct-q4_k_m.gguf`  ·  threads: `6`

| -ngl | tg128 (tok/s) |
|--:|--:|
| 0 | 35.2 |
| 8 | 44.4 |
| 16 | 51.1 |
| 24 | 71.6 |
| 32 | 94.8 |
| 99 | 95.0 |

When the model fits in VRAM, `-ngl 99` (full offload) is fastest. When it doesn't, partial offload (`-ngl 16` or `-ngl 24`) keeps the most compute on the GPU while spilling weights to RAM — usually still beats CPU-only (`-ngl 0`). Watch for the curve flattening: after the layer count covers the model's actual depth, more `-ngl` does nothing.
