output "network_id" {
  description = "ID of the internal private network hosting the cluster."
  value       = openstack_networking_network_v2.cluster.id
}

output "subnet_id" {
  description = "Subnet the cluster nodes attach to."
  value       = openstack_networking_subnet_v2.cluster.id
}

output "security_group_id" {
  description = "ID of the security group applied to the cluster nodes."
  value       = openstack_networking_secgroup_v2.cluster.id
}

output "keypair_name" {
  description = "Name of the SSH keypair injected into instances for administrative access."
  value       = openstack_compute_keypair_v2.cluster.name
}
