@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "BIN=BONUS-llama-cpp-optimization\llama.cpp\build\bin"
set "MODEL=models\qwen2.5-1.5b-instruct-q4_k_m.gguf"

echo ============================================================
echo   SERVER API (OpenAI-compatible) tren GPU
echo ============================================================
echo   Chat / API : http://localhost:8080
echo   Metrics    : http://localhost:8080/metrics
echo   Tat server : nhan Ctrl+C trong cua so nay.
echo ------------------------------------------------------------

"%BIN%\llama-server.exe" -m "%MODEL%" --host 0.0.0.0 --port 8080 -t 6 -ngl 99 --parallel 4 --cont-batching --ctx-size 4096 --metrics
