$ErrorActionPreference = 'Stop'

$userProfile = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($userProfile)) {
    throw 'No se pudo detectar la carpeta del usuario de Windows.'
}

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

$artSource = Join-Path $scriptRoot 'ascii-art.txt'
$configDir = Join-Path $userProfile '.config\fastfetch'
$logoDestination = Join-Path $configDir 'ascii-art.txt'
$configPath = Join-Path $configDir 'config.jsonc'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'WinGet no estÃ¡ disponible. Instala o actualiza App Installer desde Microsoft Store y vuelve a ejecutar este script.'
}

Write-Host 'Comprobando WinGet...'
$installed = winget list --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements 2>$null | Out-String
if ($installed -notmatch 'Fastfetch') {
    Write-Host 'Instalando Fastfetch con WinGet...'
    winget install --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet terminÃ³ con el cÃ³digo $LASTEXITCODE."
    }
} else {
    Write-Host 'Found installation.'
}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null
if (Test-Path -LiteralPath $artSource) {
    Copy-Item -LiteralPath $artSource -Destination $logoDestination -Force
} else {
    Write-Host 'no ascii error.'
    $embeddedArt = @'
............:::.:::::::::-::::::::::::::::::::::::.........
.............::::..:::::::::::::::::::::::::::::::::.....  
..........:::::::::..::--:::::::::::::::::::::::::::::.....
........:::::::::::::..:::::::::::::::::::::::::::::::::::. 
.....::::::::::::::::::...:::::::::::::::::::::::::::::::::
....::::::::::--:::::::::...:::::::::::::::::::::::::::::::
....:::::::::::::::::-+-:::...:::::::::::::::::::::::::::::
.......:::::==:::::::--***-::...:::::::::::::::::::.:::::::
.....::-:::::=**-:::::*=#%%#*+:..::::::::::::::::::::.:::::
...:::::==::::#%%#=:::+#%%%%%%%%%#--::::::::::::::::::.::::
...=::=::#*-:::%%#=#=:=%%%%%%+...#*=--:::::::::::::::::..::
......=+::#%*::*%%%%%#*%%%-:=*:::#%%--:::::::::::::::::...:
......-++:-%%%-=%%%%%%#%-:#%%#=*#%%%*-:::::::::-==-:::::...
 .....:+++:*%%%*%%%%%*%**%%%%@%%%%%%#-:::.::::::::::::::...
  . ...-++==%%%%%%%%%%%%%%%%%%%%%%%%=++::..:::::::::::::.  
     ..:===-%%@%%%%%%%%%%%%%%%%%%%%*##%-:...:::::::::::.:. 
       .=+++*%%%%%%%%%%%%%%%%%%%%%%%%%%-:....::::::::::::. 
    :.   ++++++#%#%%%%%%%%%%%%%%%%%%%%%-:.....:::::.::::.=.
    ..-. .=++= :%=:*%%%%%%%%%%%%%%%%%%%=:.....:::::..::::-.
     .-==+++-.*%%#*#%%%%%%%%%%%%%%%#%%%#:.... .:::. .......
           .:-++***%%%%%%%%%%%%%%%%%%%%%#...  .::.   ......
                -++*%%%%%%%%%%%%%%%%%%%%@%+.. .::.   ...:..
                  .-:*%%%%%%%%%%%%%%%%%%%%***-...  .....-..
                     :=+++*********####%+.-**+:.    ....::.
                                           .=+:.     ..:::.
                                             ::     ...--.-
:.....                                               ...:-:
'@
    Set-Content -LiteralPath $logoDestination -Value $embeddedArt -Encoding UTF8
}

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

Write-Host "Created configuration: $configPath"
Write-Host "ASCII installed: $logoDestination"
Write-Host "PREFIX: dung"

if (Test-Path -LiteralPath $dungPath) {
    Write-Host "`VALID:"
    & $dungPath
} else {
    Write-Host "`ALL IN! execute: dung"
}
