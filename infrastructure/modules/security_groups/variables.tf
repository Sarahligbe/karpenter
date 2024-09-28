variable "cluster_name" {
  description = "K8s cluster name"
  type = string
}

variable "vpc_id" {
  description = "ID of VPC"
  type = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block"
  type = string
}