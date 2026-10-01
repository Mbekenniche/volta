output "keypair_name" {
  description = "Name of the SSH keypair injected into instances for administrative access."
  value       = openstack_compute_keypair_v2.cluster.name
}

output "public_ip_bastion" {
  description = "Public address of the bastion, the only public address of the platform."
  value       = openstack_networking_floatingip_v2.bastion.address
}

output "private_ip_node" {
  description = "Private address of each cluster node, keyed by instance name."
  value = {
    for k, v in var.node_map : openstack_compute_instance_v2.nodes[k].name => openstack_networking_port_v2.nodes[k].all_fixed_ips[0]
  }

}
