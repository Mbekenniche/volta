#!/bin/bash
# The known hosts and the SSH configuration of this build. A host key belongs to an instance,
# not to an address: it is read once, while the instance is new, from its console log (Nova
# keeps only the end of it), and kept under the instance's ID in .project/ssh/keys/.
. "$(dirname "$0")/lib.sh"

dir=.project/ssh
mkdir -p "$dir/keys"

addr() {  # addr <instance name>: its address, from the outputs
  jq -r --arg n "$1" '
    if $n == "volta-lab-bastion" then .public_ip_bastion.value
    else .private_ip_node.value[$n] end' "$dir/outputs.json"
}

# cloud-init prints the host keys at the end of the first boot. A here-string, not a pipe:
# grep -q stops at the first match, and under pipefail the SIGPIPE of the command still
# writing would fail the test.
keys_printed() {
  grep -q 'END SSH HOST KEY KEYS' <<< "$(openstack console log show "$1")"
}

: > "$dir/known_hosts.new"
for name in volta-lab-bastion volta-lab-server-1 volta-lab-server-2 volta-lab-server-3; do
  id=$(openstack server show "$name" -f value -c id)
  if [ ! -s "$dir/keys/$id" ]; then
    log "ssh-config: $name is new, waiting for its host keys on the console"
    wait_for 60 keys_printed "$name"
    console=$(openstack console log show "$name")
    key=$(sed -n '/BEGIN SSH HOST KEY KEYS/,/END SSH HOST KEY KEYS/p' <<< "$console" \
      | grep -o 'ssh-ed25519 [A-Za-z0-9+/=]*' || true)
    [ -n "$key" ] || { log "ssh-config: no ED25519 host key on the console of $name"; exit 1; }
    # Both come from the same log, served by the authenticated API: this catches a key cut or
    # garbled on the way, before it is trusted for good.
    fp=$(ssh-keygen -lf - <<< "$key" | awk '{print $2}')
    grep -q "$fp .*(ED25519)" <<< "$console" \
      || { log "ssh-config: the fingerprint of $name does not match its key"; exit 1; }
    printf '%s\n' "$key" > "$dir/keys/$id"
  fi
  printf '%s %s\n' "$(addr "$name")" "$(< "$dir/keys/$id")" >> "$dir/known_hosts.new"
done
mv "$dir/known_hosts.new" "$dir/known_hosts"

# Rewritten on every run: the addresses change with every build.
cat > "$dir/config" <<EOF
# Written by scripts/ssh-config.sh for the current build. Usage: ssh -F .project/ssh/config <host>
# With -F, ~/.ssh/config is not read, and the jump to the bastion uses this same file.

Host *
  User ubuntu
  IdentityFile ~/.ssh/volta_lab
  IdentitiesOnly yes
  UserKnownHostsFile $PWD/$dir/known_hosts
  StrictHostKeyChecking yes
  HostKeyAlgorithms ssh-ed25519
  ForwardAgent no
  ServerAliveInterval 30
  ServerAliveCountMax 3

Host volta-bastion
  HostName $(addr volta-lab-bastion)
EOF
for n in 1 2 3; do
  printf '\nHost volta-lab-server-%s\n  HostName %s\n  ProxyJump volta-bastion\n' \
    "$n" "$(addr "volta-lab-server-$n")"
done >> "$dir/config"
log "ssh-config: known hosts and configuration written"
