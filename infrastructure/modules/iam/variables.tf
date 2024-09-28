variable "k8s_join_command_arn" {
  description = "ARN for the k8s join command"
  type = string
}

variable "irsa_private_key_arn" {
  description = "ARN for the irsa private arn"
  type = string
}

variable "irsa_public_key_arn" {
  description = "ARN for the irsa public arn"
  type = string
}

variable "oidc_provider_arn" {
  description = "ARN for the oidc provider"
  type = string
}

variable "oidc_provider" {
  description = "the oidc provider"
  type = string
}

variable "cluster_name" {
  description = "K8s cluster name"
  type = string
}

