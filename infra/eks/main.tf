terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state deliberately used here: this cluster is a one-off demo
  # resource (stand up -> verify ArgoCD/Grafana -> document -> destroy in
  # the same session), unlike the longer-lived Terraform-Scripts modules
  # which use a remote S3 backend.
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}
