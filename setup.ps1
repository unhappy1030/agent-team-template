# Windows entry point. agent-team needs tmux, which only runs on Linux, so this
# script makes sure WSL has a distro and then runs setup.sh inside it.
#   powershell -ExecutionPolicy Bypass -File setup.ps1
# (ASCII only on purpose: Windows PowerShell 5.1 misreads UTF-8 without BOM.)
$ErrorActionPreference = 'Stop'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw "wsl.exe not found. Windows 10 2004+ or Windows 11 is required."
}

# A clone made before .gitattributes existed has CRLF scripts, which bash cannot run.
if ((Get-Content -Raw "$PSScriptRoot\setup.sh") -match "`r") {
  throw "setup.sh has CRLF line endings. In this folder run:  git rm --cached -r . ; git reset --hard"
}

# wsl -l -q prints UTF-16, so strip the NULs. docker-desktop distros are not usable shells.
$out = wsl.exe -l -q 2>$null
$distros = @()
if ($LASTEXITCODE -eq 0) {
  $distros = @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } |
    Where-Object { $_ -and $_ -notlike 'docker-desktop*' })
}

if (-not $distros) {
  Write-Host "No WSL distro found. Installing Ubuntu (admin prompt, reboot may be needed)..."
  Start-Process wsl.exe -ArgumentList '--install', '-d', 'Ubuntu' -Verb RunAs -Wait
  Write-Host "Open 'Ubuntu' once from the Start menu to create your Linux user, then run this script again."
  exit 0
}

$distro = ($distros | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1)
if (-not $distro) { $distro = $distros[0] }
Write-Host "Running setup.sh in WSL ($distro)..."
wsl.exe -d $distro --cd "$PSScriptRoot" -- bash -l ./setup.sh
exit $LASTEXITCODE
