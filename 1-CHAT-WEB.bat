@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "BIN=BONUS-llama-cpp-optimization\llama.cpp\build\bin"
set "MODEL=models\qwen2.5-1.5b-instruct-q4_k_m.gguf"

echo ============================================================
echo   CHAT (Web UI) - Qwen2.5-1.5B tren GPU GTX 1650
echo ============================================================
echo   Server chay o cua so rieng, roi trinh duyet tu mo.
echo   De TAT model: dong cua so den ten "llama-server".
echo ------------------------------------------------------------

start "llama-server" "%BIN%\llama-server.exe" -m "%MODEL%" --host 127.0.0.1 --port 8080 -t 6 -ngl 99 --parallel 4 --cont-batching --ctx-size 4096 --metrics

echo Dang doi server khoi dong (~10 giay)...
timeout /t 10 /nobreak >nul
start "" http://localhost:8080
echo.
echo Da mo http://localhost:8080 trong trinh duyet.
echo Neu trang con trang, doi them vai giay roi nhan F5.
echo.
pause
