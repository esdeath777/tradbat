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
$binDir = Join-Path $userProfile 'bin'
$fastfetchLocalPath = Join-Path $binDir 'fastfetch.exe'

New-Item -ItemType Directory -Path $binDir -Force | Out-Null

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host '¿WinGet is here?...'
    $installed = winget list --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements 2>$null | Out-String
    if ($installed -notmatch 'Fastfetch') {
        Write-Host 'Installing with WinGet...'
        winget install --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet $LASTEXITCODE."
        }
    } else {
        Write-Host 'Already installed.'
    }
} else {
    Write-Host 'WinGet left the party. Come here GitHub...'
    $assetName = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        'fastfetch-windows-aarch64.zip'
    } else {
        'fastfetch-windows-amd64.zip'
    }
    $downloadUrl = "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$assetName"
    $zipPath = Join-Path $env:TEMP $assetName
    $extractDir = Join-Path $env:TEMP 'fastfetch-portable-extract'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $downloadedExe = Get-ChildItem -LiteralPath $extractDir -Filter 'fastfetch.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $downloadedExe) {
        throw 'missing executable...'
    }
    Copy-Item -LiteralPath $downloadedExe.FullName -Destination $fastfetchLocalPath -Force
    Unblock-File -LiteralPath $fastfetchLocalPath -ErrorAction SilentlyContinue
    Write-Host "Installed at: $fastfetchLocalPath"
}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null
if (Test-Path -LiteralPath $artSource) {
    Copy-Item -LiteralPath $artSource -Destination $logoDestination -Force
} else {
    Write-Host 'Injecting ASCII Art...'
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

$dungPath = Join-Path $binDir 'dung.cmd'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null

$dungCommand = @'
@echo off
setlocal
set "FF="
if exist "%USERPROFILE%\bin\fastfetch.exe" (
  set "FF=%USERPROFILE%\bin\fastfetch.exe"
  goto :run
)
for /f "delims=" %%F in ('where fastfetch 2^>nul') do set "FF=%%F" & goto :run
for /r "%LOCALAPPDATA%\Microsoft\WinGet\Packages" %%F in (fastfetch.exe) do set "FF=%%F" & goto :run
:run
if not defined FF (
  echo fetch no fue encontrado.
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
Write-Host "ASCII at: $logoDestination"
Write-Host "PREFIX: dung"

if (Test-Path -LiteralPath $dungPath) {
    Write-Host "`¿ALL IN?"
    & $dungPath
} else {
    Write-Host "`ALL IN! Execute: dung"
}
