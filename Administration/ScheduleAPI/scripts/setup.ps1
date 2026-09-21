$ErrorActionPreference = "Stop"

function Find-CompatiblePython {
    $candidates = @()

    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        $candidates += $pythonCommand.Source
    }

    $userPythonRoot = Join-Path $env:LOCALAPPDATA "Programs\Python"
    if (Test-Path $userPythonRoot) {
        $candidates += Get-ChildItem $userPythonRoot -Filter python.exe -Recurse -File |
            Select-Object -ExpandProperty FullName
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        & $candidate -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $candidate
        }
    }

    return $null
}

$python = Find-CompatiblePython
if (-not $python) {
    Write-Host "Python 3.11 or later is required but was not found." -ForegroundColor Yellow
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($winget) {
        $answer = Read-Host "Install Python 3.13 for your Windows account now? [Y/N]"
        if ($answer -match "^[Yy]") {
            & $winget.Source install --id Python.Python.3.13 --exact --scope user --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) {
                throw "Python installation failed. Install it from https://www.python.org/downloads/windows/ and launch the application again."
            }
            $python = Find-CompatiblePython
        }
    }

    if (-not $python) {
        throw "Install Python 3.11 or later from https://www.python.org/downloads/windows/, select 'Add Python to PATH', then launch the application again."
    }
}

$venvPython = Join-Path $PSScriptRoot "..\.venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "Creating the project Python environment..."
    & $python -m venv (Join-Path $PSScriptRoot "..\.venv")
}

Write-Host "Installing required Python packages..."
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $PSScriptRoot "..\requirements.txt")

Write-Host "Application setup is complete." -ForegroundColor Green