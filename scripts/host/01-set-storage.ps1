<#
=============================================================================
 01-set-storage.ps1   -   runs on your WINDOWS laptop (host), once
=============================================================================
 Moves where the lab keeps its big files, using VM_STORAGE_DIR from lab.env:

     <VM_STORAGE_DIR>\VirtualBox   VM disks   (VirtualBox "default machine folder")
     <VM_STORAGE_DIR>\vagrant.d    downloaded Ubuntu images (VAGRANT_HOME)

 Run it ONCE per laptop, BEFORE the first 'vagrant up':

     powershell -ExecutionPolicy Bypass -File .\scripts\host\01-set-storage.ps1

 Afterwards fully close and reopen VS Code / terminals so VAGRANT_HOME is seen.

 Notes
  - If VM_STORAGE_DIR is empty in lab.env, this script does nothing.
  - VMs that ALREADY exist stay where they are. To move them: 'vagrant destroy -f'
    first (the lab is disposable), then run this script, then 'vagrant up'.
  - Changes are machine/user-wide settings (VirtualBox preference + user
    environment variable), not project settings, so they persist.
=============================================================================
#>
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# --- Read lab.env ----------------------------------------------------------
$cfg = @{}
Get-Content (Join-Path $root 'lab.env') | ForEach-Object {
    $l = $_.Trim()
    if ($l -and -not $l.StartsWith('#') -and $l.Contains('=')) {
        $k, $v = $l.Split('=', 2)
        $cfg[$k.Trim()] = ($v -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
    }
}
$base = $cfg['VM_STORAGE_DIR']
if (-not $base) {
    Write-Host "VM_STORAGE_DIR is empty in lab.env - keeping VirtualBox/Vagrant defaults. Nothing to do." -ForegroundColor Yellow
    exit 0
}

# --- Sanity checks ---------------------------------------------------------
if ($base -notmatch '^[A-Za-z]:\\') { throw "VM_STORAGE_DIR must be an absolute Windows path like D:\VMs (got '$base')." }
$letter = $base.Substring(0, 1).ToUpper()
if (-not (Test-Path "${letter}:\")) { throw "Drive ${letter}: does not exist." }

# Fixed internal disk only (DriveType 3). USB/network drives hurt etcd and can disconnect.
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${letter}:'"
if ($disk.DriveType -ne 3) { throw "Drive ${letter}: is not a fixed internal disk (DriveType=$($disk.DriveType)). Choose an internal drive." }

if ($base -match 'OneDrive|Dropbox|Google ?Drive|iCloud') { throw "'$base' looks cloud-synced. Sync tools lock large VM disks. Choose a plain local folder." }

# Warn (not fail) if the physical disk is a spinning hard drive.
try {
    $part = Get-Partition -DriveLetter $letter -ErrorAction Stop
    $pd   = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $part.DiskNumber }
    if ($pd.MediaType -eq 'HDD') { Write-Host "WARN: ${letter}: is a hard disk (HDD). Expect slow boots and an unstable control plane; prefer an SSD." -ForegroundColor Yellow }
} catch { Write-Host "Note: could not detect drive type for ${letter}: (continuing)." -ForegroundColor DarkYellow }

$freeGB = [math]::Round($disk.FreeSpace / 1GB)
$needGB = 20 * ([int]$cfg['WORKER_COUNT'] + 1)
if ($freeGB -lt $needGB) { Write-Host "WARN: only $freeGB GB free on ${letter}: (plan for ~$needGB GB)." -ForegroundColor Yellow }

# --- Locate VBoxManage -----------------------------------------------------
$vbox = (Get-Command VBoxManage -ErrorAction SilentlyContinue).Source
if (-not $vbox -and (Test-Path 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe')) { $vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' }
if (-not $vbox) { throw "VirtualBox not found. Install it first (docs/PREREQUISITES.md)." }

# Existing lab VMs are not moved by this script - tell the user.
$existing = & $vbox list vms | Select-String ([regex]::Escape($cfg['LAB_NAME']) + '-k8s-')
if ($existing) {
    Write-Host "WARN: lab VMs already exist and will stay in their current folder:" -ForegroundColor Yellow
    $existing | ForEach-Object { Write-Host "      $_" }
    Write-Host "      To relocate them: vagrant destroy -f, re-run this script, then vagrant up." -ForegroundColor Yellow
}

# --- Apply -----------------------------------------------------------------
$vmDir = Join-Path $base 'VirtualBox'
$vhDir = Join-Path $base 'vagrant.d'
New-Item -ItemType Directory -Force -Path $vmDir, $vhDir | Out-Null

& $vbox setproperty machinefolder $vmDir
if ($LASTEXITCODE -ne 0) { throw "VBoxManage setproperty failed." }

# User-level environment variable: persists for new terminals / VS Code restarts.
[Environment]::SetEnvironmentVariable('VAGRANT_HOME', $vhDir, 'User')
$env:VAGRANT_HOME = $vhDir        # also for THIS terminal

$old = Join-Path $env:USERPROFILE '.vagrant.d'
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  VirtualBox VM folder : $vmDir"
Write-Host "  VAGRANT_HOME         : $vhDir"
if ((Test-Path "$old\boxes") -and ($old -ine $vhDir)) {
    Write-Host "  Note: images already downloaded in $old are not used any more (they will download again)." -ForegroundColor Yellow
    Write-Host "        You can delete $old\boxes later to free space."
}
Write-Host ""
Write-Host "NEXT: fully close and reopen VS Code (so VAGRANT_HOME is picked up), then 'vagrant up'." -ForegroundColor Cyan
