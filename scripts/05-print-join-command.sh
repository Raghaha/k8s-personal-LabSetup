#!/usr/bin/env bash
# =============================================================================
#  05-print-join-command.sh   -   runs on the MASTER only
# =============================================================================
#  Creates a fresh bootstrap token and saves the full 'kubeadm join ...' line to
#  <project>/.cluster/join-command.sh.
#
#  It is called automatically by 02. Run it again by hand when the token has
#  expired (default 24h) and you want to add a worker later:
#       vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/05-print-join-command.sh"
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env
use_admin_kubeconfig

mkdir -p "${CLUSTER_DIR}"
kubeadm token create --ttl "${JOIN_TOKEN_TTL}" --print-join-command > "${CLUSTER_DIR}/join-command.sh"
log "Join command saved to ${CLUSTER_DIR}/join-command.sh (valid ${JOIN_TOKEN_TTL})"
