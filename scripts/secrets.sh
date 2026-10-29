#!/bin/bash
# The four Secrets Argo CD does not manage, from ~/.config/volta/. Before Argo CD: the Cinder CSI
# driver does not start without its own, and Velero, finding no repository password, would
# create one with the default value, which cannot open the existing repository in Swift.
. "$(dirname "$0")/lib.sh"

src="$HOME/.config/volta"

# Built locally, applied server side: a client-side apply would copy the whole object, the
# Secret's value included, into the last-applied-configuration annotation.
ssa() { kubectl apply --server-side -f -; }

for ns in monitoring velero; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | ssa
done

kubectl -n kube-system create secret generic cinder-csi-cloud-config \
  --from-file=cloud.conf="$src/cloud.conf" --dry-run=client -o yaml | ssa
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-file=admin-password="$src/grafana-admin-password" \
  --dry-run=client -o yaml | ssa
kubectl -n velero create secret generic velero-credentials \
  --from-file=cloud="$src/velero-credentials" --dry-run=client -o yaml | ssa
kubectl -n velero create secret generic velero-repo-credentials \
  --from-file=repository-password="$src/velero-repo-password" --dry-run=client -o yaml | ssa
log "secrets: applied"
