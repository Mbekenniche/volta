moved {
  from = openstack_networking_network_v2.cluster
  to   = module.network.openstack_networking_network_v2.cluster
}

moved {
  from = openstack_networking_router_interface_v2.cluster
  to   = module.network.openstack_networking_router_interface_v2.cluster
}

moved {
  from = openstack_networking_router_v2.cluster
  to   = module.network.openstack_networking_router_v2.cluster
}

moved {
  from = openstack_networking_secgroup_rule_v2.cluster
  to   = module.network.openstack_networking_secgroup_rule_v2.cluster
}

moved {
  from = openstack_networking_secgroup_rule_v2.egress_all_v4_intra_cluster
  to   = module.network.openstack_networking_secgroup_rule_v2.egress_all_v4_intra_cluster
}

moved {
  from = openstack_networking_secgroup_v2.cluster
  to   = module.network.openstack_networking_secgroup_v2.cluster
}

moved {
  from = openstack_networking_subnet_v2.cluster
  to   = module.network.openstack_networking_subnet_v2.cluster
}
