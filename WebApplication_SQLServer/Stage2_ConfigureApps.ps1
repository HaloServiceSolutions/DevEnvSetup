# GitHub login + repo setup + database download script
# ----------------------------------------------------
# 1) Ensures GitHub CLI (gh) is installed
# 2) Performs browser-based GitHub login
# 3) Clones required repositories (or pulls latest if already present)
# 4) Switches/creates "development" branch in nethelpdesk_web
# 5) Downloads OneClickV2ITSM.bak and restores to new database
# 6) Sets up Visual Studio/API
# 7) Sets up Visual Studio Code/UI
# 8) Runs update-sharedfiles and InstallModules.bat
# 9) Discards github changes
# 10) Increase header size limits

$ErrorActionPreference = 'Stop'

function Refresh-EnvPath {
    $chocoProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
    if (Test-Path $chocoProfile) {
        Import-Module $chocoProfile -ErrorAction SilentlyContinue
        if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
            refreshenv
            return
        }
    }
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user -join ';').TrimEnd(';')
}

function Get-GhPath {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "C:\ProgramData\chocolatey\bin\gh.exe",
        "C:\Program Files\GitHub CLI\gh.exe",
        "C:\Program Files (x86)\GitHub CLI\gh.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Test-GitRepo {
    param([string]$Path)
    return (Test-Path (Join-Path $Path ".git"))
}

function Get-RemoteUrl {
    param([string]$Path)
    try {
        $url = & git -C $Path remote get-url origin 2>$null
        return $url
    } catch { return $null }
}

function Sync-Repo {
    param([string]$Path)
    Write-Host "Fetching and fast-forwarding in $Path ..." -ForegroundColor Cyan
    & git -C $Path fetch --all --prune
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed in $Path" }
    & git -C $Path pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fast-forward pull not possible in $Path. Resolve locally if needed." -ForegroundColor Yellow
    }
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
                $svc = if ($name -ieq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL$name" }
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

function Set-VSStartupProjects {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SolutionPath,                 # e.g. C:\repo\MySolution.sln
        [Parameter(Mandatory=$true)]
        [string[]]$Projects,                   # names or UniqueNames; can be multiple
        [string]$VsProgId                      # optional: e.g. 'VisualStudio.DTE.17.0'
    )

    # Try VS2022 (17.0), then 2019 (16.0), etc., unless an explicit ProgID is passed
    $progIds = @()
    if ($VsProgId) { $progIds += $VsProgId } else { $progIds += "VisualStudio.DTE.17.0","VisualStudio.DTE.16.0","VisualStudio.DTE.15.0" }

    $dte = $null
    foreach ($pids in $progIds) {
        try {
            $t = [type]::GetTypeFromProgID($pids, $true)
            if ($t) { $dte = [Activator]::CreateInstance($t); if ($dte) { break } }
        } catch { }
    }
    if (-not $dte) { throw "Could not create Visual Studio DTE COM object. Is Visual Studio installed?" }

    try {
        $dte.MainWindow.Visible = $false
        $dte.UserControl = $false

        # Open solution (or activate if already open)
        if (-not $dte.Solution.IsOpen -or ($dte.Solution.FullName -ne $SolutionPath)) {
            $dte.Solution.Open($SolutionPath)
        }

        # Recursively enumerate projects (handles solution folders)
        $all = New-Object System.Collections.ArrayList
        function Add-ProjectsRecursively([object]$projItems) {
            if (-not $projItems) { return }
            foreach ($item in $projItems) {
                if ($item -and $item.SubProject) {
                    $sub = $item.SubProject
                    if ($sub.Kind -ne "{66A26720-8FB5-11D2-AA7E-00C04F688DDE}") {  # not a solution folder
                        [void]$all.Add($sub)
                    }
                    Add-ProjectsRecursively $sub.ProjectItems
                }
            }
        }

        foreach ($p in $dte.Solution.Projects) {
            if ($p -eq $null) { continue }
            if ($p.Kind -eq "{66A26720-8FB5-11D2-AA7E-00C04F688DDE}") {
                Add-ProjectsRecursively $p.ProjectItems
            } else {
                [void]$all.Add($p)
            }
        }

        # Resolve each requested project to its UniqueName (what DTE expects for StartupProjects)
        $resolved = @()
        foreach ($name in $Projects) {
            $match = $all | Where-Object {
                $_.UniqueName -ieq $name -or
                $_.Name       -ieq $name -or
                ($_.FullName -and ($_.FullName -like "*\$name" -or $_.FullName -like "*$name"))
            } | Select-Object -First 1

            if (-not $match) { throw "Project '$name' not found in solution '$SolutionPath'." }
            $resolved += $match.UniqueName
        }

        # Set startup projects (array = multi-startup)
        $dte.Solution.SolutionBuild.StartupProjects = $resolved

        # Persist per-user state
        $dte.Solution.SaveAs($SolutionPath)
    }
    finally {
        try { $dte.Quit() } catch { }
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($dte)
    }
}

function Invoke-GitQuiet {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepoPath,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        $proc = Start-Process -FilePath 'git' `
            -ArgumentList (@('-C', $RepoPath) + $Arguments) `
            -RedirectStandardOutput $tempFile `
            -RedirectStandardError  $tempFile `
            -NoNewWindow -Wait -PassThru

        $output = ''
        if (Test-Path $tempFile) {
            $output = Get-Content $tempFile -Raw
        }

        [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Output   = $output
        }
    }
    finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

# ---- Start ----
Refresh-EnvPath
$complete = $true
$gh = Get-GhPath

if (-not $gh) {
    Write-Host "GitHub CLI (gh.exe) not found on this system." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run 'Stage1-InstallPrerequisites.ps1' first to install required developer tools." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After that, re-run this script to continue GitHub authentication." -ForegroundColor Cyan
    Write-Host "Press Enter to exit..."
    Read-Host
    exit 1
}

# Check login status (quiet)
$oldEAP = $ErrorActionPreference
try {
    $ErrorActionPreference = 'SilentlyContinue'

    & $gh auth status --hostname github.com > $null 2>&1

    $loggedIn = ($LASTEXITCODE -eq 0)
}
finally {
    $ErrorActionPreference = $oldEAP
}

if ($loggedIn) {
    # Optional: show who’s logged in
    $user = (& $gh api user --jq ".login" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $user) {
        Write-Host "Already logged in to GitHub CLI as '$user'." -ForegroundColor Green
    } else {
        Write-Host "Already logged in to GitHub CLI." -ForegroundColor Green
    }
} else {
    Write-Host "Not logged in. Starting GitHub CLI login..." -ForegroundColor Cyan
    & $gh auth login --hostname github.com --web --scopes "repo,read:org,user:email"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "GitHub login failed or was cancelled." -ForegroundColor Red
        exit 1
    }
    Write-Host "GitHub login successful." -ForegroundColor Green
}

# Clone or update repositories
$repos = @(
    @{ Url = "https://github.com/HaloServiceSolutions/nethelpdesk_web.git"; Path = "C:\nethelpdesk_web" },
    @{ Url = "https://github.com/HaloServiceSolutions/nethelpdesk_lang.git"; Path = "C:\nethelpdesk_lang" }
)

foreach ($repo in $repos) {
    $url  = $repo.Url
    $path = $repo.Path

    if (-not (Test-Path $path)) {
        Write-Host "Cloning $url to $path ..." -ForegroundColor Cyan
        & git clone $url $path
        if ($LASTEXITCODE -ne 0) { throw "Failed to clone $url" }
        continue
    }

    if (-not (Test-GitRepo -Path $path)) {
        Write-Host "Path exists but is not a git repo: $path" -ForegroundColor Yellow
        Write-Host "Skipping update. (Move/rename the folder if you want a fresh clone.)" -ForegroundColor Yellow
        continue
    }

    $remote = Get-RemoteUrl -Path $path
    if ($remote -and ($remote -ne $url)) {
        Write-Host "WARNING: '$path' origin URL differs:" -ForegroundColor Yellow
        Write-Host "  Found: $remote" -ForegroundColor Yellow
        Write-Host "  Expect: $url" -ForegroundColor Yellow
    }

    Sync-Repo -Path $path
}

# Ensure 'development' branch in nethelpdesk_web
$webRepoPath = "C:\nethelpdesk_web"
if ((Test-Path $webRepoPath) -and (Test-GitRepo -Path $webRepoPath)) {
    Write-Host "Ensuring 'development' branch in nethelpdesk_web ..." -ForegroundColor Cyan

    # 1. fetch origin
    $fetch = Invoke-GitQuiet -RepoPath $webRepoPath -Arguments @('fetch', 'origin')
    if ($fetch.ExitCode -ne 0) {
        Write-Host $fetch.Output -ForegroundColor Red
        throw "git fetch failed in $webRepoPath"
    }

    # 2. does remote branch origin/development exist
    $remoteDev = Invoke-GitQuiet -RepoPath $webRepoPath -Arguments @('ls-remote', '--exit-code', '--heads', 'origin', 'development')
    $hasRemoteDev = ($remoteDev.ExitCode -eq 0)

    if ($hasRemoteDev) {
        # 3. does local development branch exist
        $localBranch = Invoke-GitQuiet -RepoPath $webRepoPath -Arguments @('branch', '--list', 'development')
        $hasLocalDev = -not [string]::IsNullOrWhiteSpace($localBranch.Output)

        if (-not $hasLocalDev) {
            Write-Host "Creating local 'development' branch tracking origin/development..." -ForegroundColor Cyan
            $coNew = Invoke-GitQuiet -RepoPath $webRepoPath -Arguments @('checkout', '-b', 'development', 'origin/development')
            if ($coNew.ExitCode -ne 0) {
                Write-Host $coNew.Output -ForegroundColor Yellow
                Write-Host "Failed to create and checkout 'development'." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Checking out existing 'development' branch..." -ForegroundColor Cyan
            $coDev = Invoke-GitQuiet -RepoPath $webRepoPath -Arguments @('checkout', 'development')
            if ($coDev.ExitCode -ne 0) {
                Write-Host $coDev.Output -ForegroundColor Yellow
                Write-Host "Failed to checkout 'development'." -ForegroundColor Yellow
            }
        }

        # 4. fast forward pull
        $pull = Invoke-GitQuiet -RepoPath $webRepoPath -Arguments @('pull', '--ff-only')
        if ($pull.ExitCode -ne 0) {
            Write-Host $pull.Output -ForegroundColor Yellow
            Write-Host "Fast forward not possible on 'development'." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Remote branch 'origin/development' not found. Staying on current branch." -ForegroundColor Yellow
    }
}
else {
    Write-Host "Directory missing or not a git repo: $webRepoPath" -ForegroundColor Red
    $complete = $false
}

# Download .bak file if not already present
$backupDir  = "C:\DatabaseBackups"
$backupUrl  = "https://s3.eu-west-2.amazonaws.com/s3.nethelpdesk.com/BlankTrialDatabases/OneClickV2ITSM.bak"
$backupFile = Join-Path $backupDir "OneClickV2ITSM.bak"

if (-not (Test-Path $backupDir)) {
    Write-Host "Creating backup directory: $backupDir" -ForegroundColor Cyan
    New-Item -Path $backupDir -ItemType Directory | Out-Null
}

if (Test-Path $backupFile) {
    Write-Host "Backup already present, skipping download: $backupFile" -ForegroundColor Yellow
} else {
    Write-Host "Downloading database backup file..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $backupUrl -OutFile $backupFile -UseBasicParsing
    if (Test-Path $backupFile) {
        Write-Host "Database backup downloaded successfully to $backupFile" -ForegroundColor Green
    } else {
        Write-Host "Failed to download database backup file." -ForegroundColor Red
    }
}

# ==== Restore DB: OneClickV2ITSM.bak -> DevelopmentDB ====
# Only try to restore DB if SQL Server is installed
if (Test-SqlEngineInstalled) {
    # Prefer dynamic instance resolution instead of hardcoding MSSQL16.MSSQLSERVER
    $inst = Get-SqlInstancesInstalled | Select-Object -First 1
    if ($inst) {
        $regPath = Join-Path $inst.RootKey 'MSSQLServer'
        if (Test-Path $regPath) {
            $sqlInstance = if ($inst.Name -ieq 'MSSQLSERVER') { 'localhost' } else { "localhost\$($inst.Name)" }
            $databaseName = "DevelopmentDB"

            if (-not (Test-Path $backupFile)) {
                Write-Host "Backup file not found: $backupFile - skipping restore." -ForegroundColor Yellow
                return
            }
            $bakPath = $backupFile

            # Ensure SqlServer module (for Invoke-Sqlcmd)
            if (-not (Get-Module -ListAvailable -Name SqlServer)) {
                try {
                    Install-Module -Name SqlServer -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck -Confirm:$false -ErrorAction Stop
                } catch {
                    throw "SqlServer PowerShell module is required. Install failed: $($_.Exception.Message)"
                }
            }
            Import-Module SqlServer -ErrorAction Stop

            # Get default data/log directories (with robust fallbacks)
            $paths = Invoke-Sqlcmd -TrustServerCertificate -ServerInstance $sqlInstance -Database master -Query "SELECT DataPath = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(4000)), LogPath  = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS nvarchar(4000));"
            $pathsRow = $paths | Select-Object -First 1

            if (-not $pathsRow -or [string]::IsNullOrWhiteSpace($pathsRow.DataPath) -or [string]::IsNullOrWhiteSpace($pathsRow.LogPath)) {
                $qMasterLocs = @(
                    "SELECT",
                    "  DataPath = REVERSE(SUBSTRING(REVERSE(physical_name), CHARINDEX('\', REVERSE(physical_name)), 4000))",
                    "FROM sys.master_files",
                    "WHERE database_id = 1 AND file_id IN (1,2)",
                    "ORDER BY file_id;"
                ) -join "`n"
                $masterLocs = Invoke-Sqlcmd -TrustServerCertificate ServerInstance $sqlInstance -Database master -Query $qMasterLocs
                $dataBase = ($masterLocs | Select-Object -First 1).DataPath
                $logBase  = ($masterLocs | Select-Object -Last 1).DataPath
                $dataBase = if ($dataBase) { $dataBase } else { 'C:\Program Files\Microsoft SQL Server\MSSQL\Data\' }
                $logBase  = if ($logBase)  { $logBase }  else { $dataBase }
            } else {
                $dataBase = $pathsRow.DataPath
                $logBase  = $pathsRow.LogPath
            }

            # Read logical file names from the .bak
            Write-Host "Reading from the database backup"
            $filelist = Invoke-Sqlcmd -TrustServerCertificate -ServerInstance $sqlInstance -Database master -Query "RESTORE FILELISTONLY FROM DISK = N'$bakPath';"
            if (-not $filelist) { throw "Could not read FILELIST from $bakPath" }

            $dataLogical = ($filelist | Where-Object { $_.Type -eq 'D' } | Select-Object -First 1).LogicalName
            $logLogical  = ($filelist | Where-Object { $_.Type -eq 'L' } | Select-Object -First 1).LogicalName
            if (-not $dataLogical -or -not $logLogical) { throw "Could not determine logical file names from .bak." }

            # Target physical paths
            $dataFile = Join-Path $dataBase "$databaseName.mdf"
            $logFile  = Join-Path $logBase  "$databaseName_log.ldf"

            # Make sure directories exist
            New-Item -ItemType Directory -Path $dataBase -Force | Out-Null
            New-Item -ItemType Directory -Path $logBase  -Force | Out-Null

            # Drop existing DB (if present) and restore
            # Check if the database already exists
            $query = "SELECT DB_ID(N'$databaseName') AS DbId;"
            $result = Invoke-Sqlcmd -ServerInstance $sqlInstance -Database master -Query $query -TrustServerCertificate
            $skipDBRestore = $false
            if ($result.DbId) {
                Write-Host "Database '$databaseName' already exists." -ForegroundColor Yellow

                # Prompt the user
                $response = Read-Host "Do you want to replace it? (Y/N)"
                if ($response -notin @('Y', 'y', 'Yes', 'yes')) {
                    Write-Host "Skipping restore for '$databaseName'." -ForegroundColor Cyan
                    $skipDBRestore = $true
                } else {
                    $response = Read-Host "Are you sure? (Y/N)"
                    if ($response -notin @('Y', 'y', 'Yes', 'yes')) {
                        Write-Host "Skipping restore for '$databaseName'." -ForegroundColor Cyan
                        $skipDBRestore = $true
                    }
                }
            }
            else {
                Write-Host "Database '$databaseName' does not exist - proceeding with restore." -ForegroundColor Green
            }

            if ($skipDBRestore -eq $false)
            {
                # Build your restore SQL as before
                $restoreTsql = (@(
                    "IF DB_ID(N'{0}') IS NOT NULL",
                    "BEGIN",
                    "    ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;",
                    "    DROP DATABASE [{0}];",
                    "END;",
                    "",
                    "RESTORE DATABASE [{0}]",
                    "FROM DISK = N'{1}'",
                    "WITH MOVE N'{2}' TO N'{3}',",
                    "     MOVE N'{4}' TO N'{5}',",
                    "     REPLACE,",
                    "     RECOVERY;"
                ) -join "`n") -f $databaseName, $bakPath, $dataLogical, $dataFile, $logLogical, $logFile

                Write-Host "Restoring database '$databaseName' from '$bakPath'..." -ForegroundColor Cyan
                Invoke-Sqlcmd -TrustServerCertificate -ServerInstance $sqlInstance -Database master -Query $restoreTsql -QueryTimeout 0
                Write-Host "Database restored as '$databaseName'." -ForegroundColor Green

                # ==== Run post-restore SQL script on DevelopmentDB ====
                $sqlFile = "C:\nethelpdesk_web\nethelpdesk_api\switchinstance.sql"
                if (Test-Path $sqlFile) {
                    Write-Host "Running $sqlFile against $databaseName ..." -ForegroundColor Cyan
                    Invoke-Sqlcmd -TrustServerCertificate -ServerInstance $sqlInstance -Database $databaseName -InputFile $sqlFile -QueryTimeout 0
                    Write-Host "Post-restore script completed." -ForegroundColor Green
                } else {
                    Write-Host "SQL script not found: $sqlFile" -ForegroundColor Red
                    $complete = $false
                }
            }
        }
    }
} else {
    Write-Host "SQL Server engine not detected" -ForegroundColor Yellow
    Write-Host "Please run 'Stage1-InstallPrerequisites.ps1' first to install required developer tools." -ForegroundColor Yellow
    $complete = $false
}

# ==== Set up Visual Studio/API ====
Write-Host "Setting up Visual Studio/API" -ForegroundColor Yellow
# Set VS starup projects
try {
    Set-VSStartupProjects -SolutionPath "C:\nethelpdesk_web\nethelpdesk_api\nethelpdesk_api.sln" `
                          -Projects @("NetHelpDesk.API", "NetHelpDesk.Auth")
}
catch {
    Write-Host "Failed Visual Studio startup project setup, but continuing anyway: $_" -ForegroundColor Red
    $complete = $false
}

# Create API and Auth appsettings.development.json
$apiPath = "C:\nethelpdesk_web\nethelpdesk_api\NetHelpDesk.API"
$authPAth = "C:\nethelpdesk_web\nethelpdesk_api\NetHelpDesk.Auth"
$APIAppSettings = Join-Path $apiPath "appsettings.development.json"
$authAppSettings = Join-Path $authPath "appsettings.development.json"
$hostname = $env:COMPUTERNAME

if (-not (Test-Path $apiPath)) {
    Write-Host "API folder not found: $apiPath" -ForegroundColor Red
    $complete = $false
} else {
    $apiObj = @{
        authentication_root = "http://localhost:49490"
        ConnectionStrings   = @{ DefaultConnection = "Server=$hostname;Database=DevelopmentDB;User ID=sa;Password=NetHelpDesk99;Trusted_Connection=False;MultipleActiveResultSets=true" }
        Logging             = @{ IncludeScopes = $false; LogLevel = @{ Default = "Warning" } }
        UseReferenceTokens  = $true
        ProcessEvents       = $false
        ProcessAutomations  = $false
        ProcessOutgoing     = $false
        ProcessSchedules    = $false
    }
    $apijson = $apiObj | ConvertTo-Json -Depth 5

    Set-Content -Path $apiAppSettings -Value $apijson -Encoding UTF8
    Write-Host "Created appsettings.development.json at $apiAppSettings" -ForegroundColor Green
}



if (-not (Test-Path $authPAth)) {
    Write-Host "API folder not found: $authPAth" -ForegroundColor Red
    $complete = $false
} else {
    $authObj = @{
        app_root          = "http://localhost:3000"
        ConnectionStrings = @{ DefaultConnection = "Server=$hostname;Database=DevelopmentDB;User ID=sa;Password=NetHelpDesk99;Trusted_Connection=False;MultipleActiveResultSets=true" }
        Logging           = @{ IncludeScopes = $false; LogLevel = @{ Default = "Warning" } }
        UseReferenceTokens  = $true
    }
    $authjson = $authObj | ConvertTo-Json -Depth 5

    Set-Content -Path $authAppSettings -Value $authjson -Encoding UTF8
    Write-Host "Created appsettings.development.json at $authAppSettings" -ForegroundColor Green
}
Write-Host "Visual Studio/API setup complete!" -ForegroundColor Green

# ==== Set up Visual Studio Code/UI ====
Write-Host "Setting up Visual Studio Code/UI" -ForegroundColor Yellow

$codeCmd = Get-Command code -ErrorAction SilentlyContinue

# Install VS Code extensions
if ($codeCmd) {
    Write-Host "Checking VS Code extensions..." -ForegroundColor Cyan

    # Extensions we want
    $extensionsWanted = @(
        'alefragnani.Bookmarks',
        'eamodio.gitlens'
    )

    # Get currently installed extensions
    $installedExtensions = & $codeCmd.Source --list-extensions

    foreach ($ext in $extensionsWanted) {
        if ($installedExtensions -contains $ext) {
            Write-Host "  - $ext already installed. Skipping." -ForegroundColor DarkGray
        } else {
            Write-Host "  - Installing $ext..." -ForegroundColor Cyan
            & $codeCmd.Source --install-extension $ext --force *> $null
        }
    }
} else {
    Write-Warning "VS Code 'code' command not found on PATH. Skipping extension installation."
    $complete = $false
}

# Create appsettings.development.json
$uiPublicPath      = Join-Path $webRepoPath 'nethelpdesk_ui\public'
$portalPublicPath  = Join-Path $webRepoPath 'nethelpdesk_portal\public'

$appsettingsObj = @{
        api_root            = "http://localhost:49489"
        authentication_root = "http://localhost:49490"
    }
$appsettingsJson = $appsettingsObj | ConvertTo-Json -Depth 5

Write-Host "Creating appsettings.development.json files..." -ForegroundColor Cyan

New-Item -ItemType Directory -Path $uiPublicPath -Force | Out-Null
New-Item -ItemType Directory -Path $portalPublicPath -Force | Out-Null

$uiDevSettingsPath     = Join-Path $uiPublicPath 'appsettings.development.json'
$portalDevSettingsPath = Join-Path $portalPublicPath 'appsettings.development.json'

Set-Content -Path $uiDevSettingsPath -Value $appsettingsJson -Encoding UTF8 -NoNewline
Set-Content -Path $portalDevSettingsPath -Value $appsettingsJson -Encoding UTF8 -NoNewline

# Run update-sharedfiles

$portalRootPath = Join-Path $webRepoPath 'nethelpdesk_portal'
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue

if ($npmCmd -and (Test-Path $portalRootPath)) {
    Write-Host "Running 'npm run update-sharedfiles' in $portalRootPath..." -ForegroundColor Cyan
    Push-Location $portalRootPath

    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    try {
        npm run update_sharedfiles > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "update_sharedfiles exited with code $LASTEXITCODE"
            $complete = $false
        }
    } finally {
        $ErrorActionPreference = $oldEAP
    }
} else {
    if (-not $npmCmd) {
        Write-Warning "npm not found on PATH. Skipping 'npm run update-sharedfiles'."
        $complete = $false
    }
    if (-not (Test-Path $portalRootPath)) {
        Write-Warning "Portal path not found: $portalRootPath"
        $complete = $false
    }
}

# Run InstallModules.bat

$installModulesBat = Join-Path $webRepoPath 'InstallModules.bat'
Write-Host "Running InstallModules.bat" -ForegroundColor Cyan

if (Test-Path $installModulesBat) {
    Push-Location $webRepoPath
    try {
        & $installModulesBat > $null 2>&1
    } catch {
        Write-Host "InstallModules Warning occurred." -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "InstallModules.bat completed with exit code $LASTEXITCODE"
        $complete = $false
    }
} else {
    Write-Warning "InstallModules.bat not found at $installModulesBat"
    $complete = $false
}

# Discard yarn.lock changes in Git

$gitCmd = Get-Command git -ErrorAction SilentlyContinue

if ($gitCmd -and (Test-Path $webRepoPath)) {
    Write-Host "Discarding Git changes in $webRepoPath..." -ForegroundColor Yellow
    Push-Location $webRepoPath
    try {
        git reset --hard HEAD
        git clean -fd
    } finally {
        Pop-Location
    }
} else {
    if (-not $gitCmd) {
        Write-Warning "git not found on PATH. Skipping Git cleanup."
        $complete = $false
    }
    if (-not (Test-Path $webRepoPath)) {
        Write-Warning "Web root not found: $webRepoPath"
        $complete = $false
    }
}

# Increase header size limits
# Define registry path and desired values
$regPath = 'HKLM:\System\CurrentControlSet\Services\HTTP\Parameters'
$desiredValues = @{
    MaxFieldLength  = 65534
    MaxRequestBytes = 65534
}

# Track if any changes were made
$changesMade = $false

# Ensure registry path exists
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Check and update each value
foreach ($name in $desiredValues.Keys) {
    $currentValue = (Get-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue).$name
    if ($currentValue -ne $desiredValues[$name]) {
        if ($null -eq $currentValue) {
            New-ItemProperty -Path $regPath -Name $name -Value $desiredValues[$name] -PropertyType DWord
        } else {
            Set-ItemProperty -Path $regPath -Name $name -Value $desiredValues[$name]
        }
        Write-Host "$name updated from '$currentValue' to '$($desiredValues[$name])'"
        $changesMade = $true
    } else {
        Write-Host "$name is already set to $currentValue"
    }
}

# Prompt for reboot only if changes were made
if ($changesMade) {
    Write-Warning "Registry values updated. A system reboot is required for changes to take effect."
    $response = Read-Host "Do you want to reboot now? (Y/N)"
    if ($response -match '^[Yy]$') {
        Restart-Computer -Force
    } else {
        Write-Host "Please reboot manually later."
    }
} else {
    Write-Host "No changes were needed. No reboot required."
}

Write-Host "Visual Studio Code/UI setup complete!" -ForegroundColor Green

# All done
if ($complete) {
    Write-Host "All tasks completed successfully. Development environment is ready. Get to work!" -ForegroundColor Green
} else {
    Write-Host "Not all tasks were completed successfully. Please resolve issues and/or re-run the script." -ForegroundColor Red
}

