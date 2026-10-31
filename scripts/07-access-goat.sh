#!/usr/bin/env bash
# =============================================================================
#  07-access-goat.sh   -   runs on the MASTER
# =============================================================================
#  Goat's own access script starts "kubectl port-forward" processes that listen
#  on ALL interfaces of the master (ports 1230-1236). This wrapper:
#    - stops old port-forwards,
#    - starts new ones in the background so they survive after you disconnect,
#    - tells you the URL to open from Windows.
#
#  Run from Windows:
#       vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/07-access-goat.sh"
#
#  Re-run it whenever the web UI stops responding (port-forwards die if a pod
#  restarts or the VM reboots).
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env
use_admin_kubeconfig

GOAT_DIR="/home/${LAB_USER}/labs/kubernetes-goat"
[[ -d "${GOAT_DIR}" ]] || die "Goat not found. Run 06-deploy-goat.sh first."

log "Stopping old port-forwards (if any)"
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 1

log "Starting port-forwards in the background (log: /var/log/goat-access.log)"
cd "${GOAT_DIR}"
# setsid + nohup detach the process from this SSH session so it keeps running.
setsid nohup bash access-kubernetes-goat.sh --kubeconfig "${KUBECONFIG}" \
  > /var/log/goat-access.log 2>&1 < /dev/null &

# Goat's script loops until each pod is Running; give it time to finish.
for _ in $(seq 1 30); do
  grep -q "Visit http" /var/log/goat-access.log 2>/dev/null && break
  sleep 5
done

cat <<EOF

--------------------------------------------------------------------------
  Open in your Windows browser:   http://${MASTER_IP}:1234
  (Goat's own message says 127.0.0.1 - that is the master's view; use the
   host-only IP above from Windows.)
  Scenario ports: 1230-1236 on ${MASTER_IP}
--------------------------------------------------------------------------
EOF
