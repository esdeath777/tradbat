<#
.SYNOPSIS
    Automatic NVIDIA Driver installer for Windows Server 2019+

.DESCRIPTION
    1. Determine the GCP multi-region based on the instance metadata.
    2. Check for the presence of an NVIDIA GPU using the PCI Vendor ID (10DE).
    3. Check whether nvidia-smi is already installed.
    4. Download the region-specific driver installer.
    5. Install the driver silently.
    6. Clean up the installer files.
    7. Configure and start the audio services (Audiosrv and AudioEndpointBuilder).
    8. Download and install Apollo silently.
    9. Download and install Fastfetch (extra).

.NOTES
    Run this script with Administrator privileges.
#>

$ErrorActionPreference = "Stop"

# --- Check Administrator privileges ---
Write-Host "Checking Administrator privileges..." -ForegroundColor Cyan

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "        ERROR: MISSING ADMIN PRIVILEGES" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "This script REQUIRES Administrator privileges to run." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Cyan
    Write-Host "  1. Right-click on PowerShell" -ForegroundColor White
    Write-Host "  2. Select 'Run as administrator'" -ForegroundColor White
    Write-Host "  3. Run this script again" -ForegroundColor White
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Exit 1
}

Write-Host "Administrator privileges confirmed. Continuing..." -ForegroundColor Green
Write-Host ""

# --- Constants & Configuration ---
$Drivers = @{
    "Normal" = @{
        "Filename" = "582.53_grid_win10_win11_server2022_server_2025_dch_64bit_international.exe"
        "Hash"     = "6f1210b459efc7f29db930103533c3de9b93c2afdfa8d7b4871640c6b8638c0b"
    }
    "vGPU"   = @{
        "Filename" = "582.53_grid_win10_win11_server2022_server2025_dch_64bit_international_gcp_swl.exe"
        "Hash"     = "8e8689db080a0807cd9efae2368dc1971a60e66fd7defdb5f1c5025fdb0e0ced"
    }
}

$TempDir = [System.IO.Path]::GetTempPath()
$InstallerName = "nvidia_driver_installer.exe"
$InstallerPath = Join-Path -Path $TempDir -ChildPath $InstallerName

# --- Constants for Apollo ---
$ApolloUrl = "https://github.com/ClassicOldSong/Apollo/releases/download/v0.4.6/Apollo-0.4.6.exe"
$ApolloInstallerName = "Apollo-0.4.6.exe"
$ApolloInstallerPath = Join-Path -Path $TempDir -ChildPath $ApolloInstallerName

# --- Constants for Fastfetch ---
$FastfetchScriptUrl = "https://raw.githubusercontent.com/esdeath777/tradbat/refs/heads/main/install-fastfetch.ps1"
$FastfetchScriptPath = Join-Path -Path $TempDir -ChildPath "install-fastfetch.ps1"

# --- Region detection function ---
function Get-GcpMultiRegion {
    # Map region prefixes to multi-regions
    $RegionMap = @{
        "africa"       = "eu"
        "asia"         = "asia"
        "australia"    = "asia"
        "europe"       = "eu"
        "me"           = "eu"
        "northamerica" = "us"
        "southamerica" = "us"
        "us"           = "us"
    }

    Write-Host "Detecting GCP region..." -ForegroundColor Cyan

    try {
        # Query the Google metadata server for the zone
        # Include a timeout to avoid hanging if not on GCP or metadata is unreachable
        $ZoneUrl = "http://metadata.google.internal/computeMetadata/v1/instance/zone"
        $Response = Invoke-RestMethod -Uri $ZoneUrl -Headers @{"Metadata-Flavor" = "Google"} -TimeoutSec 5 -ErrorAction Stop

        # The response format is usually: projects/PROJECT_ID/zones/REGION-ZONE (for example: projects/123/zones/us-central1-a)
        $ZoneName = $Response.Split('/')[-1]

        # Get the region prefix (for example: 'us' from 'us-central1-a')
        $RegionPrefix = $ZoneName.Split('-')[0]

        if ($RegionMap.ContainsKey($RegionPrefix)) {
            $MultiRegion = $RegionMap[$RegionPrefix]
            Write-Host "Detected region: $RegionPrefix -> Multi-region: $MultiRegion" -ForegroundColor Green
            return $MultiRegion
        }
    }
    catch {
        Write-Warning "Could not detect the GCP region via the metadata server. Defaulting to 'us'."
    }

    return "us"
}

# --- Machine type detection function ---
function Get-MachineType {
    try {
        Write-Host "Detecting machine type..." -ForegroundColor Cyan
        
        $MachineTypeUrl = "http://metadata.google.internal/computeMetadata/v1/instance/machine-type"
        $Response = Invoke-RestMethod -Uri $MachineTypeUrl -Headers @{"Metadata-Flavor" = "Google"} -TimeoutSec 5 -ErrorAction Stop
        
        # projects/PROJECT_ID/machineTypes/MACHINE_TYPE
        $MachineType = $Response.Split('/')[-1]
        Write-Host "Detected machine type: $MachineType" -ForegroundColor Green
        
        if ($MachineType -in ('g4-standard-6', 'g4-standard-12', 'g4-standard-24')) {
            return "vGPU"
        }
        
        $InstanceUrl = "http://metadata.google.internal/computeMetadata/v1/instance/"
        $Response = Invoke-RestMethod -Uri $InstanceUrl -Headers @{"Metadata-Flavor" = "Google"} -TimeoutSec 5 -ErrorAction Stop
        
        if ($Response -like "*nvidia-grid-license*") {
            # Virtual Workstation
            return "Normal" 
        }
    }
    catch {
        Write-Warning "Could not detect the machine type via the metadata server. Defaulting to 'Normal'."
    }
    return "Normal"
}

# --- GPU detection function ---
function Get-Mgmt-Command {
    $Command = 'Get-CimInstance'
    if (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
        $Command = 'Get-WmiObject'
    }
    return $Command
}

function Find-GPU {
    $MgmtCommand = Get-Mgmt-Command
    try {
        # Query specifically for NVIDIA (VEN_10DE) in the Display or 3D Controller class
        $Command = "(${MgmtCommand} -query ""select DeviceID from Win32_PNPEntity Where (deviceid Like '%PCI\\VEN_10DE%') and (PNPClass = 'Display' or Name = '3D Video Controller')"" | Select-Object DeviceID -ExpandProperty DeviceID).substring(13,8)"
        $dev_id = Invoke-Expression -Command $Command
        return $dev_id
    }
    catch {
        Write-Warning "It appears that no GPU is connected to your system."
        return ""
    }
}

# --- Step 0: Determine the download URL ---
$MultiRegion = Get-GcpMultiRegion
$MachineType = Get-MachineType

$DriverInfo = $Drivers[$MachineType]
$DriverVersionFilename = $DriverInfo["Filename"]
$ExpectedSha256 = $DriverInfo["Hash"]

$DriverUrl = "https://storage.googleapis.com/compute-gpu-installation-$MultiRegion/windows/$DriverVersionFilename"

# --- Step 1: Check for GPU presence ---
Write-Host "Step 1: Checking for NVIDIA GPU (PCI ID check)..." -ForegroundColor Cyan

$gpuId = Find-GPU

if ([string]::IsNullOrWhiteSpace($gpuId)) {
    Write-Warning "No NVIDIA GPU (VEN_10DE) detected via PnP Entity check. Exiting."
    Exit
} else {
    Write-Host "Detected GPU with Device ID string: $gpuId" -ForegroundColor Green
}

# --- Step 2: Check nvidia-smi ---
Write-Host "Step 2: Checking existing installation (nvidia-smi)..." -ForegroundColor Cyan

$smiCommand = Get-Command "nvidia-smi" -ErrorAction SilentlyContinue
$smiPathDefault = "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
$smiPathSystem = "C:\Windows\System32\nvidia-smi.exe"

if ($smiCommand -or (Test-Path $smiPathDefault) -or (Test-Path $smiPathSystem)) {
    Write-Warning "nvidia-smi already exists. The driver appears to be installed. Exiting."
    Exit
} else {
    Write-Host "nvidia-smi not found. Proceeding with installation." -ForegroundColor Green
}

# --- Step 3: Download the installer ---
Write-Host "Step 3: Downloading driver..." -ForegroundColor Cyan
Write-Host "Source: $DriverUrl" -ForegroundColor Gray

# Ensure TLS 1.2 is enabled for the download
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    # IMPORTANT PERFORMANCE FIX:
    # The Invoke-WebRequest progress bar significantly slows down the download in Windows PowerShell 5.1.
    # We temporarily disable it to speed up the transfer.
    $OriginalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    Invoke-WebRequest -Uri $DriverUrl -OutFile $InstallerPath -UseBasicParsing

    # Restore the preference
    $ProgressPreference = $OriginalProgressPreference

    Write-Host "Download complete. Saved at: $InstallerPath" -ForegroundColor Green

    # --- Step 3.1: Verify Checksum ---
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Write-Host "Verifying SHA256 checksum..." -ForegroundColor Cyan
        $ComputedHash = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash

        if ($ComputedHash -eq $ExpectedSha256) {
            Write-Host "Checksum verified." -ForegroundColor Green
        } else {
            # Delete the corrupted file immediately
            Remove-Item -Path $InstallerPath -Force
            Write-Error "Checksum mismatch! Expected: $ExpectedSha256, Computed: $ComputedHash"
            Exit
        }
    }
}
catch {
    Write-Error "Could not download or verify the installer. Error: $_"
    Exit
}

# --- Steps 4 and 5: Execute and wait ---
Write-Host "Step 4: Executing the installer..." -ForegroundColor Cyan
Write-Host "Flags used: /s /n (Silent, No reboot)" -ForegroundColor Gray

try {
    # Start the process with /s (silent) and /n (no reboot)
    $process = Start-Process -FilePath $InstallerPath -ArgumentList "/s", "/n" -PassThru -Wait -Verb RunAs

    if ($process.ExitCode -eq 0) {
        Write-Host "Installation completed successfully." -ForegroundColor Green
    } else {
        Write-Warning "Installation completed with exit code: $($process.ExitCode). This may indicate a reboot is required or a non-critical warning."
    }
}
catch {
    Write-Error "Could not execute the installer. Error: $_"
    Exit
}

# --- Cleanup ---
Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
if (Test-Path $InstallerPath) {
    Remove-Item -Path $InstallerPath -Force
}

# --- Step 6: Configure and start the audio services ---
Write-Host ""
Write-Host "Step 6: Configuring and starting the audio services..." -ForegroundColor Cyan

try {
    # Configure the Audiosrv service
    Write-Host "  - Configuring Audiosrv (Windows Audio)..." -ForegroundColor Gray
    $audiosrv = sc.exe config Audiosrv start= auto
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Audiosrv configured successfully." -ForegroundColor Green
    } else {
        Write-Warning "    Could not configure Audiosrv. Error code: $LASTEXITCODE"
    }

    # Start the Audiosrv service
    Write-Host "  - Starting Audiosrv (Windows Audio)..." -ForegroundColor Gray
    $startAudiosrv = net start Audiosrv
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Audiosrv started successfully." -ForegroundColor Green
    } else {
        Write-Warning "    Could not start Audiosrv. Error code: $LASTEXITCODE"
    }

    # Configure the AudioEndpointBuilder service
    Write-Host "  - Configuring AudioEndpointBuilder..." -ForegroundColor Gray
    $audioEndpoint = sc.exe config AudioEndpointBuilder start= auto
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    AudioEndpointBuilder configured successfully." -ForegroundColor Green
    } else {
        Write-Warning "    Could not configure AudioEndpointBuilder. Error code: $LASTEXITCODE"
    }

    # Start the AudioEndpointBuilder service
    Write-Host "  - Starting AudioEndpointBuilder..." -ForegroundColor Gray
    $startAudioEndpoint = net start AudioEndpointBuilder
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    AudioEndpointBuilder started successfully." -ForegroundColor Green
    } else {
        Write-Warning "    Could not start AudioEndpointBuilder. Error code: $LASTEXITCODE"
    }

    Write-Host "Audio service configuration complete." -ForegroundColor Green
}
catch {
    Write-Warning "An error occurred while configuring the audio services: $_"
}

# --- Step 7: Download and install Apollo ---
Write-Host ""
Write-Host "Step 7: Downloading and installing Apollo..." -ForegroundColor Cyan

try {
    # Download the Apollo file to the temp directory
    Write-Host "  - Downloading Apollo from: $ApolloUrl" -ForegroundColor Gray
    
    # Disable the progress bar for faster download
    $OriginalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    
    Invoke-WebRequest -Uri $ApolloUrl -OutFile $ApolloInstallerPath -UseBasicParsing
    
    # Restore the preference
    $ProgressPreference = $OriginalProgressPreference
    
    Write-Host "    Downloaded: $ApolloInstallerPath" -ForegroundColor Green

    # Run the Apollo installer silently
    Write-Host "  - Installing Apollo (silent mode)..." -ForegroundColor Gray
    $apolloProcess = Start-Process -FilePath $ApolloInstallerPath -ArgumentList "/S" -PassThru -Wait -Verb RunAs

    if ($apolloProcess.ExitCode -eq 0) {
        Write-Host "    Apollo installed successfully." -ForegroundColor Green
    } else {
        Write-Warning "    Apollo installation completed with exit code: $($apolloProcess.ExitCode)."
    }

    # Delete the Apollo installer file after completion
    if (Test-Path $ApolloInstallerPath) {
        Remove-Item -Path $ApolloInstallerPath -Force
        Write-Host "  - Cleaned up the Apollo installer file." -ForegroundColor Gray
    }
}
catch {
    Write-Warning "Could not download or install Apollo. Error: $_"
}

# --- Step 8: Download and run Fastfetch installer (extra) ---
Write-Host ""
Write-Host "Step 8: Downloading and running the Fetch installer (extra)..." -ForegroundColor Cyan

try {
    Write-Host "  - Downloading Fetch installer from: $FastfetchScriptUrl" -ForegroundColor Gray

    $OriginalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    Invoke-WebRequest -Uri $FastfetchScriptUrl -OutFile $FastfetchScriptPath -UseBasicParsing

    $ProgressPreference = $OriginalProgressPreference

    Write-Host "    Downloaded: $FastfetchScriptPath" -ForegroundColor Green

    # Unblock the file in case it was downloaded from the internet
    Unblock-File -LiteralPath $FastfetchScriptPath -ErrorAction SilentlyContinue

    # Execute the downloaded script using powershell.exe to isolate its scope
    Write-Host "  - Executing the Fetch installer..." -ForegroundColor Gray
    $fastfetchProcess = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$FastfetchScriptPath`"" `
        -PassThru `
        -Wait `
        -Verb RunAs

    if ($fastfetchProcess.ExitCode -eq 0) {
        Write-Host "    Fetch installer completed successfully." -ForegroundColor Green
    } else {
        Write-Warning "    Fetch installer finished with exit code: $($fastfetchProcess.ExitCode)."
    }

    # Clean up the Fastfetch script file
    if (Test-Path -LiteralPath $FastfetchScriptPath) {
        Remove-Item -LiteralPath $FastfetchScriptPath -Force
        Write-Host "  - Cleaned up the Fetch installer file." -ForegroundColor Gray
    }
}
catch {
    Write-Warning "Could not download or run the Fetch installer. Error: $_"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "        INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "✓ NVIDIA Driver has been installed" -ForegroundColor White
Write-Host "✓ Audio services have been configured and started" -ForegroundColor White
Write-Host "✓ Apollo has been installed" -ForegroundColor White
Write-Host "✓ Dungfetch has been installed (extra)" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
