resource "aws_security_group" "k8s_worker_node" {
  name        = "k8s_workers_${var.cluster_name}"
  description = "Worker node security group"
  vpc_id      = var.vpc_id

  tags = {
    Name                                        = "${var.cluster_name}_nodes"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery" = var.cluster_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "worker_ing1" {
  security_group_id = aws_security_group.k8s_worker_node.id
  description = "Kubelet API, Kube-scheduler, Kube-controller-manager, Read-Only Kubelet API, Kubelet health"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 10248
  ip_protocol = "tcp"
  to_port     = 10260
}

resource "aws_vpc_security_group_ingress_rule" "worker_ing2" {
  security_group_id = aws_security_group.k8s_worker_node.id
  description = "Node Services"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 30000
  ip_protocol = "tcp"
  to_port     = 32767
}

resource "aws_vpc_security_group_ingress_rule" "worker_ing3" {
  security_group_id = aws_security_group.k8s_worker_node.id
  description = "Connection via ec2 instance connect endpoint"

  referenced_security_group_id = aws_security_group.instance_connect_endpoint.id
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "worker_ing4" {
  security_group_id = aws_security_group.k8s_worker_node.id
  description = "BGP peering for calico"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 179
  ip_protocol = "tcp"
  to_port     = 179
}

resource "aws_vpc_security_group_ingress_rule" "worker_ing5" {
  security_group_id = aws_security_group.k8s_worker_node.id
  description = "IP-IP protocol"

  cidr_ipv4   = var.vpc_cidr_block
  ip_protocol = "4"
}

resource "aws_vpc_security_group_egress_rule" "worker_eg" {
  security_group_id = aws_security_group.k8s_worker_node.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "k8s_controlplane_node" {
  name        = "k8s_controlplanes_${var.cluster_name}"
  description = "controlplane node security group"
  vpc_id      = var.vpc_id
  tags = {
    Name                                        = "${var.cluster_name}_nodes"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing1" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "API Server"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 6443
  ip_protocol = "tcp"
  to_port     = 6443
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing2" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "Kubelet API, Kube-scheduler, Kube-controller-manager, Read-Only Kubelet API, Kubelet health"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 10248
  ip_protocol = "tcp"
  to_port     = 10260
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing3" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "Node Services"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 30000
  ip_protocol = "tcp"
  to_port     = 32767
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing4" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "ETCD Server Client API"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 2379
  ip_protocol = "tcp"
  to_port     = 2380
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing5" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "Connection via ec2 instance connect endpoint"

  referenced_security_group_id = aws_security_group.instance_connect_endpoint.id
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing6" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "BGP peering for calico"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 179
  ip_protocol = "tcp"
  to_port     = 179
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_ing7" {
  security_group_id = aws_security_group.k8s_controlplane_node.id
  description = "IP-IP protocol"

  cidr_ipv4   = var.vpc_cidr_block
  ip_protocol = "4"
}

resource "aws_vpc_security_group_egress_rule" "controlplane_eg" {
  security_group_id = aws_security_group.k8s_controlplane_node.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "instance_connect_endpoint" {
  name        = "instance_connect_${var.cluster_name}"
  description = "EC2 instance connect security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.cluster_name}_eice"
  }
}

resource "aws_vpc_security_group_egress_rule" "eice_ing" {
  security_group_id = aws_security_group.instance_connect_endpoint.id
  description = "SSH Access for EIC endpoint"

  cidr_ipv4   = var.vpc_cidr_block
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}