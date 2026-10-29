#!/bin/bash
# Render every Application the way Argo CD does, then validate each object against the schemas
# of the cluster's Kubernetes version. Run from the root of the repository.

set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The cluster's version, from k3s_version in infra/variables.tofu: change both together.
kube_version=1.36.4

# Schemas of the custom resources: Application, ClusterIssuer, ServiceMonitor...
crds='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

for app in cluster/apps/*.yaml; do
  # The source with a chart; the other one only points at this repository's values.
  src='.spec.sources[] | select(.chart)'
  chart=$(yq "$src | .chart" "$app")
  [ -z "$chart" ] && continue   # plain manifests, validated below

  url=$(yq "$src | .repoURL" "$app")
  version=$(yq "$src | .targetRevision" "$app")
  values=$(yq "$src | .helm.valueFiles[0]" "$app")
  values=${values#\$values/}    # Argo CD's name for this repository
  namespace=$(yq '.spec.destination.namespace' "$app")
  release=$(yq '.metadata.name' "$app")   # Argo CD names the release after the Application

  # A repoURL without a scheme is an OCI registry.
  case $url in
    https://*) ref=(--repo "$url" "$chart") ;;
    *)         ref=("oci://$url/$chart") ;;
  esac

  # Pull first: rendering an OCI chart directly, Helm 4 prints "Pulled:" and "Digest:" on stdout.
  helm pull "${ref[@]}" --version "$version" -d "$tmp"
  helm template "$release" "$tmp/$chart-$version.tgz" -n "$namespace" -f "$values" \
    --kube-version "$kube_version" >> "$tmp/rendered.yaml"
done

# CustomResourceDefinition has no schema: skip it by name. Never -ignore-missing-schemas,
# which would let any object without a schema through unchecked.
kubeconform -strict -summary -kubernetes-version "$kube_version" \
  -schema-location default -schema-location "$crds" \
  -skip CustomResourceDefinition \
  "$tmp/rendered.yaml" cluster/apps cluster/argocd/root.yaml \
  cluster/demo cluster/cert-manager/issuers
