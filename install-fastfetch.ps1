$ErrorActionPreference = 'Stop'

$userProfile = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($userProfile)) {
    throw 'Could not detect the Windows user profile folder.'
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
    Write-Host 'WinGet is here...'
    $installed = winget list --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements 2>$null | Out-String
    if ($installed -notmatch 'Fastfetch') {
        Write-Host 'Installing Fastfetch with WinGet...'
        winget install --id Fastfetch-cli.Fastfetch --exact --source winget --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet failed with exit code $LASTEXITCODE."
        }
    } else {
        Write-Host 'Fastfetch is already installed. Moving on...'
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
        throw 'fastfetch.exe was not found inside the downloaded ZIP.'
    }
    Copy-Item -LiteralPath $downloadedExe.FullName -Destination $fastfetchLocalPath -Force
    Unblock-File -LiteralPath $fastfetchLocalPath -ErrorAction SilentlyContinue
    Write-Host "Fastfetch installed at: $fastfetchLocalPath"
}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null
Write-Host 'Injecting ASCII Art...'
if (Test-Path -LiteralPath $artSource) {
    Copy-Item -LiteralPath $artSource -Destination $logoDestination -Force
} else {
    Write-Host 'No external ASCII file found; using the embedded logo.'
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
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($logoDestination, $embeddedArt, $utf8NoBom)
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

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $config, $utf8NoBom)

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
  echo Fastfetch was not found.
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
if (-not (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $binDir.TrimEnd('\') })) {
    $env:Path = "$binDir;$env:Path"
}

Write-Host "Configuration created at: $configPath"
Write-Host "ASCII at: $logoDestination"
Write-Host 'PREFIX: dung'

if (Test-Path -LiteralPath $dungPath) {
    Write-Host "`nALL IN? Launching Dungfetch in a new terminal..."

    $windowsTerminal = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($windowsTerminal) {
        Start-Process -FilePath $windowsTerminal.Source -ArgumentList @(
            'new-tab',
            '--title',
            'Dungfetch',
            'cmd.exe',
            '/k',
            $dungPath
        )
    }
    else {
        Start-Process -FilePath 'cmd.exe' -ArgumentList @(
            '/k',
            "`"$dungPath`""
        )
    }
} else {
    Write-Host "`nRestart PowerShell, then run: dung"
}
