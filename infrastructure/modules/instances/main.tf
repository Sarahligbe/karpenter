data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_key_pair" "main" {
  filter {
    name   = "key-name"
    values = [var.key_name]
  }
}

resource "aws_ssm_parameter" "k8s_join_command" {
  name        = "/k8s/join-command"
  description = "Kubernetes cluster join command"
  type        = "SecureString"
  value       = "placeholder"  # This will be updated dynamically using the userdata script

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "setup_common" {
  name  = "/scripts/setup_common"
  description = "Script to be used to install common config in the nodes"
  type  = "String"
  value = file("${path.module}/setup_common.sh")
}

resource "aws_instance" "controlplane" {
  count                  = var.controlplane_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.controlplane_sg_id]
  key_name               = data.aws_key_pair.main.key_name
  source_dest_check      = false
  iam_instance_profile   = var.ssm_profile_name

  user_data = templatefile("${path.module}/controlplane_userdata.sh", {node_type = "controlplane", region = "${var.region}", discovery_bucket_name = "${var.discovery_bucket_name}", cluster_name = "${var.cluster_name}", karpenter_controller_role_arn = "${var.karpenter_controller_role_arn}", karpenter_instance_role_arn = "${var.karpenter_instance_role_arn}", ami_id = data.aws_ami.ubuntu.id})

  tags = {
    Name = "k8s-controlplane-${count.index + 1}"
  }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[(count.index + 1) % length(var.private_subnet_ids)] 
  vpc_security_group_ids = [var.worker_sg_id]
  key_name               = data.aws_key_pair.main.key_name
  source_dest_check      = false
  iam_instance_profile   = var.ssm_profile_name

  user_data = templatefile("${path.module}/worker_userdata.sh", {node_type = "worker", region = "${var.region}", discovery_bucket_name = "${var.discovery_bucket_name}", cluster_name = "${var.cluster_name}", aws_lb_role_arn ="${var.aws_lb_role_arn}", domain = "${var.domain}", cert_arn = "${var.cert_arn}", grafana_passwd = "${var.grafana_passwd}", dns_role_arn = "${var.dns_role_arn}", karpenter_controller_role_arn = "${var.karpenter_controller_role_arn}", karpenter_instance_role_arn = "${var.karpenter_instance_role_arn}", ami_id = data.aws_ami.ubuntu.id})

  tags = {
    Name = "k8s-worker-${count.index + 1}"
  }

  depends_on = [aws_instance.controlplane]
}