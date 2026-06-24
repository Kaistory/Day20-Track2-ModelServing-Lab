@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "BIN=BONUS-llama-cpp-optimization\llama.cpp\build\bin"
set "MODEL=models\qwen2.5-1.5b-instruct-q4_k_m.gguf"

echo ============================================================
echo   BENCHMARK - do toc do GPU vs CPU (Qwen2.5-1.5B Q4_K_M)
echo ============================================================
echo.
echo === GPU  (-ngl 99, toan bo layer tren GTX 1650) ===
"%BIN%\llama-bench.exe" -m "%MODEL%" -ngl 99 -p 512 -n 128
echo.
echo === CPU  (-ngl 0, 6 nhan) de so sanh ===
"%BIN%\llama-bench.exe" -m "%MODEL%" -ngl 0 -t 6 -p 512 -n 128
echo.
echo Xong. pp512 = toc do prefill, tg128 = toc do sinh token (tok/s).
echo.
pause
