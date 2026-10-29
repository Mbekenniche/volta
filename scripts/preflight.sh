#!/bin/bash
# Stop within a second rather than minutes into an apply: the tools, the variables OpenTofu
# reads, the files the Secrets come from, and the address of this workstation.
. "$(dirname "$0")/lib.sh"

for tool in tofu openstack kubectl helm jq dig; do
  command -v "$tool" > /dev/null || { log "preflight: $tool is not installed"; exit 1; }
done

# The cloud, the S3 key of the state, the passphrase of the state. ${!v} reads the variable
# whose name is in v.
for v in OS_CLOUD AWS_PROFILE TF_VAR_encryption_passphrase; do
  [ -n "${!v:-}" ] || { log "preflight: $v is not set"; exit 1; }
done

for f in cloud.conf grafana-admin-password velero-credentials velero-repo-password; do
  [ -s "$HOME/.config/volta/$f" ] || { log "preflight: ~/.config/volta/$f is missing"; exit 1; }
done

# Only admin_cidr reaches the bastion: from another address, SSH would hang two phases later.
# admin_cidr is never changed here: that is a plan to read, not a side effect.
ip=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
cidr=$(sed -n 's/^admin_cidr *= *"\(.*\)"/\1/p' infra/terraform.tfvars)
if [ "$ip/32" != "$cidr" ]; then
  log "preflight: this workstation is $ip, admin_cidr in infra/terraform.tfvars is $cidr"
  exit 1
fi
log "preflight: ok"
