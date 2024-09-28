variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.19.0.0/16"
}

variable "private_subnet_count" {
  description = "Number of private subnets to create"
  type        = number
  default     = 2
}

variable "public_subnet_count" {
  description = "Number of public subnets to create"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for Kubernetes nodes"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
}

variable "controlplane_count" {
  description = "Number of controlplane nodes to provision"
  type        = string
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = string
  default     = 1
}

variable "s3_suffix" {
  description = "Suffix for s3 bucket for oidc"
  type = string
  default = "self-managed"
}

variable "domain" {
  description = "Domain name"
  type = string
}

variable "grafana_passwd" {
  description = "Grafana password"
  type = string
}