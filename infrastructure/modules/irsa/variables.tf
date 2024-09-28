variable "region" {
  description = "AWS region"
  type = string
}

variable "s3_suffix" {
  description = "Suffix for s3 bucket for oidc"
  type = string
  default = "self-managed"
}