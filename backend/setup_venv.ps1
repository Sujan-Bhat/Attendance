# Create an isolated venv for Attendance (does not touch GSoC Django).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".venv")) {
    Write-Host "Creating .venv ..."
    py -3.12 -m venv .venv
}

Write-Host "Installing requirements into .venv ..."
$env:PYTHONPATH = $null
& ".venv\Scripts\python.exe" -m pip install --upgrade pip
& ".venv\Scripts\python.exe" -m pip install -r requirements.txt

Write-Host ""
Write-Host "Done. Use:"
Write-Host "  .\dev.ps1 python manage.py migrate"
Write-Host "  .\dev.ps1 python manage.py runserver"
