#!/usr/bin/env bash
# =============================================================================
#  06-deploy-goat.sh   -   runs on the MASTER (manually, after the cluster is up)
# =============================================================================
#  Deploys Kubernetes Goat, an INTENTIONALLY VULNERABLE cluster for practising
#  attacks. Docs: https://madhuakula.com/kubernetes-goat/docs/
#
#  Run it from Windows:
#       vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/06-deploy-goat.sh"
#
#  What it does:
#    1. Installs Helm (version pinned in lab.env, SHA-256 checked).
#    2. Fetches the Goat repo at the pinned GOAT_REF into /home/vagrant/labs/.
#    3. Runs Goat's own setup script against this cluster.
#    4. Waits for the deployments to become Available.
#
#  Next step:  07-access-goat.sh
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root
load_env
use_admin_kubeconfig

GOAT_DIR="/home/${LAB_USER}/labs/kubernetes-goat"

# ---------------------------------------------------------------------------
log "1/4  Helm ${HELM_VERSION}"
# ---------------------------------------------------------------------------
if command -v helm >/dev/null 2>&1 && [[ "$(helm version --template '{{.Version}}')" == "${HELM_VERSION}" ]]; then
  echo "Helm ${HELM_VERSION} already installed."
else
  ARCH="$(dpkg --print-architecture)"                      # amd64 or arm64
  TARBALL="helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
  TMP="$(mktemp -d)"
  check_url "https://get.helm.sh/${TARBALL}" "HELM_VERSION='${HELM_VERSION}' not found. See https://github.com/helm/helm/releases"
  curl -fsSL -o "${TMP}/${TARBALL}" "https://get.helm.sh/${TARBALL}"
  curl -fsSL -o "${TMP}/${TARBALL}.sha256sum" "https://get.helm.sh/${TARBALL}.sha256sum"
  # Verify the download was not corrupted or tampered with before installing.
  ( cd "${TMP}" && sha256sum -c "${TARBALL}.sha256sum" )
  tar -xzf "${TMP}/${TARBALL}" -C "${TMP}"
  install -m 0755 "${TMP}/linux-${ARCH}/helm" /usr/local/bin/helm
  rm -rf "${TMP}"
fi
helm version --short

# ---------------------------------------------------------------------------
log "2/4  Fetch Kubernetes Goat @ ${GOAT_REF}"
# ---------------------------------------------------------------------------
apt-get install -y git >/dev/null
install -d -o "${LAB_USER}" -g "${LAB_USER}" "$(dirname "${GOAT_DIR}")"
# We run as root but the folder is owned by 'vagrant' (after the first run), so
# tell git this folder is trusted; otherwise git refuses with "dubious ownership".
goat_git() { git -c safe.directory="${GOAT_DIR}" -C "${GOAT_DIR}" "$@"; }
if [[ ! -d "${GOAT_DIR}/.git" ]]; then
  git init -q "${GOAT_DIR}"
  goat_git remote add origin https://github.com/madhuakula/kubernetes-goat.git
fi
goat_git fetch -q --depth 1 origin "${GOAT_REF}"
goat_git checkout -q --force FETCH_HEAD
chown -R "${LAB_USER}:${LAB_USER}" "${GOAT_DIR}"

# ---------------------------------------------------------------------------
log "3/4  Run Goat's setup script"
# ---------------------------------------------------------------------------
cd "${GOAT_DIR}"
if helm status metadata-db >/dev/null 2>&1; then
  warn "Goat already deployed (helm release 'metadata-db' exists) - skipping setup."
else
  bash setup-kubernetes-goat.sh
fi

# ---------------------------------------------------------------------------
log "4/4  Waiting for deployments (images download on the workers, up to ~10 min)"
# ---------------------------------------------------------------------------
kubectl wait --for=condition=Available deployment --all -n default --timeout=600s
kubectl wait --for=condition=Available deployment --all -n big-monolith --timeout=600s || true
kubectl get pods -A -o wide | grep -Ev 'kube-system|calico|tigera' || true

log "Goat deployed. Next: bash /vagrant/scripts/07-access-goat.sh"
