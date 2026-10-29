#!/bin/bash
# The main stack, applied from the exact plan the operator read. The bootstrap stack, with the
# state, the stable address and the backups, is never planned here.
. "$(dirname "$0")/lib.sh"

trap 'rm -f infra/up.tfplan' EXIT

# -detailed-exitcode: 0 is no changes, 2 is changes, anything else an error. Under set -e, a 2
# would end the script before it is read, hence || rc=$?.
rc=0
tofu -chdir=infra plan -input=false -detailed-exitcode -out=up.tfplan || rc=$?
case $rc in
  0) log "infra: no changes" ;;
  2) read -r -p "Apply this plan? Only yes is accepted: " answer
     [ "$answer" = yes ] || { log "infra: not applied"; exit 1; }
     tofu -chdir=infra apply -input=false up.tfplan
     log "infra: applied" ;;
  *) log "infra: the plan failed"; exit "$rc" ;;
esac

# The addresses the next phases read, so that none of them needs the state or its passphrase.
mkdir -p .project/ssh
tofu -chdir=infra output -json > .project/ssh/outputs.json
