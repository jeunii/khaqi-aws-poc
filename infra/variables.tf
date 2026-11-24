variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Application name. Used as the prefix for every resource."
  type        = string
  default     = "transform-data"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, 2-31 characters."
  }
}

variable "environment" {
  description = "Deployment environment, e.g. dev, staging, prod."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.environment))
    error_message = "environment must be lowercase alphanumeric, 2-12 characters."
  }
}

variable "additional_tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

# --------------------------------------------------------------------------- #
# Networking
# --------------------------------------------------------------------------- #

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block no smaller than /24."
  }
}

variable "az_count" {
  description = <<-EOT
    Number of availability zones to spread the private subnets across.
    Each AZ adds one SQS interface endpoint ENI, billed hourly.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}

# --------------------------------------------------------------------------- #
# Lambda
# --------------------------------------------------------------------------- #

variable "lambda_memory_mb" {
  description = "Memory allocated to the Lambda function, in MB."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Lambda invocation timeout, in seconds."
  type        = number
  default     = 30
}

variable "lambda_architecture" {
  description = "CPU architecture for the Lambda function."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_architecture)
    error_message = "lambda_architecture must be either arm64 or x86_64."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the function."
  type        = number
  default     = 14
}

variable "log_level" {
  description = "Log level passed to the application."
  type        = string
  default     = "INFO"
}

# --------------------------------------------------------------------------- #
# Container image
# --------------------------------------------------------------------------- #

variable "build_and_push_image" {
  description = <<-EOT
    Build the app/ Dockerfile and push it to ECR during apply.
    Requires Docker and the AWS CLI v2 on the machine running Terraform.
    Set to false if your CI pipeline pushes the image separately.
  EOT
  type        = bool
  default     = true
}

variable "image_tag" {
  description = <<-EOT
    ECR image tag to deploy. Leave null to derive a tag from a hash of the
    application source, so each code change deploys a distinct image.
  EOT
  type        = string
  default     = null
}

# --------------------------------------------------------------------------- #
# SQS
# --------------------------------------------------------------------------- #

variable "sqs_message_retention_seconds" {
  description = "How long SQS keeps an unconsumed message."
  type        = number
  default     = 345600 # 4 days
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout on the output queue."
  type        = number
  default     = 60
}

variable "sqs_max_receive_count" {
  description = "Receives before a message is moved to the dead-letter queue."
  type        = number
  default     = 5
}
