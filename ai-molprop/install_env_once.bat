@echo off
REM ============================================================
REM  install_env_once.bat
REM  One-time setup on a NEW computer (needs internet, ~15-40 min)
REM  1) finds conda (Miniconda/Anaconda) on this computer
REM  2) creates env "molprop" (Python 3.10)
REM  3) installs CPU PyTorch + everything in requirements.txt
REM  4) verifies imports; afterwards double-click start_web.bat
REM ============================================================
chcp 65001 >nul
set "PYTHONUTF8=1"
cd /d "%~dp0"

set "COND="

REM --- locate conda ---
if exist "%USERPROFILE%\miniconda3\Scripts\conda.exe" set "COND=%USERPROFILE%\miniconda3\Scripts\conda.exe"
if not defined COND if exist "%USERPROFILE%\anaconda3\Scripts\conda.exe" set "COND=%USERPROFILE%\anaconda3\Scripts\conda.exe"
if not defined COND if exist "%USERPROFILE%\Miniconda3\Scripts\conda.exe" set "COND=%USERPROFILE%\Miniconda3\Scripts\conda.exe"
if not defined COND if exist "%USERPROFILE%\Anaconda3\Scripts\conda.exe" set "COND=%USERPROFILE%\Anaconda3\Scripts\conda.exe"
if not defined COND if exist "C:\ProgramData\miniconda3\Scripts\conda.exe" set "COND=C:\ProgramData\miniconda3\Scripts\conda.exe"
if not defined COND if exist "C:\ProgramData\Anaconda3\Scripts\conda.exe" set "COND=C:\ProgramData\Anaconda3\Scripts\conda.exe"
if not defined COND for /f "delims=" %%C in ('where conda 2^>nul') do if not defined COND set "COND=%%C"

if not defined COND goto :no_conda
echo Found conda: %COND%

echo.
echo [1/5] Creating environment "molprop" (Python 3.10) ...
"%COND%" create -n molprop python=3.10 -y
if errorlevel 1 goto :err

REM --- best-effort accept ToS on newer conda versions (ignored on older) ---
"%COND%" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >nul 2>nul
"%COND%" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r >nul 2>nul
"%COND%" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2 >nul 2>nul

echo.
echo [2/5] Installing CPU PyTorch ...
"%COND%" run -n molprop python -m pip install --upgrade pip setuptools wheel
"%COND%" run -n molprop python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
if errorlevel 1 goto :err

echo.
echo [3/5] Installing all project dependencies from requirements.txt ...
"%COND%" run -n molprop python -m pip install -r requirements.txt
if errorlevel 1 goto :err

echo.
echo [4/5] Verifying imports ...
"%COND%" run -n molprop python -c "import numpy, rdkit, deepchem, torch, tensorflow; print('core deps OK')"
if errorlevel 1 goto :err

echo.
echo [5/5] Done!
echo.
echo  All set. Now double-click:   start_web.bat
echo  (or run: conda activate molprop  then  python run.py web)
echo  Optional: image-recognition weights - run: python run.py ocr-setup
pause
exit /b 0

:no_conda
echo.
echo  [ERROR] conda was not found on this computer.
echo  Please install Miniconda first, then run this installer again.
echo  Miniconda download: https://docs.conda.io/en/latest/miniconda.html
pause
exit /b 1

:err
echo.
echo  [ERROR] Something went wrong during installation.
echo  Please read the red message above and send it to the developer,
echo  or try running the commands in README.md manually.
pause
exit /b 1
