#!/usr/bin/env bash
# =============================================================================
#  01-common-node.sh   -   runs on EVERY node (master + workers)
# =============================================================================
#  Usage (done for you by Vagrant):  bash 01-common-node.sh <this-node-host-only-IP>
#
#  What it does, in order:
#    1. Fixes /etc/hosts so nodes can find each other by name.
#    2. Turns off swap (kubelet refuses to run with swap on).
#    3. Loads kernel modules + network settings that Kubernetes networking needs.
#    4. Installs containerd (the container runtime) with systemd cgroups.
#    5. Installs kubeadm, kubelet, kubectl from the official Kubernetes repo.
#    6. Tells kubelet to use the host-only IP (NOT the NAT IP).
#
#  Safe to re-run: every step checks / overwrites rather than appends.
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env

NODE_IP="${1:?Usage: 01-common-node.sh <node-ip>}"
export DEBIAN_FRONTEND=noninteractive   # never stop to ask questions during apt

# ---------------------------------------------------------------------------
log "1/6  /etc/hosts: map node names to host-only IPs"
# ---------------------------------------------------------------------------
# Vagrant maps the node's own name to a loopback address (127.0.2.1). That
# breaks etcd/kubeadm because they would listen on the wrong address, so we
# remove that line and add real entries instead.
sed -i -E '/^127\.0\.[12]\.1[[:space:]].*k8s-(master|worker)/d' /etc/hosts
sed -i '/# k8s-lab managed/d' /etc/hosts       # remove our own old entries (re-run safe)
{
  echo "${MASTER_IP} ${MASTER_NAME} # k8s-lab managed"
  for i in $(seq 1 "${WORKER_COUNT}"); do
    echo "${NETWORK_PREFIX}.$((WORKER_IP_START + i - 1)) k8s-worker${i} # k8s-lab managed"
  done
} >> /etc/hosts

# ---------------------------------------------------------------------------
log "2/6  Disable swap (Kubernetes requirement)"
# ---------------------------------------------------------------------------
swapoff -a
sed -ri '/\sswap\s/s/^/#/' /etc/fstab          # keep it off after reboot

# ---------------------------------------------------------------------------
log "3/6  Kernel modules + sysctl settings for pod networking"
# ---------------------------------------------------------------------------
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# ---------------------------------------------------------------------------
log "4/6  Install containerd (container runtime)"
# ---------------------------------------------------------------------------
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# kubelet uses systemd for cgroups, so containerd must too, or pods crash-loop.
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd
systemctl restart containerd

# ---------------------------------------------------------------------------
log "5/6  Install kubeadm / kubelet / kubectl (${K8S_MINOR})"
# ---------------------------------------------------------------------------
K8S_REPO="https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb"
check_url "${K8S_REPO}/Release.key" \
  "K8S_MINOR='${K8S_MINOR}' is not published. See https://kubernetes.io/releases/ and fix lab.env."
mkdir -p /etc/apt/keyrings
curl -fsSL "${K8S_REPO}/Release.key" | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${K8S_REPO}/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
# "hold" stops a routine 'apt upgrade' from silently upgrading Kubernetes.
apt-mark hold kubelet kubeadm kubectl

# ---------------------------------------------------------------------------
log "6/6  Pin kubelet to the host-only IP ${NODE_IP}"
# ---------------------------------------------------------------------------
# Every VirtualBox NAT adapter has the same IP (10.0.2.15). Without this,
# nodes may register with that useless address and pods cannot talk to each other.
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl enable kubelet
systemctl restart kubelet || true   # it crash-loops until 'kubeadm init/join' runs - that is normal

log "Node setup complete: $(hostname) (${NODE_IP}) - kubeadm $(kubeadm version -o short)"
