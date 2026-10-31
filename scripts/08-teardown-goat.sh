#!/usr/bin/env bash
# =============================================================================
#  08-teardown-goat.sh   -   runs on the MASTER
# =============================================================================
#  Removes Kubernetes Goat's scenarios from the cluster (cluster itself stays).
#  After heavy exploitation practice it is cleaner to rebuild the whole lab
#  (vagrant destroy -f && vagrant up) than to trust this teardown.
#
#       vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/08-teardown-goat.sh"
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env
use_admin_kubeconfig

GOAT_DIR="/home/${LAB_USER}/labs/kubernetes-goat"
[[ -d "${GOAT_DIR}" ]] || die "Goat not found - nothing to remove."

pkill -f "kubectl.*port-forward" 2>/dev/null || true
cd "${GOAT_DIR}"
# Goat's teardown continues past "not found" errors, so do not stop on them.
set +e
bash teardown-kubernetes-goat.sh
set -e
log "Goat removed."
