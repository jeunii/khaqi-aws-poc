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

variable "reserved_concurrency" {
  description = <<-EOT
    Reserved concurrent executions for the function. Use -1 for unreserved.
    Setting a positive value requires the account to retain at least 10
    unreserved executions, so it fails on accounts at the default limit of 10.
  EOT
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrency == -1 || var.reserved_concurrency >= 1
    error_message = "reserved_concurrency must be -1 (unreserved) or a positive integer."
  }
}

variable "log_retention_days" {
  description = <<-EOT
    CloudWatch Logs retention for the function, in days.
    CloudWatch only accepts a fixed set of values; 0 means never expire.
    Note there is no 300: the nearest valid values are 180 and 365.
  EOT
  type        = number
  default     = 365

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
      1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days,
    )
    error_message = <<-EOT
      log_retention_days must be one of the values CloudWatch Logs accepts:
      0 (never expire), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400,
      545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653.
    EOT
  }
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
