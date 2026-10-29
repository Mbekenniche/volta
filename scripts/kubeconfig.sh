#!/bin/bash
# The cluster's admin kubeconfig, the tunnel to its API through the bastion, then three nodes
# Ready. The kubeconfig points at https://127.0.0.1:6443, the local end of the tunnel.
. "$(dirname "$0")/lib.sh"

ssh_lab() { ssh -F .project/ssh/config -o ConnectTimeout=5 "$@"; }

# k3s writes it once it has started, readable by root only.
log "kubeconfig: waiting for k3s on volta-lab-server-1"
wait_for 30 ssh_lab volta-lab-server-1 sudo test -f /etc/rancher/k3s/k3s.yaml

# rm first: a redirection keeps the mode of an existing file, umask 077 gives a new one 0600.
mkdir -p "$(dirname "$KUBECONFIG")"
rm -f "$KUBECONFIG"
(umask 077; ssh_lab volta-lab-server-1 sudo cat /etc/rancher/k3s/k3s.yaml > "$KUBECONFIG")

# A tunnel already open may lead to the address of a destroyed server: always open a new one.
# Without ExitOnForwardFailure, a port still busy leaves ssh in the background, exit code 0,
# and no tunnel.
pkill -f 'L 127.0.0.1:6443' || true
sleep 1
server=$(jq -r '.private_ip_node.value["volta-lab-server-1"]' .project/ssh/outputs.json)
ssh -F .project/ssh/config -o ExitOnForwardFailure=yes -f -N \
  -L "127.0.0.1:6443:$server:6443" volta-bastion

# Not kubectl wait node --all: it only waits for the nodes already registered, and servers 2
# and 3 register after server 1.
three_ready() {
  [ "$(kubectl get nodes --no-headers 2> /dev/null | grep -cw Ready)" -eq 3 ]
}
log "kubeconfig: waiting for three nodes Ready"
wait_for 60 three_ready
log "kubeconfig: three nodes Ready"
