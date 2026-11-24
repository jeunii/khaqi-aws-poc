# Scheduled trigger for the function.
#
# EventBridge rules invoke Lambda asynchronously. On failure Lambda retries
# twice on its own before the event is discarded, so a transient DynamoDB or
# SQS error will not lose a run, but a persistent one fails silently unless
# you add an alarm. See the retry_policy below and the note in the README.

resource "aws_cloudwatch_event_rule" "schedule" {
  count = var.schedule_enabled ? 1 : 0

  name                = "${local.name}-schedule"
  description         = "Invokes ${local.name} on a schedule (${var.schedule_expression})"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"

  tags = {
    Name = "${local.name}-schedule"
  }
}

resource "aws_cloudwatch_event_target" "lambda" {
  count = var.schedule_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.schedule[0].name
  target_id = "${local.name}-lambda"
  arn       = aws_lambda_function.this.arn

  # The handler ignores its event, but sending a marker makes it obvious in
  # the logs whether a run came from the schedule or from a manual invoke.
  input = jsonencode({
    source = "eventbridge-schedule"
    rule   = "${local.name}-schedule"
  })

  # Give up rather than pile up: a run is superseded by the next hourly one.
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 2
  }
}

# EventBridge is a service principal, so it needs resource-based permission on
# the function. Scoped to this one rule.
resource "aws_lambda_permission" "eventbridge" {
  count = var.schedule_enabled ? 1 : 0

  statement_id  = "AllowInvokeFromEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}
