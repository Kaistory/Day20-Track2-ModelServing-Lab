@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "BIN=BONUS-llama-cpp-optimization\llama.cpp\build\bin"
set "MODEL=models\qwen2.5-1.5b-instruct-q4_k_m.gguf"

echo ============================================================
echo   CHAT (Terminal) - Qwen2.5-1.5B tren GPU GTX 1650
echo ============================================================
echo   Go cau hoi roi Enter de gui.  Go  /exit  hoac Ctrl+C de thoat.
echo ------------------------------------------------------------

"%BIN%\llama-cli.exe" -m "%MODEL%" -ngl 99 -t 6 -c 4096
