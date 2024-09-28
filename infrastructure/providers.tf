terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.67.0"
    }
}
}

terraform {
  backend "s3" {
    bucket         = "terraform-state-lifi"
    key            = "backend/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "lifi_terraform_state_lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}