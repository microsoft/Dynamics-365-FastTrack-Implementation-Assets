@echo off
setlocal

REM ============================================================
REM   Payment Recon Agent - Full Installer Launcher
REM ============================================================

title Payment Recon V1 - Unified Installer (Create/Update)
color 07
mode con: cols=100 lines=42

set "PS_SCRIPT=%~dp0Install-PaymentRecon.ps1"

if not exist "%PS_SCRIPT%" (
    color 4F
    echo.
    echo  [ERROR] Installer script not found:
    echo          %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

set "PWSH_EXE="
where pwsh.exe >nul 2>&1
if %ERRORLEVEL%==0 (
    set "PWSH_EXE=pwsh.exe"
) else (
    where powershell.exe >nul 2>&1
    if %ERRORLEVEL%==0 (
        set "PWSH_EXE=powershell.exe"
    )
)

if "%PWSH_EXE%"=="" (
    color 4F
    echo.
    echo  [ERROR] PowerShell was not found on this machine.
    echo          Please install Windows PowerShell 5.1+ or PowerShell 7+.
    echo.
    pause
    exit /b 1
)

echo.
echo  Launching Payment Recon V1 unified installer using %PWSH_EXE% ...
echo.

"%PWSH_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "$Host.UI.RawUI.BackgroundColor='Black'; $Host.UI.RawUI.ForegroundColor='Gray'; Clear-Host; & '%PS_SCRIPT%'"
set "RC=%ERRORLEVEL%"

echo.
echo  ------------------------------------------------------------
if "%RC%"=="0" (
    color 2F
    echo                Installer finished successfully.
) else (
    color 4F
    echo                Installer exited with code %RC%.
)
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b %RC%
