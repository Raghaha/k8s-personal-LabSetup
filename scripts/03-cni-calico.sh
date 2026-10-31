#!/usr/bin/env bash
# =============================================================================
#  03-cni-calico.sh   -   runs on the MASTER only
# =============================================================================
#  A fresh cluster has NO pod networking, so nodes stay "NotReady" until a CNI
#  (Container Network Interface) plugin is installed. We use Calico because it
#  also enforces NetworkPolicy - useful for later defensive-security labs.
#
#  Calico is installed through its "operator": we install the operator, then
#  hand it a small 'Installation' description of what we want.
#
#  Safe to re-run.
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env
use_admin_kubeconfig

OPERATOR_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
check_url "${OPERATOR_URL}" "CALICO_VERSION='${CALICO_VERSION}' not found. See https://github.com/projectcalico/calico/releases and fix lab.env."

# ---------------------------------------------------------------------------
if kubectl get namespace tigera-operator >/dev/null 2>&1; then
  log "Calico operator already installed - skipping"
else
  log "Installing Calico operator ${CALICO_VERSION}"
  # 'create' (not 'apply'): the operator CRDs are too large for 'apply'.
  kubectl create -f "${OPERATOR_URL}"
fi

log "Waiting for the operator's Installation CRD to be ready"
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=180s

# ---------------------------------------------------------------------------
log "Applying Calico Installation (pods ${POD_CIDR}, ${CALICO_ENCAPSULATION}, NIC on ${NETWORK_PREFIX}.0/24)"
# nodeAddressAutodetectionV4.cidrs is the key line for VirtualBox: it forces
# Calico to use the host-only NIC instead of the shared NAT address 10.0.2.15.
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - cidr: ${POD_CIDR}
        encapsulation: ${CALICO_ENCAPSULATION}
        natOutgoing: Enabled
        nodeSelector: all()
    nodeAddressAutodetectionV4:
      cidrs:
        - ${NETWORK_PREFIX}.0/24
EOF

# ---------------------------------------------------------------------------
log "Waiting for the master node to become Ready (Calico images are pulled now, up to ~5 min)"
for attempt in $(seq 1 30); do
  if kubectl wait --for=condition=Ready "node/${MASTER_NAME}" --timeout=20s >/dev/null 2>&1; then
    log "Master is Ready. CNI installed."
    exit 0
  fi
  echo "  ...still waiting (${attempt}/30)"
done
die "Master did not become Ready. Check: kubectl get pods -A   and   kubectl -n calico-system get pods"
