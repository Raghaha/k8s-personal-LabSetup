# Kubernetes Pentest Lab: 1 master + 2 workers on VirtualBox

Build a 3-node Kubernetes cluster on a Windows laptop with **one command** (`vagrant up`), then practise offensive security on it, starting with [Kubernetes Goat](https://madhuakula.com/kubernetes-goat/docs/).

> **Status:** the scripts were syntax-checked and the Goat steps were reviewed against Goat's own scripts, but the whole stack has **not yet been run end-to-end** (the authoring environment has no VirtualBox). Expect to fix a small thing or two on the first build, and use *Troubleshooting* below. The version numbers in `lab.env` (Kubernetes, Calico, Helm) are also unverified live: the scripts fail early with a clear message if one does not exist.

---

## 1. How it works

```
 Windows laptop (host)                         VirtualBox VMs (Ubuntu 24.04)
 ┌─────────────────────────┐   host-only net  ┌──────────────────────────────┐
 │ Vagrantfile + lab.env   │   192.168.56.0/24│ k8s-master  .10  control plane│
 │ vagrant up ─────────────┼─────────────────►│ k8s-worker1 .11  runs pods    │
 │ browser → :1234 (Goat)  │                  │ k8s-worker2 .12  runs pods    │
 └─────────────────────────┘                  └──────────────────────────────┘
        Each VM also has a NAT NIC for internet downloads.
```

* **Vagrant** reads `Vagrantfile`, creates the VMs in VirtualBox, and runs the numbered scripts inside them.
* **`lab.env`** holds every setting you may want to change. The Vagrantfile and all scripts read it.
* The master publishes the *join command* and *kubeconfig* into `.cluster/` (shared folder), and the workers pick up the join command from there.

## 2. Project layout

| Path | Purpose | Edit it? |
|---|---|---|
| `lab.env` | **All settings**: sizes, IPs, versions | **Yes: this is your main file** |
| `Vagrantfile` | Defines the 3 VMs and which script runs where | Rarely |
| `scripts/lib.sh` | Shared helper functions for the scripts | Rarely |
| `scripts/01-common-node.sh` | Every node: swap off, containerd, kubeadm/kubelet/kubectl | When changing the node OS setup |
| `scripts/02-master-init.sh` | Master: `kubeadm init`, kubeconfig, join command | When changing cluster creation |
| `scripts/03-cni-calico.sh` | Master: Calico network plugin | When changing the network plugin |
| `scripts/04-worker-join.sh` | Workers: join the cluster | Rarely |
| `scripts/05-print-join-command.sh` | Master: (re)create the worker join command | Rarely |
| `scripts/06-deploy-goat.sh` | Master: Helm + Kubernetes Goat | When adding/changing the vulnerable target |
| `scripts/07-access-goat.sh` | Master: start Goat port-forwards | — |
| `scripts/08-teardown-goat.sh` | Master: remove Goat | — |
| `scripts/09-verify-cluster.sh` | Master: PASS/FAIL health check | — |
| `scripts/host/00-check-prereqs.ps1` | Windows: checks your laptop before the first build | — |
| `docs/PREREQUISITES.md` | One-time laptop setup | — |
| `.cluster/` | **Generated** (admin kubeconfig, join token). Contains credentials, git-ignored | Never commit |
| `.gitattributes`, `.gitignore` | Keep LF line endings; keep secrets out of Git | No |

Design rule: **one script = one job.** To add something new (e.g. another vulnerable app), copy `06-deploy-goat.sh`, give it the next number, and document it in the table above.

## 3. Quick start

1. Do the one-time setup in [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md).
2. Open PowerShell in the project folder and check your laptop:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\host\00-check-prereqs.ps1
   ```
3. (Optional) Review `lab.env`. The defaults suit a 16 GB laptop.
4. Build everything (≈ 15–30 min the first time; downloads dominate):
   ```powershell
   vagrant up
   ```
5. Verify:
   ```powershell
   vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/09-verify-cluster.sh"
   ```
   Expect three `Ready` nodes with `192.168.56.x` addresses. Workers show ROLES `<none>`; that is normal.
6. Deploy the first target and open it:
   ```powershell
   vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/06-deploy-goat.sh"
   vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/07-access-goat.sh"
   ```
   Browse to **http://192.168.56.10:1234** and follow the [Goat guide](https://madhuakula.com/kubernetes-goat/docs/).

## 4. What do I change? (cheat-sheet)

| I want to… | Edit | Then run |
|---|---|---|
| Give workers more/less RAM or CPU | `WORKER_MEMORY_MB`, `WORKER_CPUS` in `lab.env` | `vagrant halt` → `vagrant up` (applies to existing VMs) |
| Add a 3rd worker | `WORKER_COUNT=3` | `vagrant up k8s-worker3` (the master's join token must still be valid; otherwise first run `vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/05-print-join-command.sh"`) |
| Change IP range | `NETWORK_PREFIX` etc. | Full rebuild (see below) |
| Use another Kubernetes minor | `K8S_MINOR` | Full rebuild (the scripts install fresh; they do not upgrade in place) |
| Use another Calico/Helm/Goat version | `CALICO_VERSION` / `HELM_VERSION` / `GOAT_REF` | Re-run the relevant step, or rebuild |
| Change what a step does | The matching script in `scripts/` | `vagrant provision <vm> --provision-with <step>` |

**Step names** for `--provision-with`: `common`, `control-plane`, `cni` (master) and `join` (workers). Example:
```powershell
vagrant provision k8s-master --provision-with cni
```

**Full rebuild** (the lab is disposable by design):
```powershell
vagrant destroy -f
vagrant up
```

**A tip for safe changes:** change one thing in `lab.env`, rebuild, run `09-verify-cluster.sh`. If it breaks, you know which change did it.

## 5. Everyday commands (PowerShell, project folder)

| Command | Meaning |
|---|---|
| `vagrant status` | Which VMs exist/are running |
| `vagrant up` | Create or start VMs (first time: also provisions) |
| `vagrant halt` | Shut VMs down (keeps disks) |
| `vagrant ssh k8s-master` | Shell on the master (`kubectl` works as the `vagrant` user) |
| `vagrant ssh k8s-worker1` | Shell on worker 1 |
| `vagrant destroy -f` | Delete all VMs and disks |
| `vagrant reload <vm>` | Reboot a VM and re-apply Vagrantfile hardware settings |

After `vagrant halt`/`up` the cluster comes back on its own. Re-run `07-access-goat.sh` if the Goat web UI is not responding (its port-forwards do not survive a reboot).

### Optional: use kubectl from Windows
Install it (`winget install -e --id Kubernetes.kubectl`), then in each PowerShell session:
```powershell
$env:KUBECONFIG = "$PWD\.cluster\admin.conf"
kubectl get nodes
```
`.cluster/admin.conf` is **full admin access**; treat it like a password.

## 6. Pentest targets

| Target | Status in this repo |
|---|---|
| [Kubernetes Goat](https://madhuakula.com/kubernetes-goat/docs/) | Scripted (`06`–`08`) |
| [k8s-bh26india workshop](https://k8s-bh26india.netlify.app/index.html) | Not scripted yet: follow its own page on this cluster |
| [OWASP PwnzzAI](https://github.com/OWASP/PwnzzAI) | Not scripted yet: read its README for how to deploy it |

Run targets **one at a time**; the nodes have limited RAM. When a target is scripted, it becomes the next numbered script (see "Design rule" above).

## 7. Safety

* Goat contains deliberate container-escape and privileged-pod scenarios. After practising them, treat the VMs as compromised: rebuild instead of reusing.
* Keep the lab on the **host-only** network. Never switch the adapters to *Bridged*.
* Store nothing sensitive in the VMs. Do not commit `.cluster/` (already git-ignored).
* Scripts download software from the internet (Kubernetes repo, GitHub, Helm). Versions are pinned in `lab.env`; Helm's checksum is verified and Goat is pinned to a reviewed commit.

## 8. Troubleshooting

| Symptom | Likely cause → fix |
|---|---|
| `$'\r': command not found` or *"CRLF line endings"* error from Vagrant | Files were converted to Windows line endings → `git add --renormalize .`, or re-clone; `.gitattributes` prevents this |
| Script says *"Cannot download: …"* | A version in `lab.env` doesn't exist (typo, or not released) → check the URL's release page named in the message |
| VM boots very slowly or hangs at "Waiting for SSH" | Virtualization off in BIOS, or Hyper-V/WSL2 conflict → run `00-check-prereqs.ps1`; see PREREQUISITES §4 |
| Host-only network error on `vagrant up` | The `NETWORK_PREFIX` range is not allowed by VirtualBox (Linux/macOS hosts: add it to `/etc/vbox/networks.conf`) or a stale network exists → VirtualBox *Tools → Network* |
| Nodes `NotReady` | Calico not installed yet or failing → `vagrant ssh k8s-master`, then `kubectl get pods -A` and `kubectl -n calico-system get pods` |
| Nodes show INTERNAL-IP `10.0.2.15` | kubelet not pinned to the host-only IP → `cat /etc/default/kubelet` on that node, then `sudo systemctl restart kubelet` |
| Worker failed to join / *token expired* | Run `05-print-join-command.sh` on the master, then `vagrant provision k8s-workerN --provision-with join` |
| Goat page doesn't load | Pods still starting (`kubectl get pods`) or port-forwards died → re-run `07-access-goat.sh` and check `/var/log/goat-access.log` on the master |
| Pods stuck `ImagePullBackOff` | Workers have no internet/DNS → try `ping registry.k8s.io` from the worker; restart VirtualBox NAT by `vagrant reload <vm>` |
| Provisioning step failed midway | Fix the cause, then re-run only that step: `vagrant provision <vm> --provision-with <step>` (all scripts are safe to re-run) |

Useful logs: `/var/log/kubeadm-init.log` (master), `journalctl -u kubelet` (any node).

## 9. Resource summary (defaults)

| Node | vCPU | RAM | Host-only IP |
|---|---|---|---|
| k8s-master | 2 | 3 GB | 192.168.56.10 |
| k8s-worker1 | 2 | 4 GB | 192.168.56.11 |
| k8s-worker2 | 2 | 4 GB | 192.168.56.12 |

The master stays small because it only runs the control plane (workloads are kept off it by Kubernetes' default taint). Worker memory is what the vulnerable apps consume, so tune the workers first if the laptop is tight.
