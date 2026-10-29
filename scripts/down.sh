#!/bin/bash
# Destroy the main stack, then what OpenTofu does not know about: the volumes the Cinder CSI
# driver created. The bootstrap stack, with the state, the stable address and the backups, is
# never touched.
. "$(dirname "$0")/lib.sh"

trap 'rm -f infra/down.tfplan' EXIT

# The plan first, so that the name is typed after reading what goes.
tofu -chdir=infra plan -input=false -destroy -out=down.tfplan
read -r -p "Type volta-lab to destroy it: " answer
[ "$answer" = volta-lab ] || { log "down: nothing destroyed"; exit 1; }

# The tunnel leads to a server about to disappear.
pkill -f 'L 127.0.0.1:6443' || true
tofu -chdir=infra apply -input=false down.tfplan
log "down: main stack destroyed"

# The driver sets this metadata on every volume it creates. Each is detached once its server
# is gone, and Cinder deletes a volume only when it is available.
csi_volumes() {
  openstack volume list --long -f json \
    | jq -r '.[] | select(.Properties["cinder.csi.openstack.org/cluster"] == "volta-lab") | .ID'
}
available() {
  [ "$(openstack volume show "$1" -f value -c status)" = available ]
}
for id in $(csi_volumes); do
  wait_for 30 available "$id"
  openstack volume delete "$id"
  log "down: volume $id deleted"
done

# What described the destroyed build. The next make up writes it again.
rm -f "$KUBECONFIG" .project/ssh/outputs.json
rm -rf .project/ssh/keys
log "down: done"
