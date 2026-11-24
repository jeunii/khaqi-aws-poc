provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags,
  )

  app_dir = abspath("${path.module}/../app")

  # Content-addressed image tag: any change to the app source produces a new
  # tag, which in turn makes Lambda pick up the new image on apply.
  source_hash = substr(sha256(join("", [
    filesha256("${path.module}/../app/app.py"),
    filesha256("${path.module}/../app/Dockerfile"),
    filesha256("${path.module}/../app/requirements.txt"),
  ])), 0, 12)

  image_tag = coalesce(var.image_tag, local.source_hash)
  image_uri = "${aws_ecr_repository.this.repository_url}:${local.image_tag}"

  lambda_platform = var.lambda_architecture == "arm64" ? "linux/arm64" : "linux/amd64"
}
