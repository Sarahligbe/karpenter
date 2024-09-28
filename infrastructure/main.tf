data "aws_ssm_parameter" "kubeconfig" {
  name            = "/k8s/kubeconfig"
  with_decryption = true
}

# Decode the base64-encoded kubeconfig
locals {
  kubeconfig = base64decode(data.aws_ssm_parameter.kubeconfig.value)
}

# Write kubeconfig to a local file
resource "local_file" "kubeconfig" {
  content  = local.kubeconfig
  filename = "${path.module}/kubeconfig"
}

module "networking" {
  source = "./modules/networking"

  cluster_name           = var.cluster_name
  vpc_cidr_block         = var.vpc_cidr_block
  private_subnet_count   = var.private_subnet_count
  public_subnet_count    = var.public_subnet_count
  eice_sg_id             = module.security_groups.eice_sg_id
}

module "security_groups" {
  source = "./modules/security_groups"

  cluster_name    = var.cluster_name
  vpc_id          = module.networking.vpc_id
  vpc_cidr_block  = var.vpc_cidr_block
}

module "irsa" {
  source = "./modules/irsa"

  region = var.region
  s3_suffix = var.s3_suffix
}

module "iam" {
  source = "./modules/iam"

  k8s_join_command_arn = module.instances.k8s_join_command_arn
  irsa_private_key_arn = module.irsa.irsa_private_key_arn
  irsa_public_key_arn = module.irsa.irsa_public_key_arn
  oidc_provider_arn   = module.irsa.oidc_provider_arn
  oidc_provider       = module.irsa.oidc_provider
  cluster_name        = var.cluster_name

  depends_on           = [module.irsa]
}

module "instances" {
  source = "./modules/instances"

  cluster_name       = var.cluster_name
  region             = var.region
  instance_type      = var.instance_type
  controlplane_count = var.controlplane_count
  worker_count       = var.worker_count
  private_subnet_ids = module.networking.private_subnet_ids
  controlplane_sg_id = module.security_groups.controlplane_sg_id
  worker_sg_id       = module.security_groups.worker_sg_id
  key_name           = var.key_name #provide the key name of an existing ssh key you own
  ssm_profile_name   = module.iam.ssm_profile_name
  discovery_bucket_name = module.irsa.discovery_bucket_name
  aws_lb_role_arn       = module.iam.aws_lb_role_arn
  dns_role_arn       = module.iam.dns_role_arn
  domain            = var.domain
  grafana_passwd    = var.grafana_passwd
  cert_arn          = module.cluster_addons.cert_arn
  karpenter_controller_role_arn = module.iam.karpenter_controller_role_arn
  karpenter_instance_role_arn = module.iam.karpenter_instance_role_arn

  depends_on         = [module.networking, module.irsa]
}

module "cluster_addons" {
  source = "./modules/addons"

  domain            = var.domain
}