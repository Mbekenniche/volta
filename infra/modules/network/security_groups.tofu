locals {
  secgroup_rules = {

    "k3s_api_cluster" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 6443
      port_range_max = 6443
      remote_group   = "cluster"
      description    = "K3s Kubernetes API access between cluster nodes"
    }
    "k3s_api_bastion" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 6443
      port_range_max = 6443
      remote_group   = "bastion"
      description    = "K3s Kubernetes API access from the bastion."
    }

    "flannel_vxlan" = {
      direction      = "ingress"
      protocol       = "udp"
      port_range_min = 8472
      port_range_max = 8472
      remote_group   = "cluster"
      description    = "Flannel VXLAN overlay traffic between cluster nodes"
    }

    "kubelet" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 10250
      port_range_max = 10250
      remote_group   = "cluster"
      description    = "Kubelet API metrics and logs between cluster nodes"
    }

    "etcd" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 2379
      port_range_max = 2380
      remote_group   = "cluster"
      description    = "Embedded etcd client and peer communication"
    }



    "icmp_cluster" = {
      direction    = "ingress"
      protocol     = "icmp"
      remote_group = "cluster"
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
    "ssh_bastion" = {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 22
      port_range_max = 22
      remote_group   = "bastion"
      description    = "SSH access from the bastion"
    }
    "amphorae_http" = {
      direction        = "ingress"
      protocol         = "tcp"
      port_range_min   = 30080
      port_range_max   = 30080
      remote_ip_prefix = var.subnet_cidr
      description      = "HTTP from the ingress load balancer to the Traefik node port"
    }
    "amphorae_https" = {
      direction        = "ingress"
      protocol         = "tcp"
      port_range_min   = 30443
      port_range_max   = 30443
      remote_ip_prefix = var.subnet_cidr
      description      = "HTTPS from the ingress load balancer to the Traefik node port"
    }
  }

  secgroup_rules_bastion = {
    "ssh_admin" = {
      direction        = "ingress"
      protocol         = "tcp"
      port_range_min   = 22
      port_range_max   = 22
      remote_ip_prefix = var.admin_cidr
      description      = "SSH access from admin CIDR"
    }
    "icmp" = {
      direction        = "ingress"
      protocol         = "icmp"
      remote_ip_prefix = var.admin_cidr
      description      = "ICMP ping from admin CIDR"
    }
    "ssh_cluster" = {
      direction      = "egress"
      protocol       = "tcp"
      port_range_min = 22
      port_range_max = 22
      remote_group   = "cluster"
      description    = "Outbound SSH to the cluster nodes, the only way into them"
    }
    "k3s_cluster" = {
      direction      = "egress"
      protocol       = "tcp"
      port_range_min = 6443
      port_range_max = 6443
      remote_group   = "cluster"
      description    = "Outbound K3s API to the cluster nodes."
    }
    "dns_udp" = {
      direction        = "egress"
      protocol         = "udp"
      port_range_min   = 53
      port_range_max   = 53
      remote_ip_prefix = var.subnet_cidr
      description      = "Outbound DNS over UDP to the resolvers on the subnet"
    }

    "dns_tcp" = {
      direction        = "egress"
      protocol         = "tcp"
      port_range_min   = 53
      port_range_max   = 53
      remote_ip_prefix = var.subnet_cidr
      description      = "Outbound DNS over TCP to the resolvers on the subnet"
    }
    "http" = {
      direction        = "egress"
      protocol         = "tcp"
      port_range_min   = 80
      port_range_max   = 80
      remote_ip_prefix = "0.0.0.0/0"
      description      = "Outbound HTTP for Ubuntu repositories"
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
  name                 = "${var.name_prefix}-secgroup"
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

  remote_group_id = lookup(each.value, "remote_group", null) == "cluster" ? openstack_networking_secgroup_v2.cluster.id : (
    lookup(each.value, "remote_group", null) == "bastion" ? openstack_networking_secgroup_v2.bastion.id : null
  )

  lifecycle {
    precondition {
      condition     = lookup(each.value, "remote_group", null) == "cluster" || lookup(each.value, "remote_group", null) == "bastion" || lookup(each.value, "remote_group", null) == null
      error_message = "Rule ${each.key}: remote_group must be \"cluster\" or \"bastion\"."
    }
    precondition {
      condition     = (lookup(each.value, "remote_group", null) == null) != (lookup(each.value, "remote_ip_prefix", null) == null)
      error_message = "Rule ${each.key}: set exactly one of remote_group and remote_ip_prefix."
    }
  }
}
resource "openstack_networking_secgroup_rule_v2" "egress_all_v4_intra_cluster" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.cluster.id
  remote_group_id   = openstack_networking_secgroup_v2.cluster.id
  description       = "Allow all outbound IPv4 traffic between cluster nodes"
}

resource "openstack_networking_secgroup_v2" "bastion" {
  name                 = "${var.name_prefix}-bastion-secgroup"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "bastion" {
  for_each = local.secgroup_rules_bastion

  security_group_id = openstack_networking_secgroup_v2.bastion.id

  direction = each.value.direction
  ethertype = lookup(each.value, "ethertype", "IPv4")
  protocol  = each.value.protocol

  port_range_min   = lookup(each.value, "port_range_min", null)
  port_range_max   = lookup(each.value, "port_range_max", null)
  remote_ip_prefix = lookup(each.value, "remote_ip_prefix", null)
  description      = lookup(each.value, "description", null)

  remote_group_id = lookup(each.value, "remote_group", null) == "cluster" ? openstack_networking_secgroup_v2.cluster.id : (
    lookup(each.value, "remote_group", null) == "bastion" ? openstack_networking_secgroup_v2.bastion.id : null
  )

  lifecycle {
    precondition {
      condition     = lookup(each.value, "remote_group", null) == "cluster" || lookup(each.value, "remote_group", null) == "bastion" || lookup(each.value, "remote_group", null) == null
      error_message = "Rule ${each.key}: remote_group must be \"cluster\" or \"bastion\"."
    }
    precondition {
      condition     = (lookup(each.value, "remote_group", null) == null) != (lookup(each.value, "remote_ip_prefix", null) == null)
      error_message = "Rule ${each.key}: set exactly one of remote_group and remote_ip_prefix."
    }
  }
}
