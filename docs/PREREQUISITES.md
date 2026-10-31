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

## 5. Get the project and set line endings

```powershell
git clone <your-repo-url> k8s-LabSetup     # or copy the folder
cd k8s-LabSetup
```

`.gitattributes` in this project forces Unix (LF) line endings for scripts. If you copy the files by other means (zip, USB, cloud drive), make sure they were not converted to CRLF. The next step detects this.

## 6. Run the prerequisite check

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\host\00-check-prereqs.ps1
```

Everything marked `[FAIL]` must be fixed before `vagrant up`; `[WARN]` is advice.

## 7. Network facts (so nothing surprises you)

* VMs get **two** NICs: NAT (internet, shared address `10.0.2.15`) and *host-only* (`192.168.56.x`, only your laptop can reach it).
* Vagrant creates the host-only network automatically on the first `vagrant up`. A Windows firewall pop-up may appear; allow *private* networks.
* Nothing is exposed to your home/office LAN. Keep it that way: this lab contains intentionally vulnerable software.
