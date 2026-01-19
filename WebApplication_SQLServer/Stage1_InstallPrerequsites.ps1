<#
    setup-dev-env.ps1
    Automated setup of a web development environment using Chocolatey.
    Features:
    - Reboot awareness
    - Resume after reboot
    - Skips already-installed programs
    - Logs all actions
    Run as Administrator
#>

# -------------------------------------------------------
# Paths and Logging
# -------------------------------------------------------
$InstallerPath = "C:\DevInstallers"
$StateFile = "$InstallerPath\setup-state.json"
$LogFile = "$InstallerPath\setup-log.txt"
# Global reboot flag
$global:RebootNeeded = $false

if (!(Test-Path $InstallerPath)) { New-Item -ItemType Directory -Path $InstallerPath | Out-Null }

Start-Transcript -Path $LogFile -Append

function Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# -------------------------------------------------------
# Pre-flight Checks
# -------------------------------------------------------
# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Log "This script must be run as Administrator!" "Red"
    Stop-Transcript
    Write-Host "Please re-run this script in an elevated PowerShell session (Run as Administrator)." -ForegroundColor Red
    Write-Host "Press Enter to close this window..."
    Read-Host
    exit
}

# Check for Pending System Reboot
function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    foreach ($key in $keys) { if (Test-Path $key) { return $true } }
    return $false
}

if (Test-PendingReboot) {
    Log "System has a pending reboot from a previous installation." "Yellow"
    $state = @{ step = "start"; pendingReboot = $true }
    $state | ConvertTo-Json | Set-Content $StateFile
    Stop-Transcript
    Write-Host "Reboot is required. Please restart your computer before running this script again." -ForegroundColor Yellow
    Write-Host "Press Enter to close this window..."
    Read-Host
    exit
}

# -------------------------------------------------------
# State Tracking
# -------------------------------------------------------
if (Test-Path $StateFile) {
    $state = Get-Content $StateFile | ConvertFrom-Json
    Log "Resuming setup from last recorded step: $($state.step)" "Yellow"
} else {
    $state = @{ step = "start" }
}

function Save-State { param([string]$Step) $state.step = $Step; $state | ConvertTo-Json | Set-Content $StateFile }

# -------------------------------------------------------
# Chocolatey Install Helpers
# -------------------------------------------------------

function Test-VSProductInstalled {
 
    # Ensure vswhere is available
    $vsw = Get-Command vswhere -ErrorAction SilentlyContinue
    if (-not $vsw) {
        Log "vswhere not found in PATH. Cannot detect Visual Studio installations." "Red"
        return $false
    }

    try {
        # Query all Visual Studio installations (all versions, all editions)
        $results = & $vsw.Source `
            -products * `
            -format json 2>$null | ConvertFrom-Json

        if ($results -and $results.Count -gt 0) {
            foreach ($vs in $results) {
                $ver      = $vs.catalog.productDisplayVersion
                $edition  = $vs.productId -replace 'Microsoft.VisualStudio.Product.', ''
                $path     = $vs.installationPath

                Log "Visual Studio $ver $edition detected at: $path" "Green"
            }
            return $true
        } else {
            Log "No Visual Studio installations found." "Yellow"
            return $false
        }
    } catch {
        Log "Failed to query Visual Studio installation using vswhere: $_" "Red"
        return $false
    }
}

function Test-VSWorkload {
    param(
        [Parameter(Mandatory)]
        [string] $Workload
    )

    # Map winget-style names -> Visual Studio workload IDs
    $map = @{
        'visualstudio2026-workload-netweb'         = 'Microsoft.VisualStudio.Workload.NetWeb'
        'visualstudio2026-workload-azure'          = 'Microsoft.VisualStudio.Workload.Azure'
        'visualstudio2026-workload-node'           = 'Microsoft.VisualStudio.Workload.Node'
        'visualstudio2026-workload-netcrossplat'   = 'Microsoft.VisualStudio.Workload.NetCrossPlat'
        'visualstudio2026-workload-manageddesktop' = 'Microsoft.VisualStudio.Workload.ManagedDesktop'
        'visualstudio2026-workload-nativedesktop'  = 'Microsoft.VisualStudio.Workload.NativeDesktop'
        'visualstudio2026-workload-universal'      = 'Microsoft.VisualStudio.Workload.Universal'
        'visualstudio2026-workload-data'           = 'Microsoft.VisualStudio.Workload.Data'
        'visualstudio2026-workload-office'         = 'Microsoft.VisualStudio.Workload.Office'
    }

    if (-not $map.ContainsKey($Workload)) {
        Write-Warning "Unknown workload name: $Workload"
        return $false
    }

    $vsWorkloadId = $map[$Workload]

    # Locate vswhere
    $vsw = Get-Command vswhere -ErrorAction SilentlyContinue
    if (-not $vsw) {
        $fallback = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $fallback) { $vsw = [pscustomobject]@{ Source = $fallback } }
    }
    if (-not $vsw) {
        Write-Host "vswhere not found. Cannot check workloads." -ForegroundColor Red
        return $false
    }

    # Query via vswhere
    $args = @('-products','*','-requires',$vsWorkloadId,'-property','installationPath','-format','text')
    $result = & $vsw.Source @args 2>$null

    if ($result) {
        Write-Host "✅ Workload '$Workload' ($vsWorkloadId) is installed." -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ Workload '$Workload' ($vsWorkloadId) is NOT installed." -ForegroundColor Yellow
        return $false
    }
}

# Returns an array of instance objects actually present on the box.
# Each object: @{ Name = 'MSSQLSERVER' or 'SQLEXPRESS'... ; Version = '16.x' ; RootKey = 'HKLM:\...\MSSQL16.<Name>' ; ServiceName = 'MSSQL$<Name>' or 'MSSQLSERVER' }
function Get-SqlInstancesInstalled {
    $instances = @()
    $instKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    if (Test-Path $instKey) {
        Get-ItemProperty $instKey -ErrorAction SilentlyContinue | ForEach-Object {
            $_.PSObject.Properties | ForEach-Object {
                $name = $_.Name            # instance name (MSSQLSERVER or named)
                $instanceId = $_.Value     # e.g., MSSQL16.MSSQLSERVER
                $rootKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId"
                $ver = $null
                if (Test-Path $rootKey) {
                    $verKey = Join-Path $rootKey 'Setup'
                    if (Test-Path $verKey) {
                        $p = Get-ItemProperty $verKey -ErrorAction SilentlyContinue
                        $ver = $p.Version
                    }
                }
                # Service name rules: default instance = MSSQLSERVER; named = MSSQL$<name>
                $svc = if ($name -ieq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$name" }
                $instances += [pscustomobject]@{
                    Name        = $name
                    Version     = $ver
                    RootKey     = $rootKey
                    ServiceName = $svc
                }
            }
        }
    }
    return $instances
}

function Test-SqlEngineInstalled {
    # True if any SQL Server Database Engine instance exists and has its binaries
    $inst = Get-SqlInstancesInstalled
    if (-not $inst -or $inst.Count -eq 0) { return $false }

    foreach ($i in $inst) {
        # Consider it real if the service exists OR the expected MSSQL folder exists
        $svc = Get-Service -Name $i.ServiceName -ErrorAction SilentlyContinue
        $binPathKey = Join-Path $i.RootKey 'MSSQLServer'
        $hasFolder = $false
        if (Test-Path $binPathKey) {
            $props = Get-ItemProperty $binPathKey -ErrorAction SilentlyContinue
            if ($props -and $props.Path) { $hasFolder = Test-Path (Join-Path $props.Path 'Binn\sqlservr.exe') }
        }
        if ($svc -or $hasFolder) { return $true }
    }
    return $false
}

function Test-SSMSInstalled {
    param()

    # 1) Try vswhere (just in case SSMS is registered)
    $vsw = Get-Command vswhere -ErrorAction SilentlyContinue
    if ($vsw) {
        try {
            $out = & $vsw.Source -products * -version "[21.0,22.0)" -property installationPath 2>$null
            if ($out -and ($out.Trim() -ne '')) {
                return $true
            }
        } catch {
            # ignore errors
        }
    }

    # 2) Check typical executable paths
    $paths = @(
        "C:\Program Files (x86)\Microsoft SQL Server Management Studio 21\Common7\IDE\Ssms.exe",
        "C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe",
        "C:\Program Files\Microsoft SQL Server Management Studio 21\Common7\IDE\Ssms.exe",
        "C:\Program Files\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }

    # 3) Check Uninstall registry entries (64 bit + 32 bit)
    $hive  = [Microsoft.Win32.RegistryHive]::LocalMachine
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        try {
            $base  = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
            $key   = $base.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
            if ($key) {
                foreach ($name in $key.GetSubKeyNames()) {
                    $sk = $key.OpenSubKey($name)
                    $dn = $sk.GetValue('DisplayName')
                    if ($dn -and $dn -match 'SQL Server Management Studio') {
                        return $true
                    }
                }
            }
        } catch {
            # ignore
        }
    }

    return $false
}

# Install-ChocoPackage
# Purpose:
#   Install a Chocolatey package quietly, detect "already installed", map
#   Windows installer exit codes (0/3010/1641) to success, and report whether
#   a reboot is required — without triggering a reboot during the run.
#
# Returns:
#   [pscustomobject] with:
#     - Installed        : $true if this run installed something new
#     - AlreadyInstalled : $true if it was present beforehand (no-op)
#     - RebootRequired   : $true if the installer requested a reboot (3010/1641)
#     - ExitCode         : raw process exit code from Chocolatey
#
# Notes:
#   - Uses Start-Process to avoid spewing child installer output in the console.
#   - Adds '--no-progress' and '--limit-output' to keep Chocolatey quiet.
#   - You can redirect stdout/err to files for deep-dive logging (see commented lines).
# -----------------------------------------------------------------------------
function Install-ChocoPackage {
    param(
        [string]$PackageName,         # Chocolatey package id (e.g., 'git', 'visualstudio2022professional')
        [string]$PackageParams = "",  # Passed through to the *underlying* installer (e.g., Visual Studio setup.exe args)
        [string[]]$ExtraChocoArgs = @() # Optional extra args for Chocolatey (e.g., '--timeout', '--ignore-checksums')
    )

    # Normalize input
    $PackageName = $PackageName.Trim()

    # Resolve choco.exe path
    $chocoExe = "$env:ChocolateyInstall\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) {
        Log "Chocolatey executable not found at $chocoExe" "Red"
        return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$false; RebootRequired=$false; ExitCode=-1 }
    }

    $chocoThinksInstalled = $false
    try {
        $idOnly = & $chocoExe list --local-only --exact --id-only --limit-output --no-progress $PackageName 2>$null
        $chocoThinksInstalled = ($idOnly -and $idOnly.Trim() -ieq $PackageName)
    } catch { $chocoThinksInstalled = $false }

    #In some cases validate real install state, not just choco's record, which isn't reliabale.
    if ($PackageName -ieq 'sql-server-2022') {
        $sqlReal = Test-SqlEngineInstalled
        if ($chocoThinksInstalled -and -not $sqlReal) {
            Log "$PackageName recorded as installed in Chocolatey, but no SQL Server engine instances are present. Forcing reinstall via 'choco install --force'." "Yellow"
            $verb = 'install'
            $useForce = $true
        } elseif ($chocoThinksInstalled -and $sqlReal) {
            Log "$PackageName is already installed, skipping." "Green"
            return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$true; RebootRequired=$false; ExitCode=0 }
        } else {
            $verb = 'install'
            $useForce = $false
        }
    }
    elseif ($PackageName -ieq 'sql-server-management-studio') {
        $ssmsReal = Test-SSMSInstalled
        if ($chocoThinksInstalled -and -not $ssmsReal) {
            Log "$PackageName recorded as installed in Chocolatey, but SSMS binaries not found. Forcing reinstall via 'choco install --force'." "Yellow"
            $verb = 'install'
            $useForce = $true
        } elseif ($chocoThinksInstalled -and $ssmsReal) {
            Log "$PackageName is already installed, skipping." "Green"
            return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$true; RebootRequired=$false; ExitCode=0 }
        } else {
            $verb = 'install'
            $useForce = $false
        }
    }
    elseif ($PackageName -ieq 'visualstudio2026professional') {
        $vsReallyInstalled = Test-VSProductInstalled -Edition 'Professional'
        if ($chocoThinksInstalled -and -not $vsReallyInstalled) {
            Log "$PackageName recorded as installed in Chocolatey, but VS 2026 Professional not found. Forcing reinstall via 'choco install --force'." "Yellow"
            $verb = 'install'
            $useForce = $true
        } elseif ($chocoThinksInstalled -and $vsReallyInstalled) {
            Log "$PackageName is already installed, skipping." "Green"
            return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$true; RebootRequired=$false; ExitCode=0 }
        } else {
            $verb = 'install'
            $useForce = $false
        }
    }
    elseif ($PackageName -like '*-workload-*') {
        $vsWorkloadInstalled = (Test-VSWorkload -Workload $PackageName)
        if ($chocoThinksInstalled -or $vsWorkloadInstalled) {
            Log "$PackageName is already installed, skipping." "Green"
            return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$true; RebootRequired=$false; ExitCode=0 }
        } else {
            $verb = 'install'
            $useForce = $false
        }
    }
    else {
        # Non-VS packages (and VS workloads): normal choco logic
        if ($chocoThinksInstalled -and -not ($PackageName -imatch '^visualstudio2026-workload-')) {
            Log "$PackageName is already installed, skipping." "Green"
            return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$true; RebootRequired=$false; ExitCode=0 }
        } else {
            $verb = 'install'
            $useForce = $false
        }
    }

    Log "$($verb.Substring(0,1).ToUpper()+$verb.Substring(1))ing $PackageName..." "Cyan"

    # Build Chocolatey argument list:
    #   install <id> -y                  : non-interactive accept
    #   --no-progress --limit-output     : keep console quiet
    $chocoArgs = @($verb, $PackageName, "-y", "--no-progress", "--limit-output")
    if ($useForce) { $chocoArgs += '--force' }

    # If present, pass-through *package* parameters (these are NOT Chocolatey switches;
    # they are consumed by the underlying installer invoked by the choco package).
    if ($PackageParams) { $chocoArgs += @("--package-parameters", "`"$PackageParams`"") }

    # Allow callers to add extra choco switches if they want (timeouts, etc.)
    if ($ExtraChocoArgs) { $chocoArgs += $ExtraChocoArgs }

    # Run the install quietly. This avoids streaming verbose MSI/EXE logs to the console.
    # To capture full output, uncomment the Redirect lines and set file paths.
    # $outLog = Join-Path $InstallerPath "choco-$($PackageName)-out.log"
    # $errLog = Join-Path $InstallerPath "choco-$($PackageName)-err.log"
    $p = Start-Process -FilePath $chocoExe -ArgumentList $chocoArgs -Wait -PassThru -WindowStyle Hidden `
        # -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $exit = $p.ExitCode

    # Map common Windows installer exit codes:
    #   0    = success
    #   3010 = success, reboot required
    #   1641 = success, reboot initiated/required
    switch ($exit) {
        0     { Log "$PackageName installed successfully." "Green"
                return [pscustomobject]@{ Installed=$true; AlreadyInstalled=$false; RebootRequired=$false; ExitCode=$exit } }
        3010  { Log "$PackageName installed successfully (reboot required)." "Yellow"
                return [pscustomobject]@{ Installed=$true; AlreadyInstalled=$false; RebootRequired=$true; ExitCode=$exit } }
        1641  { Log "$PackageName installed successfully (reboot initiated/required)." "Yellow"
                return [pscustomobject]@{ Installed=$true; AlreadyInstalled=$false; RebootRequired=$true; ExitCode=$exit } }
        default {
            Log "$PackageName installation failed (exit code $exit). See C:\ProgramData\chocolatey\logs\chocolatey.log" "Red"
            return [pscustomobject]@{ Installed=$false; AlreadyInstalled=$false; RebootRequired=$false; ExitCode=$exit }
        }
    }
}


# -------------------------------------------------------
# Ensure Chocolatey is installed
# -------------------------------------------------------
if ($state.step -eq "start") {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Log "Installing Chocolatey..." "Cyan"

        # Force TLS 1.2 (required for newer HTTPS endpoints)
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

        try {
            # Set execution policy; ignore only the ExecutionPolicyOverride warning
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
            } catch {
                if ($_.FullyQualifiedErrorId -eq "ExecutionPolicyOverride,Microsoft.PowerShell.Commands.SetExecutionPolicyCommand") {
                    Log "ExecutionPolicy warning ignored - effective policy already allows scripts." "Yellow"
                } else {
                    throw
                }
            }

            $installer = 'https://community.chocolatey.org/install.ps1'

            # Use Invoke-RestMethod for better error handling
            $scriptContent = Invoke-RestMethod -Uri $installer -Method Get -ErrorAction Stop

            if (-not $scriptContent -or $scriptContent.Length -lt 1000) {
                throw "Chocolatey install script appears incomplete (possibly HTTP 503)."
            }

            Invoke-Expression $scriptContent

            if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
                throw "Chocolatey installation did not complete successfully."
            }

            Log "Chocolatey installed successfully." "Green"
        }
        catch {
            $msg = $_.Exception.Message
            Log ("Chocolatey installation failed: {0}" -f $msg) "Red"

            # Clean up any partial Chocolatey installation
            $chocoPath = "C:\ProgramData\Chocolatey"
            if (Test-Path $chocoPath) {
                try {
                    Log "Removing partial Chocolatey installation at $chocoPath ..." "Yellow"
                    Remove-Item -Recurse -Force -Path $chocoPath -ErrorAction Stop
                    Log "Partial Chocolatey folder removed." "Green"
                } catch {
                    Log "Failed to remove partial Chocolatey folder. Please delete manually: $chocoPath" "Red"
                }
            }

            if ($msg -match "503|temporarily unavailable|timeout|Unable to download") {
                Log "Chocolatey servers may be unavailable (HTTP 503). Please retry later or install manually from https://community.chocolatey.org" "Yellow"
            }

            Log "Abandoning setup." "Red"
            exit 1
        }
    } else {
        Log "Chocolatey already installed." "Green"
    }
    Save-State "core-tools"
}

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

# -------------------------------------------------------
# Core Tools
# -------------------------------------------------------
if ($state.step -eq "core-tools") {
    foreach ($pkg in @("vswhere","git","github-desktop","gh","vscode","nodejs","yarn","dotnet-8.0-sdk")) {

        # If installing Node, pass extra args to specify version
        $extraArgs = @()
        if ($pkg -ieq "nodejs") {
            $extraArgs += "--version=16.20.1"
        }

        $res = Install-ChocoPackage $pkg "" $extraArgs
        if ($res.RebootRequired) { $global:RebootNeeded = $true }
    }
    Log "Core tools complete." "Green"
    Save-State "visualstudio"
}

# -------------------------------------------------------
# Visual Studio 2026 Professional
# -------------------------------------------------------
if ($state.step -eq "visualstudio") {
    $vsInstallPath = 'C:\Program Files\Microsoft Visual Studio\2026\Professional'
    $vsParams = @(
        '--quiet',               # Fully silent install (no UI at all). Use instead of --passive to avoid the GUI.
        '--norestart',           # Do not reboot automatically (we’ll handle a single reboot at the end).
        '--includeRecommended',  # Include Microsoft’s recommended components for the workloads.
        #'--includeOptional',     # Include optional components in addition to recommended.
        '--wait',                # Block until the operation completes.
        '--nocache',             # Don’t keep package caches.
        #'--noUpdateInstaller',    # Prevent the installer from self-updating during this run (reduces chatter/feeds).
	'--productId', 'Microsoft.VisualStudio.Product.Professional',
	'--channelId', 'VisualStudio.17.Release',
        '--installPath', "`"`"$vsInstallPath`"`""   # target the existing instance explicitly
    ) -join ' '
    
    # Install base IDE
    $base = Install-ChocoPackage -PackageName 'visualstudio2026professional' -PackageParams $vsParams
    if ($base.RebootRequired) { $global:RebootNeeded = $true }

    # Check if VS is actually present after the attempt
    $vsOk = Test-VSProductInstalled -Edition 'Professional'

    if (-not $vsOk) {
        Log "Visual Studio 2026 Professional not detected after installation attempt. Skipping workload installs." "Yellow"
        Save-State "sqlserver"
    }
    else {
        $workloads = @(
            'visualstudio2026-workload-netweb',       # ASP.NET and web dev
            'visualstudio2026-workload-azure',        # Azure dev
            'visualstudio2026-workload-node',         # Node.js dev
            'visualstudio2026-workload-netcrossplat', # .NET cross-platform (MAUI/etc.)
            'visualstudio2026-workload-manageddesktop',  # .NET desktop dev (WPF/WinForms)
            'visualstudio2026-workload-nativedesktop',   # C++ desktop dev
            'visualstudio2026-workload-universal',    # UWP
            'visualstudio2026-workload-data',         # Data storage and processing
            'visualstudio2026-workload-office'        # Office/SharePoint dev
        )

        # Install VS and workloads in a loop
        $results = @{}
        foreach ($pkg in $workloads) {
            $res = Install-ChocoPackage -PackageName $pkg -PackageParams $vsParams
            $results[$pkg] = $res
            if ($res.RebootRequired) { $global:RebootNeeded = $true }
        }

        # Show summary
        ""
        "Install summary:"
        $results.GetEnumerator() | Sort-Object Key | ForEach-Object {
            $v = $_.Value
            $status = if     ($v.AlreadyInstalled) { 'Present' }
                      elseif ($v.Installed)        { 'Installed' }
                      else                          { 'Failed' }
            $reboot = if ($v.RebootRequired) { ', RebootReq' } else { '' }
            "{0,-45} : {1} (Exit {2}{3})" -f $_.Key, $status, $v.ExitCode, $reboot
        }
        ""
        Save-State "sqlserver"
    }
}

# -------------------------------------------------------
# SQL Server + SSMS
# -------------------------------------------------------
if ($state.step -eq "sqlserver") {

    $sqlReal = Test-SqlEngineInstalled
    if (-not $sqlReal) {
        Log "Installing SQL Server 2022 Developer + SSMS..." "Cyan"

        $BootstrapUrl  = "https://go.microsoft.com/fwlink/?linkid=2215158"
        $BootstrapPath = "C:\Scripts\SQL2022-SSEI-Dev.exe"
        $LogPath       = "C:\Scripts\SQL2022_Install.log"
        $mediaFolder   = "C:\Scripts"
        if (!(Test-Path "C:\Scripts")) { New-Item "C:\Scripts" -ItemType Directory | Out-Null }

        Log "Downloading bootstrapper..." "Cyan"
        if (Test-Path $BootstrapPath) {
            Log "Bootstrapper already exists at: $BootstrapPath"
        } else {
            try {
                Invoke-WebRequest -Uri $BootstrapUrl -OutFile $BootstrapPath -UseBasicParsing
                Unblock-File -Path $BootstrapPath
                Log "Download complete: $BootstrapPath" "Green"
            } catch {
                Log "ERROR: Failed to download bootstrapper. $_" "Red"
                return
            }
        }

        Log "Starting SQL Server media download (ISO)..." "Cyan"
        $Arguments = @(
          "/Action=Download",
          "/Quiet",
          "/Language=en-us",
          "/MediaType=ISO",
          "/MediaPath=`"$mediaFolder`""
        ) -join ' '

        # IMPORTANT: call the correct path and wait
        $proc = Start-Process -FilePath $BootstrapPath -ArgumentList $Arguments -PassThru -Wait

        # Wait for the ISO to appear (handles child process spawn)
        $iso = $null
        $deadline = (Get-Date).AddMinutes(30)
        do {
            Start-Sleep -Seconds 5
            $iso = Get-ChildItem -Path $mediaFolder -Filter *.iso -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
        } until ($iso -or (Get-Date) -gt $deadline)

        if (-not $iso) {
            Log "ERROR: No ISO found in $mediaFolder after waiting. Check network/proxy or try again." "Red"
            return
        }

        $isoPath = $iso.FullName
        Log "Downloaded SQL Server ISO: $isoPath" "Green"

        # Extract to C:\Scripts (root of media)
        try {
            $dest = "C:\Scripts"
            Mount-DiskImage $isoPath | Out-Null
            $d = (Get-Volume -DiskImage (Get-DiskImage $isoPath)).DriveLetter
            if (-not $d) { throw "Could not determine mounted drive letter." }

            $src = "$($d):\"
            robocopy $src $dest /E | Out-Null
            Dismount-DiskImage $isoPath
            Log "Extracted SQL Server ISO to $dest" "Green"
        } catch {
            try { Dismount-DiskImage $isoPath -ErrorAction SilentlyContinue } catch {}
            Log "ERROR extracting ISO: $_" "Red"
            return
        }

        #Uninstall any ODBC Drivers or OLE DB Drivers as these can cause problems with a SQL install (SQL installer will install new ones)
        $packages = Get-Package | Where-Object { $_.Name -match "ODBC Driver|OLE DB Driver" }
        foreach ($pkg in $packages) {
            Log "Uninstalling $($pkg.Name)..." "Yellow"
            try {
                Uninstall-Package -InputObject $pkg -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            } catch {
                Log "Failed to uninstall $($pkg.Name): $_" "Yellow"
            }
        }

        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & C:\Scripts\setup.exe /ConfigurationFile="C:\Scripts\SQL2022InstallConfiguration.ini" /QS /SQLSYSADMINACCOUNTS="$currentUser"

        Log "SQL Server installation complete"
    } else {
        Log "SQL Server already installed" "Green"
    }

    # Verify service status
    Log "Checking SQL Server service status..." "Cyan"
    try {
        $Service = Get-Service -Name "MSSQLSERVER" -ErrorAction Stop
        if ($Service.Status -eq "Running") {
            Log "SQL Server service is running." "Green"
            Log "Testing SA login..." "Green"
            try {
                sqlcmd -S localhost -U sa -P "NetHelpDesk99" -Q "SELECT @@VERSION;" | Out-Host
                Log "Connection test successful. SQL Server 2022 is ready to use!" "Green"
            } catch {
                Log "Could not connect with SA account. Please check credentials or authentication mode." "Yellow"
            }
        } else {
            Log "SQL Server service is installed but not running. Attempting to start..." "Cyan"
            Start-Service -Name "MSSQLSERVER"
            Log "SQL Server service started successfully." "Green"
        }
    } catch {
        Log "ERROR: Could not verify or start SQL Server service. $_" "Red"
    }

    # Install SSMS
    $resSsms = Install-ChocoPackage "sql-server-management-studio"
    if ($resSsms.RebootRequired) { $global:RebootNeeded = $true }

    # Mixed Mode & SA config (only if engine exists)
    if (Test-SqlEngineInstalled) {
        $inst = Get-SqlInstancesInstalled | Select-Object -First 1
        if ($inst) {
            $regPath = Join-Path $inst.RootKey 'MSSQLServer'
            if (Test-Path $regPath) {
                $loginMode = Get-ItemProperty -Path $regPath -Name "LoginMode" -ErrorAction SilentlyContinue
                if ($loginMode -and $loginMode.LoginMode -ne 2) {
                    try {
                        Set-ItemProperty -Path $regPath -Name "LoginMode" -Value 2
                        Log "Enabled SQL Server Mixed Mode Authentication in registry." "Green"
                        Restart-Service -Name $inst.ServiceName -Force -ErrorAction Stop
                        Log "SQL Server service restarted." "Green"
                        $saPassword = "NetHelpDesk99"
                        $sqlInstance = if ($inst.Name -ieq 'MSSQLSERVER') { 'localhost' } else { "localhost\$($inst.Name)" }
                        & sqlcmd -S "$sqlInstance" -E -Q "ALTER LOGIN sa ENABLE"
                        & sqlcmd -S "$sqlInstance" -E -Q "ALTER LOGIN sa WITH PASSWORD=N'$saPassword';"
                        Log "SA login enabled and password set." "Green"
                    } catch {
                        Log "Failed to configure SQL Server authentication: $_" "Red"
                    }
                } else {
                    Log "SQL Server already in Mixed Mode Authentication, skipping configuration." "Green"
                }
            }
        }
    } else {
        Log "SQL Server engine not detected after install attempt; skipping Mixed Mode configuration." "Yellow"
    }

    Save-State "optional-tools"
}

# -------------------------------------------------------
# Optional Tools
# -------------------------------------------------------
if ($state.step -eq "optional-tools") {
    Log "Installing optional tools..." "Cyan"
    foreach ($pkg in @("postman","7zip","googlechrome", "aws-vpn-client")) {
        $res = Install-ChocoPackage $pkg
        if ($res.RebootRequired) { $global:RebootNeeded = $true }
    }
    Save-State "verify"
}

# -------------------------------------------------------
# Verification
# -------------------------------------------------------
if ($state.step -eq "verify") {
    Log "Verifying installations..." "Cyan"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

    function Verify { param([string]$Command, [string]$DisplayName)
        try {
            $output = & $Command --version 2>$null
            if ($LASTEXITCODE -eq 0 -or $output) { Log "$DisplayName is installed and working." "Green" }
            else { Log "$DisplayName not detected." "Red" }
        } catch { Log "$DisplayName verification failed. Error: $_" "Red" }
    }

    Verify "git" "Git"
    Verify "node" "Node.js"
    Verify "npm" "npm"
    Verify "yarn" "Yarn"
    Verify "dotnet" ".NET SDK"
    Verify "code" "Visual Studio Code"

    $vsExe = "C:\Program Files\Microsoft Visual Studio\2026\Professional\Common7\IDE\devenv.exe"
    if (Test-Path $vsExe) { Log "Visual Studio 2026 Professional detected." "Green" } else { Log "Visual Studio not found." "Red" }

    if (Test-SqlEngineInstalled) { Log "SQL Server engine detected." "Green" }
    else                         { Log "SQL Server engine not found." "Red" }

    if (Test-SSMSInstalled)      { Log "SSMS detected." "Green" }
    else                         { Log "SSMS not found." "Red" }

    Log "All installations and verifications complete." "Green"
    if (Test-Path $StateFile) { Remove-Item $StateFile -Force }
}

# -------------------------------------------------------
# One-and-done reboot policy
# -------------------------------------------------------
if ($global:RebootNeeded) {
    Log "One or more installations require a reboot." "Yellow"
    $resp = Read-Host "Reboot now? (Y/N)"
    if ($resp -match '^[Yy]') {
        Log "Rebooting now..." "Yellow"
        Stop-Transcript
        Restart-Computer -Force
        exit
    } else {
        Log "Reboot skipped for now. Please reboot later to finalize installations." "Yellow"
    }
}

Stop-Transcript
