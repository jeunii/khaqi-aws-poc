terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Local state is fine for a PoC. For anything shared, uncomment and point at
  # an S3 bucket with a DynamoDB lock table.
  #
  # backend "s3" {
  #   bucket         = "my-tf-state"
  #   key            = "transform-data/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "my-tf-locks"
  #   encrypt        = true
  # }
}
