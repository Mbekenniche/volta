#!/bin/bash

set -euo pipefail

# Paths are written from the root of the repository, wherever the script is run from.
cd "$(dirname "$0")/.."

# Set here, never inherited: the operator's shell may point kubectl at another cluster.
export KUBECONFIG="$HOME/.kube/volta-lab.yaml"

# UTC timestamps: the duration of each phase of make up is read from these lines.
log() {
  printf '[%s] %s\n' "$(date -u +%T)" "$*"
}

wait_for() {  # wait_for <tries> <command...>: run it every 10 s until it succeeds
  local n=$1; shift
  until "$@"; do
    n=$((n - 1))
    [ "$n" -gt 0 ] || { log "gave up waiting for: $*"; return 1; }
    sleep 10
  done
}
