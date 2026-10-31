# -*- mode: ruby -*-
# vi: set ft=ruby :
# =============================================================================
#  Vagrantfile  -  describes the 3 VMs and WHICH SCRIPT runs on WHICH VM.
# =============================================================================
#  Vagrant = a tool that drives VirtualBox from text files, so the lab can be
#  built, destroyed and rebuilt with one command:
#       vagrant up        -> create + provision all VMs
#       vagrant destroy -f -> delete all VMs
#
#  You should rarely need to edit this file. VM sizes, IPs, versions etc. all
#  come from lab.env. Edit THIS file only to change the *structure* (e.g. add a
#  new provisioning step).
# =============================================================================

# ---------------------------------------------------------------------------
# Helper: read lab.env (KEY=VALUE lines) into a Ruby hash.
# ---------------------------------------------------------------------------
def load_env(path)
  abort "ERROR: #{path} not found." unless File.exist?(path)
  cfg = {}
  File.readlines(path).each do |raw|
    line = raw.strip                                  # strip also removes a Windows \r
    next if line.empty? || line.start_with?("#")
    key, val = line.split("=", 2)
    next if val.nil?
    val = val.sub(/\s+#.*$/, "").strip                # drop trailing "  # comment"
    val = val.gsub(/\A["']|["']\z/, "")               # drop optional quotes
    cfg[key.strip] = val
  end
  cfg
end

# ---------------------------------------------------------------------------
# Safety check: scripts with Windows line endings (CRLF) fail inside Linux with
# confusing errors. Stop early with a clear message instead.
# ---------------------------------------------------------------------------
Dir.glob(File.join(__dir__, "scripts", "*.sh")).each do |f|
  if File.binread(f).include?("\r\n")
    abort "ERROR: #{f} has Windows (CRLF) line endings.\n" \
          "Fix: run 'git add --renormalize .' (uses .gitattributes) or convert the file to LF."
  end
end

cfg          = load_env(File.join(__dir__, "lab.env"))
lab_name     = cfg.fetch("LAB_NAME")
prefix       = cfg.fetch("NETWORK_PREFIX")
worker_count = cfg.fetch("WORKER_COUNT").to_i

# ---------------------------------------------------------------------------
# Build the node list: 1 master + N workers, with IPs computed from lab.env.
# ---------------------------------------------------------------------------
nodes = [{
  name: "k8s-master",
  role: :master,
  ip:   "#{prefix}.#{cfg.fetch('MASTER_IP_SUFFIX')}",
  cpus: cfg.fetch("MASTER_CPUS").to_i,
  mem:  cfg.fetch("MASTER_MEMORY_MB").to_i
}]
(1..worker_count).each do |i|
  nodes << {
    name: "k8s-worker#{i}",
    role: :worker,
    ip:   "#{prefix}.#{cfg.fetch('WORKER_IP_START').to_i + i - 1}",
    cpus: cfg.fetch("WORKER_CPUS").to_i,
    mem:  cfg.fetch("WORKER_MEMORY_MB").to_i
  }
end

Vagrant.configure("2") do |config|
  # --- Image ----------------------------------------------------------------
  config.vm.box = cfg.fetch("BOX_NAME")
  config.vm.box_version = cfg["BOX_VERSION"] unless cfg["BOX_VERSION"].to_s.empty?
  config.vm.box_check_update = false   # do not nag about newer boxes on every 'up'

  # --- Shared folder --------------------------------------------------------
  # This project folder appears inside every VM as /vagrant. The scripts live
  # there, and the master drops the join command + kubeconfig in /vagrant/.cluster
  # so workers (and you) can pick them up.
  config.vm.synced_folder ".", "/vagrant"

  # --- Nodes (the master is defined first, so it is created first) ----------
  nodes.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]

      # NIC #1 is NAT (internet access, added by Vagrant automatically).
      # NIC #2 is host-only: the stable lab IP you SSH / browse to.
      vm.vm.network "private_network", ip: node[:ip]

      vm.vm.provider "virtualbox" do |vb|
        vb.name   = "#{lab_name}-#{node[:name]}"
        vb.cpus   = node[:cpus]
        vb.memory = node[:mem]
        vb.gui    = false
      end

      # ---- Provisioning steps ----------------------------------------------
      # Each step is a separate script in scripts/. They run in this order on
      # the FIRST 'vagrant up'. To re-run a single step later:
      #     vagrant provision k8s-master --provision-with cni
      # (the name after --provision-with is the first argument below)

      # Step 1 - every node: OS tuning, containerd, kubeadm/kubelet/kubectl.
      vm.vm.provision "common", type: "shell",
        inline: "bash /vagrant/scripts/01-common-node.sh #{node[:ip]}"

      if node[:role] == :master
        # Step 2 - master only: create the cluster, publish join command.
        vm.vm.provision "control-plane", type: "shell",
          inline: "bash /vagrant/scripts/02-master-init.sh"
        # Step 3 - master only: install the Calico network plugin.
        vm.vm.provision "cni", type: "shell",
          inline: "bash /vagrant/scripts/03-cni-calico.sh"
      else
        # Step 4 - workers only: join the cluster using the published command.
        vm.vm.provision "join", type: "shell",
          inline: "bash /vagrant/scripts/04-worker-join.sh"
      end
    end
  end
end
