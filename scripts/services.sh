#!/bin/bash
# Argo CD, then the root Application, which brings everything else from main on GitHub. Done
# once the demo answers over HTTPS.
. "$(dirname "$0")/lib.sh"

# --wait: Helm 4 then waits for the objects to be ready, not only for its hooks.
helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd --version 10.10.2 \
  -n argocd --create-namespace -f cluster/argocd/values.yaml --wait --timeout 10m
kubectl apply -f cluster/argocd/root.yaml

# The Lua health check in cluster/argocd/values.yaml gives the root the health of its
# children: a Healthy root means every Application is. Polled rather than kubectl wait, which
# would stop on the first error of a tunnel that blinks.
root_ready() {
  [ "$(kubectl -n argocd get application app-of-apps \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2> /dev/null)" = Synced/Healthy ]
}
log "services: waiting for the root Application, Synced and Healthy"
wait_for 120 root_ready

# -f: an HTTP error fails curl. No -k: an invalid certificate fails it too.
log "services: waiting for the demo over HTTPS"
wait_for 30 curl -fsS -m 10 -o /dev/null https://demo.volta.koveolabs.com/
log "services: the demo answers"
