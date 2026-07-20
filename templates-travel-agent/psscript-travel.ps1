Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,
    [string]
    $AzurePassword,
    [string]
    $AzureTenantID,
    [string]
    $AzureSubscriptionID,
    [string]
    $ODLID,
    [string]
    $DeploymentID,
    [string]
    $adminUsername,
    [string]
    $adminPassword,
    [string]
    $trainerUserName,
    [string]
    $trainerUserPassword
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# NOTE: Running on the Spektra cloudlabs-windows-jumpvm image.
# Az CLI, Az PowerShell, Edge/Choco and the CloudLabs agent are already baked
# into the image, so the install functions for those are not needed here.

Function CreateCredFile($AzureUserName, $AzurePassword, $AzureTenantID, $AzureSubscriptionID, $DeploymentID)
{
    New-Item -ItemType directory -Path C:\LabFiles -force

    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.txt","C:\LabFiles\AzureCreds.txt")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.ps1","C:\LabFiles\AzureCreds.ps1")

    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"

    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"

    Copy-Item "C:\LabFiles\AzureCreds.txt" -Destination "C:\Users\Public\Desktop"
}
CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID

Function updateVMShadowFile
{
    # Shadow.ps1 is baked into the image at C:\Users\Public\Documents
    $drivepath = "C:\Users\Public\Documents"
    (Get-Content -Path "$drivepath\Shadow.ps1") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$adminUsername"} | Set-Content -Path "$drivepath\Shadow.ps1"
    # Set the trainer account password
    net user $trainerUserName $trainerUserPassword
}
updateVMShadowFile

# ---- Downgrade Python: replace the image's 3.13 release-candidate with 3.11 ----
# The jumpvm image ships python/python3/python313 = 3.13.0-rc1. Remove those and
# install the stable 3.11 line so pip wheels (pandas/numpy/openai/azure) resolve.
foreach ($pkg in @("python", "python3", "python313")) {
    choco uninstall $pkg -y --skip-autouninstaller --no-progress 2>&1 | Out-Null
}
choco install python311 -y --no-progress --force

# Refresh PATH in the current session so subsequent steps use Python 3.11
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verify
& python --version

# =========================================================================
# ---- WORKSHOP ADDITIONS: VS Code, extensions, Node.js, repo logon task ----
# =========================================================================

New-Item -ItemType Directory -Path "C:\Workshop" -Force | Out-Null
$workshopLog = "C:\Workshop\provisioning.log"
function Write-WorkshopLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $workshopLog -Value $line
}

Write-WorkshopLog "Starting workshop dev-environment additions (VS Code, extensions, Node.js, logon task)."

# ---- Install VS Code (choco is already baked into the image) ----
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-WorkshopLog "Installing VS Code..."
    choco install vscode -y --no-progress
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-WorkshopLog "VS Code already installed."
}

# ---- Install Node.js LTS (needed for the Angular frontend: npm install / npm start) ----
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-WorkshopLog "Installing Node.js LTS..."
    choco install nodejs-lts -y --no-progress
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-WorkshopLog "Node.js already installed."
}

# ---- Install required VS Code extensions for this repo ----
# python/python3.11 -> backend + MCP server (FastAPI, LangGraph agents)
# angular/eslint/prettier -> frontend (Angular 19)
# azureresourcegroups -> browse Cosmos DB / Azure OpenAI from inside VS Code
# rest-client -> exercise the FastAPI (:8000/docs) and MCP (:8080/docs) endpoints
$extensions = @(
    "ms-python.python",
    "ms-python.vscode-pylance",
    "ms-toolsai.jupyter",
    "angular.ng-template",
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "ms-azuretools.vscode-azureresourcegroups",
    "humao.rest-client"
)

$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if ($null -eq $codeCmd) {
    Write-WorkshopLog "WARNING: 'code' command not found on PATH. Extensions were not installed."
} else {
    foreach ($ext in $extensions) {
        Write-WorkshopLog "Installing VS Code extension: $ext"
        try {
            & code --install-extension $ext --force | Out-Null
        } catch {
            Write-WorkshopLog "WARNING: failed to install extension $ext : $_"
        }
    }
}

# ---- Write the logon clone script ----
# PLACEHOLDER: set the workshop's Git repo URL here once available.
$GitRepoUrl       = "https://github.com/AzureCosmosDB/travel-multi-agent-workshop.git"
$RepoDestination  = "C:\Workshop\travel-multi-agent-workshop"
$cloneScriptPath  = "C:\Workshop\Clone-WorkshopRepo.ps1"

$cloneScriptContent = @"
# Auto-generated by the CloudLabs custom script extension — runs at user logon.
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

`$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if (`$codeCmd -and (Test-Path `$destPath)) {
    Start-Process -FilePath `$codeCmd.Source -ArgumentList `$destPath
}
"@

Set-Content -Path $cloneScriptPath -Value $cloneScriptContent -Encoding UTF8
Write-WorkshopLog "Wrote logon clone script to $cloneScriptPath (repo URL currently set to: $GitRepoUrl)"

# ---- Register the scheduled task that links to the clone script above, at user logon ----
$taskName = "WorkshopRepoClone"

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-WorkshopLog "Scheduled task '$taskName' already exists — removing and re-registering."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$cloneScriptPath`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -GroupId "Users" -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Clones/updates the workshop Git repo and opens it in VS Code when a participant logs on." | Out-Null

Write-WorkshopLog "Registered scheduled task '$taskName' (links to $cloneScriptPath), triggered AtLogOn for group 'Users'."
Write-WorkshopLog "Workshop dev-environment additions complete."

# =========================================================================
# ---- END WORKSHOP ADDITIONS ----
# =========================================================================

# ---- Lab payload: developer environment setup files ----
$desktopPath = "C:\Users\Public\Desktop"
if (-not (Test-Path $desktopPath)) {
    New-Item -ItemType Directory -Path $desktopPath -Force
}

Invoke-WebRequest -Uri "https://labfilespersonal.blob.core.windows.net/power/Setup-MyDevEnv.bat" -OutFile "$desktopPath\Setup-MyDevEnv.bat" -UseBasicParsing

Invoke-WebRequest -Uri "https://labfilespersonal.blob.core.windows.net/power/Setup-MyDevEnv.ps1" -OutFile "$desktopPath\Setup-MyDevEnv.ps1" -UseBasicParsing

$file = Get-Item "$desktopPath\Setup-MyDevEnv.ps1" -Force
$file.Attributes = "Hidden"

Function RunModernVmValidator
{
    cmd.exe --% /c sc create "Spektra CloudLabs VM Agent" BinPath=C:\CloudLabs\Validator\VMAgent\Spektra.CloudLabs.VMAgent.exe start= auto
    cmd.exe --% /c sc start "Spektra CloudLabs VM Agent"
}
RunModernVmValidator

Stop-Transcript

# Disable the image's bootstrap task so the script does not run again
Disable-ScheduledTask -TaskName "runuserdata"
Stop-ScheduledTask -TaskName "runuserdata"
