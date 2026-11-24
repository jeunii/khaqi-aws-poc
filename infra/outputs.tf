output "lambda_function_name" {
  description = "Name of the transform-data Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "ARN of the transform-data Lambda function."
  value       = aws_lambda_function.this.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.lambda.arn
}

output "vpc_id" {
  description = "ID of the VPC the function runs in."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnets the function's ENIs live in."
  value       = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  description = "Security group attached to the function."
  value       = aws_security_group.lambda.id
}

output "vpc_endpoint_ids" {
  description = "VPC endpoints the function uses to reach AWS services."
  value = {
    dynamodb = aws_vpc_endpoint.dynamodb.id
    sqs      = aws_vpc_endpoint.sqs.id
  }
}

output "schedule_rule_name" {
  description = "EventBridge rule invoking the function, or null if disabled."
  value       = try(aws_cloudwatch_event_rule.schedule[0].name, null)
}

output "schedule_expression" {
  description = "Active schedule expression, or null if disabled."
  value       = try(aws_cloudwatch_event_rule.schedule[0].schedule_expression, null)
}

output "dynamodb_table_name" {
  description = "Name of the source DynamoDB table."
  value       = aws_dynamodb_table.records.name
}

output "sqs_queue_url" {
  description = "URL of the output SQS queue."
  value       = aws_sqs_queue.output.url
}

output "sqs_queue_arn" {
  description = "ARN of the output SQS queue."
  value       = aws_sqs_queue.output.arn
}

output "sqs_dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "ecr_repository_url" {
  description = "ECR repository holding the Lambda image."
  value       = aws_ecr_repository.this.repository_url
}

output "image_uri" {
  description = "Container image currently deployed to Lambda."
  value       = local.image_uri
}

output "log_group_name" {
  description = "CloudWatch log group for the function."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "invoke_command" {
  description = "Copy-paste command to trigger the function."
  value       = "aws lambda invoke --region ${var.aws_region} --function-name ${aws_lambda_function.this.function_name} --cli-binary-format raw-in-base64-out --payload '{}' /tmp/transform-data-out.json && cat /tmp/transform-data-out.json"
}

output "receive_command" {
  description = "Copy-paste command to read the message off the queue."
  value       = "aws sqs receive-message --region ${var.aws_region} --queue-url ${aws_sqs_queue.output.url} --max-number-of-messages 1 --wait-time-seconds 5"
}
