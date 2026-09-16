$ErrorActionPreference = 'Stop'

$artSource = Join-Path $PSScriptRoot 'ascii-art.txt'
$configDir = Join-Path $env:USERPROFILE '.config\fastfetch'
$logoDestination = Join-Path $configDir 'ascii-art.txt'
$configPath = Join-Path $configDir 'config.jsonc'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'WinGet no está disponible. Instala o actualiza App Installer desde Microsoft Store y vuelve a ejecutar este script.'
}

if (-not (Test-Path -LiteralPath $artSource)) {
    throw "No se encontró el archivo del ASCII art: $artSource"
}

Write-Host 'Comprobando Fastfetch con WinGet...'
$installed = winget list --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements 2>$null | Out-String
if ($installed -notmatch 'Fastfetch') {
    Write-Host 'Instalando Fastfetch con WinGet...'
    winget install --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet terminó con el código $LASTEXITCODE."
    }
} else {
    Write-Host 'Fastfetch ya está instalado; se conservará la instalación actual.'
}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null
Copy-Item -LiteralPath $artSource -Destination $logoDestination -Force

$config = @'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "file-raw",
    "source": "%USERPROFILE%/.config/fastfetch/ascii-art.txt"
  },
  "modules": [
    "title",
    "separator",
    "os",
    "host",
    "kernel",
    "uptime",
    "shell",
    "cpu",
    "gpu",
    "memory",
    "disk",
    "battery"
  ]
}
'@

Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8

$binDir = Join-Path $env:USERPROFILE 'bin'
$dungPath = Join-Path $binDir 'dung.cmd'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null

$dungCommand = @'
@echo off
setlocal
set "FF="
for /f "delims=" %%F in ('where fastfetch 2^>nul') do set "FF=%%F" & goto :run
for /r "%LOCALAPPDATA%\Microsoft\WinGet\Packages" %%F in (fastfetch.exe) do set "FF=%%F" & goto :run
:run
if not defined FF (
  echo Fastfetch no fue encontrado.
  exit /b 1
)
"%FF%" %*
'@
Set-Content -LiteralPath $dungPath -Value $dungCommand -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathItems = @()
if ($userPath) {
    $pathItems = $userPath -split ';' | Where-Object { $_ -and $_.Trim() }
}
if (-not ($pathItems | Where-Object { $_.TrimEnd('\') -ieq $binDir.TrimEnd('\') })) {
    [Environment]::SetEnvironmentVariable('Path', (($pathItems + $binDir) -join ';'), 'User')
}

Write-Host "Configuración creada en: $configPath"
Write-Host "Logo instalado en: $logoDestination"
Write-Host "Comando creado: dung"

if (Test-Path -LiteralPath $dungPath) {
    Write-Host "`nValidación:"
    & $dungPath
} else {
    Write-Host "`nFastfetch fue instalado. Cierra y vuelve a abrir PowerShell para actualizar el PATH; después ejecuta: dung"
}
