# ============================================================
#  install_runtime.ps1  (ASCII ONLY - do not put non-ASCII text in this file!)
#
#  Why ASCII only: Windows PowerShell 5.1 reads .ps1 files without a BOM using
#  the system ANSI codepage (936/GBK on Chinese Windows). Non-ASCII comments get
#  decoded wrongly and can even swallow the following newline, which breaks the
#  script with a parse error like: "Unexpected token '}'". Keep this file ASCII.
#
#  One-click bootstrap for computers WITHOUT conda / without Python deps:
#    1) look for an existing Python that already has the packages
#       (set MOLPROP_FRESH=1 to skip this and always install the local runtime)
#    2) if none found: download & silently install Miniconda INTO the
#       project folder (runtime\miniconda3) - does NOT touch the system
#    3) create env "molprop" (Python 3.10) using a CN mirror with retries,
#       install CPU PyTorch and everything in requirements.txt (also mirrored)
#    4) start the web UI (python run.py)
#  Usage from install_and_start.bat / the Chinese-named one-click .bat
# ============================================================

$ErrorActionPreference = 'Continue'
# force UTF-8 so Chinese console output from python never breaks on GBK systems
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$proj = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $proj

$runtimeRoot   = Join-Path $proj 'runtime'
$instDir       = Join-Path $runtimeRoot 'miniconda3'
$localPy       = Join-Path $instDir 'envs\molprop\python.exe'
$minicondaExe  = Join-Path $runtimeRoot 'miniconda-installer.exe'
$url           = 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe'
$UA            = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

function Write-Step($msg){ Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Test-Py([string]$py){
    if(-not $py -or -not (Test-Path $py)){ return $false }
    & $py -c "import numpy,rdkit,deepchem,torch,tensorflow" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ---------- 1) find an already-capable python ----------
Write-Step "Looking for a Python with the required packages ..."
$candidates = @()
# MOLPROP_FRESH=1 -> pretend this is a brand-new computer: skip reuse of any
# existing environment and always install the self-contained runtime\ here.
$fresh = ($env:MOLPROP_FRESH -eq '1')
if($fresh){ Write-Host "MOLPROP_FRESH=1 -> ignoring existing Python environments (fresh-install simulation)" }
if(-not $fresh){
  if($env:MOLPROP_PYTHON){ $candidates += $env:MOLPROP_PYTHON }
  $candidates += $localPy
  if($env:CONDA_PREFIX){ $candidates += (Join-Path $env:CONDA_PREFIX 'python.exe') }
  $candidates += @(
    "$env:USERPROFILE\miniconda3\envs\molprop\python.exe",
    "$env:USERPROFILE\anaconda3\envs\molprop\python.exe",
    "C:\ProgramData\miniconda3\envs\molprop\python.exe",
    "C:\ProgramData\Anaconda3\envs\molprop\python.exe",
    "D:\miniconda3\envs\molprop\python.exe"
  )
  foreach($c in $candidates){ if(Test-Py $c){ Write-Host "Found capable Python: $c"; $py = $c; break } }
  if(-not $py){ foreach($p in (Get-Command python -ErrorAction SilentlyContinue)){ if(Test-Py $p.Source){ $py=$p.Source; break } } }
} else {
  if(Test-Py $localPy){ Write-Host "Found capable Python (local runtime): $localPy"; $py = $localPy }
}

if($py){
    Write-Step "Environment ready -> starting web UI ..."
    & $py (Join-Path $proj 'run.py')
    exit 0
}

# ---------- 2) no capable python -> local Miniconda ----------
Write-Step "No ready environment found. I will install one INSIDE this folder"
Write-Host  "        $instDir"
Write-Host  "(about 1.5-3 GB on disk, needs internet, first run may take 15-40 min)"

# robust resumable download (PowerShell)
function Download-Resume([string]$u,[string]$d){
    New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null
    for($i=0; $i -lt 40; $i++){
        $have = if(Test-Path $d){ (Get-Item $d).Length } else { 0 }
        try{
            $req=[System.Net.HttpWebRequest]::Create($u)
            $req.UserAgent=$UA; $req.Timeout=300000; $req.ReadWriteTimeout=300000
            if($have -gt 0){ $req.AddRange('bytes',$have) }
            $resp=$req.GetResponse()
            $total=$resp.ContentLength + $have
            $fs=[System.IO.File]::Open($d,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write)
            $s=$resp.GetResponseStream(); $buf=New-Object byte[] 1048576; $got=$have
            try{
                while(($n=$s.Read($buf,0,$buf.Length)) -gt 0){ $fs.Write($buf,0,$n); $got+=$n }
            } finally { $fs.Close(); $s.Close(); $resp.Close() }
            Write-Host ("download: {0:N0} / {1:N0} MB" -f ($got/1MB),($total/1MB))
            if($total -gt 0 -and $got -ge $total){ return $true }
        } catch {
            Write-Host ("download retry ({0}): {1}" -f ($i+1), $_.Exception.Message)
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

if(-not (Test-Path $instDir)){
    if(-not (Test-Path $minicondaExe)){
        Write-Step "Downloading Miniconda installer (about 130 MB) ..."
        if(-not (Download-Resume $url $minicondaExe)){ Write-Error "Download failed - please check internet"; exit 1 }
    }
    Write-Step "Installing Miniconda into $instDir (silent) ..."
    $argD = '/D=' + $instDir
    if($instDir -match ' '){   # NSIS /D= must be last and unquoted; use 8.3 short path
        try{
            $fso=New-Object -ComObject Scripting.FileSystemObject
            $root8=$fso.GetFolder($runtimeRoot).ShortPath
            $argD='/D=' + (Join-Path $root8 'miniconda3')
        } catch { }
    }
    $p=Start-Process -FilePath $minicondaExe -ArgumentList @('/S','/InstallationType=JustMe','/AddToPath=0','/RegisterPython=0',$argD) -Wait -PassThru
    if($p.ExitCode -ne 0 -or -not (Test-Path (Join-Path $instDir 'Scripts\conda.exe'))){ Write-Error 'Miniconda install failed'; exit 1 }
}

$conda = Join-Path $instDir 'Scripts\conda.exe'
if(-not (Test-Path $conda)){ Write-Error 'conda not found after install'; exit 1 }

# accept ToS on newer conda (ignore failure on older)
& $conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main  2>$null | Out-Null
& $conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r     2>$null | Out-Null
& $conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2 2>$null | Out-Null

# ---------- 2b) conda config: CN mirror + long timeouts + retries ----------
# Measured failure mode on lossy networks: the python package downloaded from the
# default channel gets truncated, then conda aborts with
#   "CondaVerificationError: The package ... appears to be corrupted".
# Fix: prefer the Tsinghua anaconda mirror, raise timeouts/retries, and clean the
# package cache between retries. Set MOLPROP_NO_CONDA_MIRROR=1 to use defaults.
$condarc = Join-Path $instDir '.condarc'
if(-not $env:MOLPROP_NO_CONDA_MIRROR){
    if(-not (Test-Path $condarc)){
        Write-Step "Writing conda mirror config (Tsinghua; faster and more reliable in CN) ..."
        $yml = @"
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
remote_connect_timeout_secs: 30
remote_read_timeout_secs: 180
remote_max_retries: 10
remote_backoff_factor: 4
"@
        Set-Content -Path $condarc -Value $yml -Encoding ASCII
    }
    & $conda config --set ssl_verify true 2>$null | Out-Null
}

if(-not (Test-Py $localPy)){
    # up to 3 attempts; clean the (possibly corrupted) package cache in between
    for($attempt=1; $attempt -le 3; $attempt++){
        Write-Step "Creating environment molprop (Python 3.10), attempt $attempt/3 ..."
        & $conda create -n molprop python=3.10 -y
        if($LASTEXITCODE -eq 0 -and (Test-Path $localPy)){ break }
        Write-Host "conda create failed -> cleaning package cache and retrying ..." -ForegroundColor Yellow
        & $conda clean -y --packages --tarballs --index-cache 2>$null | Out-Null
        Remove-Item -Recurse -Force (Join-Path $instDir 'envs\molprop') -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
    if(-not (Test-Path $localPy)){ Write-Error 'conda create failed (3 attempts)'; exit 1 }
}

if(-not (Test-Py $localPy)){
    # pip against lossy networks: --retries/--timeout plus a CN mirror first,
    # then fall back to the default PyPI index.
    # Note: do not pass both -i and --index-url (the latter wins); the mirror also
    # carries CPU-only torch wheels for Windows, so a single index is enough.
    $PIPMIRROR = 'https://pypi.tuna.tsinghua.edu.cn/simple'
    function Pip-Try([string[]]$pipArgs){
        Write-Host ("pip " + ($pipArgs -join ' ') + "   [mirror]")
        & $localPy -m pip @pipArgs -i $PIPMIRROR --retries 5 --timeout 60 --no-input
        if($LASTEXITCODE -eq 0){ return $true }
        Write-Host "pip failed with mirror -> retrying with default PyPI ..." -ForegroundColor Yellow
        & $localPy -m pip @pipArgs --retries 5 --timeout 60 --no-input
        if($LASTEXITCODE -eq 0){ return $true }
        Write-Host "pip failed again -> one more retry with default PyPI ..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        & $localPy -m pip @pipArgs --retries 8 --timeout 120 --no-input
        return ($LASTEXITCODE -eq 0)
    }
    Write-Step "Upgrading pip/setuptools/wheel ..."
    if(-not (Pip-Try @('install','--upgrade','pip','setuptools','wheel'))){ Write-Error 'pip bootstrap failed'; exit 1 }
    Write-Step "Installing CPU PyTorch ..."
    if(-not (Pip-Try @('install','torch'))){ Write-Error 'PyTorch install failed'; exit 1 }
    Write-Step "Installing project requirements (this is the long step) ..."
    if(-not (Pip-Try @('install','-r',(Join-Path $proj 'requirements.txt')))){ Write-Error 'requirements install failed'; exit 1 }
}
if(-not (Test-Py $localPy)){ Write-Error 'Environment setup failed'; exit 1 }

Write-Step "All set. Starting web UI ..."
& $localPy (Join-Path $proj 'run.py')
exit 0
