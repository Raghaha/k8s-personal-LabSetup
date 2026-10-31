#!/usr/bin/env bash
# =============================================================================
#  lib.sh  -  shared helpers. Every other script does:  source "$SCRIPT_DIR/lib.sh"
#  You normally never run this file directly.
# =============================================================================

# Strict mode: stop on first error (-e), on unset variables (-u), and when any
# command in a pipeline fails (pipefail). This prevents "half-built" nodes.
set -euo pipefail

# Where the project folder is mounted inside the VM (see Vagrantfile).
LAB_DIR="${LAB_DIR:-/vagrant}"
# Folder where the master publishes the join command and kubeconfig.
CLUSTER_DIR="${LAB_DIR}/.cluster"
# The normal (non-root) Linux user inside the VMs. Vagrant boxes use "vagrant".
LAB_USER="${LAB_USER:-vagrant}"

log()  { printf '\n[%s] ==> %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "Run as root (use sudo)."; }

# Load lab.env into shell variables. "tr -d '\r'" removes Windows line endings
# if the file was edited on Windows.
load_env() {
  [[ -f "${LAB_DIR}/lab.env" ]] || die "${LAB_DIR}/lab.env not found."
  set -a
  # shellcheck disable=SC1090
  source <(tr -d '\r' < "${LAB_DIR}/lab.env")
  set +a
  MASTER_NAME="k8s-master"
  MASTER_IP="${NETWORK_PREFIX}.${MASTER_IP_SUFFIX}"
}

# Fail early, with a useful message, if a download URL is wrong (e.g. a typo in
# a version number in lab.env). Fetches only the first byte.
check_url() {
  local url="$1" hint="${2:-Check the version in lab.env.}"
  curl -fsSL --max-time 30 -r 0-0 -o /dev/null "$url" \
    || die "Cannot download: ${url}
       ${hint}"
}

# All scripts that talk to the cluster as root use the admin kubeconfig.
use_admin_kubeconfig() {
  export KUBECONFIG=/etc/kubernetes/admin.conf
  [[ -f "$KUBECONFIG" ]] || die "Cluster not initialised yet (no ${KUBECONFIG}). Run step 02 first."
}
