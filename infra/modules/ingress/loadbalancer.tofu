data "openstack_networking_floatingip_v2" "ingress" {
  tags = ["volta-ingress"]
}

resource "openstack_lb_loadbalancer_v2" "ingress" {
  name          = "${var.name_prefix}-ingress"
  vip_subnet_id = var.subnet_id
}

resource "openstack_lb_listener_v2" "ingress_http" {
  protocol        = "TCP"
  protocol_port   = 80
  loadbalancer_id = openstack_lb_loadbalancer_v2.ingress.id
}

resource "openstack_lb_listener_v2" "ingress_https" {
  protocol        = "TCP"
  protocol_port   = 443
  loadbalancer_id = openstack_lb_loadbalancer_v2.ingress.id
}

resource "openstack_lb_pool_v2" "ingress_http" {
  protocol    = "PROXY"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.ingress_http.id
}

resource "openstack_lb_pool_v2" "ingress_https" {
  protocol    = "PROXY"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.ingress_https.id
}

resource "openstack_lb_members_v2" "ingress_http" {
  pool_id = openstack_lb_pool_v2.ingress_http.id

  dynamic "member" {
    for_each = var.private_ip_node
    content {
      address       = member.value
      protocol_port = 30080
      subnet_id     = var.subnet_id
    }
  }
}

resource "openstack_lb_members_v2" "ingress_https" {
  pool_id = openstack_lb_pool_v2.ingress_https.id

  dynamic "member" {
    for_each = var.private_ip_node
    content {
      address       = member.value
      protocol_port = 30443
      subnet_id     = var.subnet_id
    }
  }
}

resource "openstack_lb_monitor_v2" "ingress_http" {
  pool_id     = openstack_lb_pool_v2.ingress_http.id
  type        = "TCP"
  delay       = 20
  timeout     = 10
  max_retries = 5
}

resource "openstack_lb_monitor_v2" "ingress_https" {
  pool_id     = openstack_lb_pool_v2.ingress_https.id
  type        = "TCP"
  delay       = 20
  timeout     = 10
  max_retries = 5
}

resource "openstack_networking_floatingip_associate_v2" "ingress" {
  port_id     = openstack_lb_loadbalancer_v2.ingress.vip_port_id
  floating_ip = data.openstack_networking_floatingip_v2.ingress.address
}
