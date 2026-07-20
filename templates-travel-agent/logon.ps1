<#
.SYNOPSIS
    Provisions a CloudLabs workshop VM with VS Code, required extensions, Git,
    Python, and Node.js, and registers a scheduled task that clones the
    workshop's Git repository the next time the participant logs on.

.DESCRIPTION
    Run this script ONCE, as Administrator, during VM provisioning
    (e.g. via a Custom Script Extension, or manually before handing the VM
    to a participant). It does NOT clone the repo itself — cloning happens
    via a logon scheduled task, so the repo is always freshly pulled the
    first time the participant actually logs in.

.NOTES
    - Set $GitRepoUrl below once you have the workshop's repo URL.
    - Designed for the CloudLabs "cloudlabs-windows-jumpvm" (Windows Server) image.
    - Idempotent: safe to re-run; skips steps that are already done.
#>

[CmdletBinding()]
param(
    # ---- SET THIS once you have the repo URL ----
    [string]$GitRepoUrl = "REPLACE_ME_WITH_GIT_REPO_URL",

    # Where the repo will be cloned to, on every participant's desktop area
    [string]$RepoDestination = "C:\Workshop\travel-multi-agent-workshop",

    # Local user(s) the logon task should trigger for. Use "Users" (built-in
    # group) to fire for anyone who logs on, or a specific username.
    [string]$LogonTaskUser = "Users",

    [string]$PythonVersion = "3.11.9",
    [string]$NodeVersion   = "lts"
)

$ErrorActionPreference = "Stop"
$logFile = "C:\Workshop\provisioning.log"
New-Item -ItemType Directory -Path "C:\Workshop" -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== Workshop VM provisioning started ==="

# -----------------------------------------------------------------------
# 1. Ensure Chocolatey is installed (used to install VS Code / Git / Python / Node)
# -----------------------------------------------------------------------
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:Path += ";$env:ProgramData\chocolatey\bin"
} else {
    Write-Log "Chocolatey already installed."
}

function Install-ChocoPackage {
    param([string]$PackageName, [string]$Args = "")
    Write-Log "Installing $PackageName via Chocolatey..."
    $cmd = "choco install $PackageName -y --no-progress $Args"
    Invoke-Expression $cmd
}

# -----------------------------------------------------------------------
# 2. Install VS Code
# -----------------------------------------------------------------------
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Install-ChocoPackage -PackageName "vscode"
    # Refresh PATH in this session so `code` is usable right away
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
                [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-Log "VS Code already installed."
}

# -----------------------------------------------------------------------
# 3. Install Git, Python, Node.js
# -----------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Install-ChocoPackage -PackageName "git"
} else {
    Write-Log "Git already installed."
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Install-ChocoPackage -PackageName "python" -Args "--version=$PythonVersion"
} else {
    Write-Log "Python already installed."
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    if ($NodeVersion -eq "lts") {
        Install-ChocoPackage -PackageName "nodejs-lts"
    } else {
        Install-ChocoPackage -PackageName "nodejs" -Args "--version=$NodeVersion"
    }
} else {
    Write-Log "Node.js already installed."
}

# Refresh PATH again after installs so `code`, `git`, `python`, `node` all resolve below
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path","User")

# -----------------------------------------------------------------------
# 4. Install required VS Code extensions
# -----------------------------------------------------------------------
$extensions = @(
    "ms-python.python",              # Python language support / debugging
    "ms-python.vscode-pylance",      # Python IntelliSense
    "ms-toolsai.jupyter",            # Handy for quick data/embedding checks
    "angular.ng-template",           # Angular template language service (frontend)
    "dbaeumer.vscode-eslint",        # Linting for the Angular frontend
    "esbenp.prettier-vscode",        # Formatting
    "ms-azuretools.vscode-azureresourcegroups", # Browse Azure resources from VS Code
    "humao.rest-client"              # Quick manual testing of the FastAPI / MCP endpoints
)

$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if ($null -eq $codeCmd) {
    Write-Log "WARNING: 'code' command not found on PATH after install. Extensions will need to be installed manually."
} else {
    foreach ($ext in $extensions) {
        Write-Log "Installing VS Code extension: $ext"
        try {
            & code --install-extension $ext --force | Out-Null
        } catch {
            Write-Log "WARNING: failed to install extension $ext : $_"
        }
    }
}

# -----------------------------------------------------------------------
# 5. Write the clone-on-logon helper script
#    (kept separate so the repo URL can be updated later without re-running
#    the whole provisioning script — just edit this file or re-run with -GitRepoUrl)
# -----------------------------------------------------------------------
$cloneScriptPath = "C:\Workshop\Clone-WorkshopRepo.ps1"

$cloneScriptContent = @"
# Auto-generated by Setup-WorkshopVM.ps1 — runs at user logon.
# Clones the workshop repo if it isn't already present, and pulls latest if it is.

`$ErrorActionPreference = 'Continue'
`$logFile = 'C:\Workshop\clone-on-logon.log'
function Write-CloneLog {
    param([string]`$Message)
    `$line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), `$Message
    Add-Content -Path `$logFile -Value `$line
}

`$repoUrl  = '$GitRepoUrl'
`$destPath = '$RepoDestination'

if (`$repoUrl -eq 'REPLACE_ME_WITH_GIT_REPO_URL') {
    Write-CloneLog 'Repo URL has not been configured yet. Skipping clone. Edit $cloneScriptPath and set `$repoUrl.'
    exit 0
}

# Make sure git is resolvable even in the fresh logon session's PATH
`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')

if (Test-Path (Join-Path `$destPath '.git')) {
    Write-CloneLog "Repo already present at `$destPath — pulling latest changes."
    Push-Location `$destPath
    git pull 2>&1 | ForEach-Object { Write-CloneLog `$_ }
    Pop-Location
} else {
    Write-CloneLog "Cloning `$repoUrl into `$destPath ..."
    New-Item -ItemType Directory -Path (Split-Path `$destPath -Parent) -Force | Out-Null
    git clone `$repoUrl `$destPath 2>&1 | ForEach-Object { Write-CloneLog `$_ }
    Write-CloneLog 'Clone complete.'
}

# Optionally open the workshop folder in VS Code once cloned
`$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if (`$codeCmd -and (Test-Path `$destPath)) {
    Start-Process -FilePath `$codeCmd.Source -ArgumentList `$destPath
}
"@

Set-Content -Path $cloneScriptPath -Value $cloneScriptContent -Encoding UTF8
Write-Log "Wrote logon clone script to $cloneScriptPath"

# -----------------------------------------------------------------------
# 6. Register the scheduled task to run the clone script at user logon
# -----------------------------------------------------------------------
$taskName = "WorkshopRepoClone"

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Log "Scheduled task '$taskName' already exists — removing and re-registering to apply latest settings."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$cloneScriptPath`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -GroupId $LogonTaskUser -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Clones/updates the workshop Git repo when a participant logs on." | Out-Null

Write-Log "Registered scheduled task '$taskName' to run at logon for group '$LogonTaskUser'."

# -----------------------------------------------------------------------
# 7. Done
# -----------------------------------------------------------------------
Write-Log "=== Workshop VM provisioning complete ==="
Write-Log "NOTE: Git repo URL is currently set to: $GitRepoUrl"
Write-Log "      Once you have the real URL, either re-run this script with -GitRepoUrl '<url>'"
Write-Log "      or edit `$repoUrl directly in $cloneScriptPath"
