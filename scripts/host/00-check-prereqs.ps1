<#
=============================================================================
 00-check-prereqs.ps1   -   runs on your WINDOWS laptop (host), not in a VM
=============================================================================
 Read-only health check. It changes NOTHING; it only reports.
 Run it from the project folder BEFORE the first 'vagrant up':

     powershell -ExecutionPolicy Bypass -File .\scripts\host\00-check-prereqs.ps1

 Checks: VirtualBox, Vagrant, Git, CPU virtualization, Hyper-V conflict,
 free RAM vs. what lab.env asks for, free disk, and Windows line endings.
=============================================================================
#>
$ErrorActionPreference = 'Stop'
$root   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$script:fails = 0
function Ok($m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fails++ }

# --- Read lab.env (same KEY=VALUE format the other scripts use) -------------
$cfg = @{}
Get-Content (Join-Path $root 'lab.env') | ForEach-Object {
    $l = $_.Trim()
    if ($l -and -not $l.StartsWith('#') -and $l.Contains('=')) {
        $k, $v = $l.Split('=', 2)
        $cfg[$k.Trim()] = ($v -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
    }
}

Write-Host "`n== Tools ==" -ForegroundColor Cyan
# VirtualBox: VBoxManage is not always on PATH, so also try the default folder.
$vbox = (Get-Command VBoxManage -ErrorAction SilentlyContinue).Source
if (-not $vbox -and (Test-Path 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe')) {
    $vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
}
if ($vbox) { Ok "VirtualBox $(& $vbox --version)" } else { Bad "VirtualBox not found (see docs/PREREQUISITES.md)" }

if (Get-Command vagrant -ErrorAction SilentlyContinue) { Ok "$(vagrant --version)" }
else { Bad "Vagrant not found (see docs/PREREQUISITES.md)" }

if (Get-Command git -ErrorAction SilentlyContinue) { Ok "$(git --version)" }
else { Warn "Git not found - optional, but recommended to version your lab files" }

Write-Host "`n== CPU / virtualization ==" -ForegroundColor Cyan
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
if ($cpu.VirtualizationFirmwareEnabled) { Ok "Hardware virtualization (VT-x/AMD-V) enabled in BIOS" }
else { Bad "Virtualization is OFF in BIOS/UEFI - enable VT-x / AMD-V / SVM" }

# If Windows' own hypervisor is active (Hyper-V, WSL2, Memory Integrity, Docker
# Desktop) VirtualBox still works but slower. Not fatal - just a hint.
if ($cs.HypervisorPresent) {
    Warn "Windows hypervisor is active (Hyper-V/WSL2/Core Isolation). VirtualBox will work but slower."
    Warn "For speed: 'bcdedit /set hypervisorlaunchtype off' in an ADMIN shell, then reboot (undo with 'auto')."
} else { Ok "No competing Windows hypervisor" }

Write-Host "`n== Resources vs lab.env ==" -ForegroundColor Cyan
$workers  = [int]$cfg['WORKER_COUNT']
$needMB   = [int]$cfg['MASTER_MEMORY_MB'] + $workers * [int]$cfg['WORKER_MEMORY_MB']
$needCpu  = [int]$cfg['MASTER_CPUS']      + $workers * [int]$cfg['WORKER_CPUS']
$totalMB  = [math]::Round($cs.TotalPhysicalMemory / 1MB)
$freeMB   = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
Write-Host "  Lab asks for: $needMB MB RAM, $needCpu vCPU across $($workers + 1) VMs"
Write-Host "  This laptop : $totalMB MB RAM total, $freeMB MB free now, $($cpu.NumberOfLogicalProcessors) logical CPUs"
if ($freeMB -lt $needMB + 2048) { Warn "Free RAM is tight. Close heavy apps, or lower *_MEMORY_MB in lab.env." } else { Ok "Enough free RAM" }
if ($needCpu -gt $cpu.NumberOfLogicalProcessors) { Warn "More vCPUs requested than logical CPUs (works, but oversubscribed)" } else { Ok "vCPU count fits" }

# Disk space is checked on the drive where the VMs will live: VM_STORAGE_DIR if
# set in lab.env, otherwise the drive of this project folder.
$driveName = (Get-Item $root).PSDrive.Name
if ($cfg['VM_STORAGE_DIR'] -match '^([A-Za-z]):') { $driveName = $Matches[1].ToUpper() }
$drive = Get-PSDrive -Name $driveName
$freeGB = [math]::Round($drive.Free / 1GB)
$needGB = 20 * ($workers + 1)    # each VM disk grows up to ~20 GB in practice
if ($freeGB -lt $needGB) { Warn "Only $freeGB GB free on $($drive.Name): (plan for ~$needGB GB + the box download)" }
else { Ok "$freeGB GB free on $($drive.Name):" }
if ($env:VAGRANT_HOME) { Write-Host "  Vagrant boxes are stored in: $env:VAGRANT_HOME" }
else { Write-Host "  Vagrant boxes are stored in: $env:USERPROFILE\.vagrant.d  (set VAGRANT_HOME to move it)" }

Write-Host "`n== Storage locations ==" -ForegroundColor Cyan
$want = $cfg['VM_STORAGE_DIR']
$vmFolder = $null
if ($vbox) {
    $line = & $vbox list systemproperties | Select-String 'Default machine folder'
    if ($line) { $vmFolder = ($line.ToString() -replace '^.*?:\s*', '').Trim() }
}
$vhome = if ($env:VAGRANT_HOME) { $env:VAGRANT_HOME } else { "$env:USERPROFILE\.vagrant.d" }
Write-Host "  VirtualBox VM folder : $vmFolder"
Write-Host "  Vagrant box storage  : $vhome"
if ($want) {
    $wantVm = Join-Path $want 'VirtualBox'
    $wantVh = Join-Path $want 'vagrant.d'
    if ($vmFolder -and ($vmFolder.TrimEnd('\') -ine $wantVm.TrimEnd('\'))) { Warn "VM folder differs from VM_STORAGE_DIR - run scripts\host\01-set-storage.ps1" } else { Ok "VM folder matches lab.env" }
    if ($vhome.TrimEnd('\') -ine $wantVh.TrimEnd('\')) { Warn "VAGRANT_HOME differs from VM_STORAGE_DIR - run 01-set-storage.ps1, then restart VS Code" } else { Ok "VAGRANT_HOME matches lab.env" }
} else { Write-Host "  (VM_STORAGE_DIR is empty in lab.env: defaults in use)" }
if ($vmFolder -match 'OneDrive|Dropbox|Google ?Drive') { Warn "VM folder looks cloud-synced - move it (see docs/PREREQUISITES.md)" }

Write-Host "`n== Project files ==" -ForegroundColor Cyan
$crlf = Get-ChildItem (Join-Path $root 'scripts') -Filter *.sh | Where-Object {
    [System.IO.File]::ReadAllText($_.FullName).Contains("`r`n")
}
if ($crlf) { Bad "Windows (CRLF) line endings in: $($crlf.Name -join ', ') - run 'git add --renormalize .' or re-clone with .gitattributes in place" }
else { Ok "All scripts/*.sh use Unix (LF) line endings" }

Write-Host ""
if ($script:fails -eq 0) { Write-Host "All required checks passed. Next: vagrant up" -ForegroundColor Green; exit 0 }
else { Write-Host "$($script:fails) required check(s) failed - fix them, then re-run." -ForegroundColor Red; exit 1 }
