#!/usr/bin/env bash
# =============================================================================
#  04-worker-join.sh   -   runs on each WORKER
# =============================================================================
#  Reads the join command the master published in <project>/.cluster/ and runs
#  it. Waits a few minutes if the master has not published it yet.
#
#  Safe to re-run: a node that already joined is skipped.
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env

JOIN_FILE="${CLUSTER_DIR}/join-command.sh"

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  log "$(hostname) already joined the cluster - skipping"
  exit 0
fi

log "Waiting for the master to publish ${JOIN_FILE}"
for _ in $(seq 1 60); do
  [[ -s "${JOIN_FILE}" ]] && break
  sleep 5
done
[[ -s "${JOIN_FILE}" ]] || die "Join command not found. Is the master up? Try: vagrant provision k8s-master --provision-with control-plane"

log "Checking the API server is reachable at ${MASTER_IP}:6443"
timeout 10 bash -c "exec 3<>/dev/tcp/${MASTER_IP}/6443" \
  || die "Cannot reach ${MASTER_IP}:6443 from this worker (check host-only network)."

log "Joining the cluster"
bash "${JOIN_FILE}"
log "$(hostname) joined. Verify from the master:  kubectl get nodes"
