locals {
  secgroup_rules = {
    "ssh" = {
      direction        = "ingress"
      protocol         = "tcp"
      port_range_min   = 22
      port_range_max   = 22
      remote_ip_prefix = var.admin_cidr
      description      = "SSH access from admin CIDR"
    }

    "k3s_api_admin" = {
      direction        = "ingress"
      protocol         = "tcp"
      port_range_min   = 6443
      port_range_max   = 6443
      remote_ip_prefix = var.admin_cidr
      description      = "K3s Kubernetes API access from admin CIDR"
    }

    "k3s_api_cluster" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 6443
      port_range_max = 6443
      remote_group   = true
      description    = "K3s Kubernetes API access between cluster nodes"
    }

    "flannel_vxlan" = {
      direction      = "ingress"
      protocol       = "udp"
      port_range_min = 8472
      port_range_max = 8472
      remote_group   = true
      description    = "Flannel VXLAN overlay traffic between cluster nodes"
    }

    "kubelet" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 10250
      port_range_max = 10250
      remote_group   = true
      description    = "Kubelet API metrics and logs between cluster nodes"
    }

    "etcd" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 2379
      port_range_max = 2380
      remote_group   = true
      description    = "Embedded etcd client and peer communication"
    }

    "icmp_admin" = {
      direction        = "ingress"
      protocol         = "icmp"
      remote_ip_prefix = var.admin_cidr
      description      = "ICMP ping from admin CIDR"
    }

    "icmp_cluster" = {
      direction    = "ingress"
      protocol     = "icmp"
      remote_group = true
      description  = "ICMP ping between cluster nodes"
    }

    "dns_udp" = {
      direction        = "egress"
      protocol         = "udp"
      port_range_min   = 53
      port_range_max   = 53
      remote_ip_prefix = "0.0.0.0/0"
      description      = "Outbound DNS resolution over UDP"
    }

    "dns_tcp" = {
      direction        = "egress"
      protocol         = "tcp"
      port_range_min   = 53
      port_range_max   = 53
      remote_ip_prefix = "0.0.0.0/0"
      description      = "Outbound DNS resolution and zone transfers over TCP"
    }

    "http" = {
      direction        = "egress"
      protocol         = "tcp"
      port_range_min   = 80
      port_range_max   = 80
      remote_ip_prefix = "0.0.0.0/0"
      description      = "Outbound HTTP for package repositories and downloads"
    }

    "https" = {
      direction        = "egress"
      protocol         = "tcp"
      port_range_min   = 443
      port_range_max   = 443
      remote_ip_prefix = "0.0.0.0/0"
      description      = "Outbound HTTPS for container registries and secure downloads"
    }

    "ntp" = {
      direction        = "egress"
      protocol         = "udp"
      port_range_min   = 123
      port_range_max   = 123
      remote_ip_prefix = "0.0.0.0/0"
      description      = "Outbound NTP time synchronization over UDP"
    }
  }
}


resource "openstack_networking_secgroup_v2" "cluster" {
  name                 = "${local.name_prefix}-secgroup"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "cluster" {
  for_each = local.secgroup_rules

  security_group_id = openstack_networking_secgroup_v2.cluster.id

  direction = each.value.direction
  ethertype = lookup(each.value, "ethertype", "IPv4")
  protocol  = each.value.protocol

  port_range_min   = lookup(each.value, "port_range_min", null)
  port_range_max   = lookup(each.value, "port_range_max", null)
  remote_ip_prefix = lookup(each.value, "remote_ip_prefix", null)
  description      = lookup(each.value, "description", null)

  remote_group_id = lookup(each.value, "remote_group", false) ? openstack_networking_secgroup_v2.cluster.id : null
}
resource "openstack_networking_secgroup_rule_v2" "egress_all_v4_intra_cluster" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.cluster.id
  remote_group_id   = openstack_networking_secgroup_v2.cluster.id
  description       = "Allow all outbound IPv4 traffic between cluster nodes"
}
