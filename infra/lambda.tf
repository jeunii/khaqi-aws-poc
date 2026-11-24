# Build and push the container image, then deploy it as a Lambda function.

resource "null_resource" "image" {
  count = var.build_and_push_image ? 1 : 0

  # Re-runs whenever the application source or the target tag changes.
  triggers = {
    source_hash = local.source_hash
    image_uri   = local.image_uri
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/scripts/build_and_push.sh"

    environment = {
      AWS_REGION     = var.aws_region
      ACCOUNT_ID     = local.account_id
      REPOSITORY_URL = aws_ecr_repository.this.repository_url
      IMAGE_TAG      = local.image_tag
      BUILD_CONTEXT  = local.app_dir
      PLATFORM       = local.lambda_platform
    }
  }

  depends_on = [aws_ecr_repository.this]
}

# Created explicitly so retention is managed and the IAM policy can scope to it.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/aws/lambda/${local.name}"
  }
}

resource "aws_lambda_function" "this" {
  function_name = local.name
  description   = "Reads records from DynamoDB, transforms them to JSON, ships them to SQS"
  role          = aws_iam_role.lambda.arn

  package_type  = "Image"
  image_uri     = local.image_uri
  architectures = [var.lambda_architecture]

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  # One in-flight invocation at a time: the whole table is read every run, so
  # concurrent runs would just publish duplicate documents.
  reserved_concurrent_executions = 1

  # Private subnets with no route to the internet. DynamoDB and SQS are
  # reached over VPC endpoints; see vpc.tf.
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.records.name
      QUEUE_URL  = aws_sqs_queue.output.url
      LOG_LEVEL  = var.log_level
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  depends_on = [
    null_resource.image,
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = {
    Name = local.name
  }
}
