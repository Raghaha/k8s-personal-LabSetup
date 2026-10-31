#!/usr/bin/env bash
# =============================================================================
#  02-master-init.sh   -   runs on the MASTER only
# =============================================================================
#  What it does:
#    1. 'kubeadm init' - creates the control plane (API server, etcd, scheduler...).
#    2. Gives the 'vagrant' user a working kubectl config.
#    3. Copies the admin kubeconfig to <project>/.cluster/admin.conf so you can
#       run kubectl from your Windows laptop too.
#    4. Publishes the "join command" workers will use (via 05-print-join-command.sh).
#
#  Safe to re-run: if the cluster already exists, init is skipped and only the
#  kubeconfig copy + join command are refreshed.
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env

# ---------------------------------------------------------------------------
if [[ -f /etc/kubernetes/admin.conf ]]; then
  log "Cluster already initialised on this node - skipping 'kubeadm init'"
else
  log "Pre-pulling control-plane images (this is the slow part, ~2-5 min)"
  kubeadm config images pull

  log "Running kubeadm init (advertise address ${MASTER_IP})"
  # --apiserver-advertise-address : the host-only IP, NOT the NAT IP
  # --apiserver-cert-extra-sans   : names/IPs allowed in the API server TLS cert,
  #                                 so kubectl from Windows verifies correctly
  # --pod-network-cidr / --service-cidr : IP ranges from lab.env
  kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --apiserver-cert-extra-sans="${MASTER_IP},${MASTER_NAME}" \
    --pod-network-cidr="${POD_CIDR}" \
    --service-cidr="${SERVICE_CIDR}" \
    --node-name="${MASTER_NAME}" \
    | tee /var/log/kubeadm-init.log
fi

# ---------------------------------------------------------------------------
log "Configuring kubectl for user '${LAB_USER}'"
install -d -o "${LAB_USER}" -g "${LAB_USER}" "/home/${LAB_USER}/.kube"
cp /etc/kubernetes/admin.conf "/home/${LAB_USER}/.kube/config"
chown "${LAB_USER}:${LAB_USER}" "/home/${LAB_USER}/.kube/config"

# ---------------------------------------------------------------------------
log "Publishing kubeconfig to ${CLUSTER_DIR}/admin.conf (use it from Windows)"
mkdir -p "${CLUSTER_DIR}"
cp /etc/kubernetes/admin.conf "${CLUSTER_DIR}/admin.conf"

# ---------------------------------------------------------------------------
log "Creating the worker join command"
bash "${SCRIPT_DIR}/05-print-join-command.sh"
