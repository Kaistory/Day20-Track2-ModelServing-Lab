# Launch the NATIVE llama.cpp `llama-server.exe` WITH Prometheus /metrics on :8080 — GPU build.
# Windows PowerShell 7+ companion to start-server-native.sh.
#
# Why this exists: the Python server (start-server.ps1, `python -m llama_cpp.server`) is the
# zero-build chat+load path but has NO /metrics endpoint. The §2/§3 observability step
# (/metrics, n_busy_slots_per_decode, requests_processing) needs this native binary.
#
# The CUDA 12.4 prebuilt binaries live under BONUS-.../llama.cpp/build/bin/ (see SETUP-GPU-WINDOWS.md).
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$Bin = "BONUS-llama-cpp-optimization\llama.cpp\build\bin\llama-server.exe"
if (-not (Test-Path $Bin)) {
    Write-Host "ERROR: native llama-server.exe not found at $Bin" -ForegroundColor Red
    Write-Host "       See SETUP-GPU-WINDOWS.md to download the CUDA binaries." -ForegroundColor Red
    exit 1
}

$active  = Get-Content 'models/active.json' -Raw | ConvertFrom-Json
$model   = $active.primary_model
$hw      = Get-Content 'hardware.json'    -Raw | ConvertFrom-Json
$threads = if ($hw.cpu.cores_physical) { $hw.cpu.cores_physical } else { 4 }
$ngl     = if ($env:LAB_N_GPU_LAYERS) { $env:LAB_N_GPU_LAYERS } else { '99' }
$parallel= if ($env:LAB_PARALLEL)     { $env:LAB_PARALLEL }     else { '4' }
$ctx     = if ($env:LAB_N_CTX)        { $env:LAB_N_CTX }        else { '2048' }

Write-Host "==> Starting NATIVE llama-server (CUDA, with --metrics) on http://0.0.0.0:8080" -ForegroundColor Cyan
Write-Host "    binary  : $Bin"
Write-Host "    model   : $model"
Write-Host "    threads : $threads   parallel: $parallel   ctx: $ctx   ngl: $ngl (GPU offload)"
Write-Host "    metrics : http://localhost:8080/metrics"
Write-Host ""

& $Bin `
    -m $model `
    --host 0.0.0.0 --port 8080 `
    -t $threads `
    -ngl $ngl `
    --parallel $parallel --cont-batching `
    --ctx-size $ctx `
    --metrics
