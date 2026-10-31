# Prerequisites

Do these once on the **Windows laptop** that will host the lab. Total time ≈ 30 min plus downloads.

## 1. Hardware

| Item | Minimum | Comfortable |
|---|---|---|
| RAM | 16 GB | 32 GB |
| CPU | 4 cores / 8 threads | 8 cores |
| Free disk | 80 GB | 120 GB (SSD) |
| CPU feature | VT-x / AMD-V enabled | — |

The default lab (`lab.env`) uses **11 GB RAM and 6 vCPUs** while running. The master gets less RAM than the workers because it only runs the control plane. Disk is thin-provisioned, so VMs only use what they actually fill.

## 2. Enable virtualization in BIOS/UEFI
Restart → enter BIOS (usually F2/F10/Del) → enable **Intel VT-x** or **AMD-V / SVM** → save.
Verify in Task Manager → Performance → CPU → *Virtualization: Enabled*.

## 3. Install the software

Use `winget` in a normal PowerShell window, or download installers from the vendors.

```powershell
winget install --id Oracle.VirtualBox -e
winget install --id Hashicorp.Vagrant -e
winget install --id Git.Git -e
```

Reboot after installing VirtualBox/Vagrant.

* **Compatibility:** Vagrant only supports certain VirtualBox versions. Check the *VirtualBox provider* page in the Vagrant docs (developer.hashicorp.com/vagrant/docs/providers/virtualbox) against the versions `winget` installed. If they do not match, install the latest Vagrant (or the VirtualBox version Vagrant lists).
* The VirtualBox *Extension Pack* is **not** required for this lab.

## 4. (Only if the lab runs very slowly) Hyper-V / WSL2 conflict

Windows features like Hyper-V, WSL2, Docker Desktop and "Memory integrity" make Windows run its own hypervisor. VirtualBox still works beside it, only slower.
To give VirtualBox full speed, open PowerShell **as Administrator**:

```powershell
bcdedit /set hypervisorlaunchtype off   # then reboot
# To undo later (needed for WSL2/Docker Desktop):
bcdedit /set hypervisorlaunchtype auto  # then reboot
```

## 5. Get the project onto the Windows laptop

The project is your own repository. There is no ready-made URL, so create one once, from the machine where the files live (your Mac).

**Option A: private GitHub repository (recommended)**

1. On the Mac, in the project folder:
   ```bash
   git init
   git add .
   git commit -m "Initial k8s lab setup"
   ```
2. On github.com create an **empty private** repository (no README, no .gitignore), e.g. `k8s-LabSetup`. Use your personal account.
3. Connect and push:
   ```bash
   git remote add origin https://github.com/<your-username>/k8s-LabSetup.git
   git branch -M main
   git push -u origin main
   ```
4. On the Windows laptop:
   ```powershell
   git clone https://github.com/<your-username>/k8s-LabSetup.git
   cd k8s-LabSetup
   ```

**Option B: copy the folder** (USB drive, zip, cloud drive). Afterwards, make sure the scripts still use Unix (LF) line endings; the next step checks this.

`.gitattributes` forces LF line endings for the scripts, and `.gitignore` keeps `.cluster/` (credentials) out of Git.

## 6. Run the prerequisite check

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\host\00-check-prereqs.ps1
```

Everything marked `[FAIL]` must be fixed before `vagrant up`; `[WARN]` is advice.

## 7. Network facts (so nothing surprises you)

* VMs get **two** NICs: NAT (internet, shared address `10.0.2.15`) and *host-only* (`192.168.56.x`, only your laptop can reach it).
* Vagrant creates the host-only network automatically on the first `vagrant up`. A Windows firewall pop-up may appear; allow *private* networks.
* Nothing is exposed to your home/office LAN. Keep it that way: this lab contains intentionally vulnerable software.

## 8. Optional: keep VM disks off the C: drive

By default VirtualBox puts VM disks on `C:` and Vagrant stores its downloaded images under your user profile. To use another drive:

1. In `lab.env` set (in quotes): `VM_STORAGE_DIR="D:\VMs"`
2. Run once, **before the first `vagrant up`**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\host\01-set-storage.ps1
   ```
3. Fully close and reopen VS Code, then continue with `vagrant up`.

Rules the script enforces: the drive must be a fixed internal disk, and not a cloud-synced folder (OneDrive, Dropbox, ...). It warns about hard disks (HDD): etcd is sensitive to disk latency, so use an SSD. VMs that already exist are not moved; run `vagrant destroy -f` first if you want them rebuilt in the new place.

