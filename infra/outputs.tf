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
