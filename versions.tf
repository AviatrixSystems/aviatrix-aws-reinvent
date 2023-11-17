terraform {
  required_providers {
    aviatrix = {
      source  = "aviatrixsystems/aviatrix"
      version = ">= 3.1.0"
    }
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.25.0"
      configuration_aliases = [aws.us-east-2]
    }
  }
  required_version = ">= 1.5.0"
}
