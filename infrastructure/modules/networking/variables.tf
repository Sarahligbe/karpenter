variable "cluster_name" {
  description = "K8s cluster name"
  type = string
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

variable "eice_sg_id" {
  description = "EC2 instance connect security group ID"
  type = string
}