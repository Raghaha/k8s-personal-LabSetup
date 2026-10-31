#!/usr/bin/env bash
# =============================================================================
#  09-verify-cluster.sh   -   runs on the MASTER
# =============================================================================
#  Health check. Prints PASS/FAIL for the things that most often go wrong:
#    - all nodes registered and Ready
#    - nodes use the host-only IPs (not 10.0.2.15)
#    - no kube-system / calico pods stuck
#
#       vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/09-verify-cluster.sh"
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env
use_admin_kubeconfig

FAIL=0
pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAIL=1; }

EXPECTED=$((1 + WORKER_COUNT))
echo; kubectl get nodes -o wide; echo

READY=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
[[ "${READY}" -eq "${EXPECTED}" ]] && pass "${READY}/${EXPECTED} nodes Ready" || fail "only ${READY}/${EXPECTED} nodes Ready"

BAD_IP=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | grep -vc "^${NETWORK_PREFIX}\." || true)
[[ "${BAD_IP}" -eq 0 ]] && pass "all nodes use ${NETWORK_PREFIX}.x addresses" \
  || fail "${BAD_IP} node(s) not on ${NETWORK_PREFIX}.x - check /etc/default/kubelet and restart kubelet"

NOT_OK=$(kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed"' | grep -E 'kube-system|calico|tigera' | wc -l || true)
[[ "${NOT_OK}" -eq 0 ]] && pass "system pods healthy" \
  || { fail "${NOT_OK} system pod(s) not Running:"; kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed"'; }

echo
[[ "${FAIL}" -eq 0 ]] && echo "Cluster looks healthy." || { echo "Problems found - see README.md > Troubleshooting."; exit 1; }
