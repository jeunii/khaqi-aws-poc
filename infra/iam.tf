# Execution role for the Lambda function. Every permission is scoped to the
# exact resource the application touches - no managed policies, no wildcards.

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    # Confused-deputy guard: only this account's Lambda service may assume it.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name                 = "${local.name}-lambda"
  description          = "Execution role for the ${local.name} Lambda function"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json
  max_session_duration = 3600

  tags = {
    Name = "${local.name}-lambda"
  }
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid    = "ReadSourceTable"
    effect = "Allow"
    actions = [
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.records.arn,
      "${aws_dynamodb_table.records.arn}/index/*",
    ]
  }

  # Required for Lambda to attach the function to the VPC. The service creates
  # and tears down elastic network interfaces in our private subnets using
  # this role.
  statement {
    sid    = "DescribeNetworkResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]
    # These EC2 Describe calls do not support resource-level permissions, so
    # "*" is the only valid value. They are read-only and list metadata.
    resources = ["*"]
  }

  statement {
    sid    = "ManageOwnVpcInterfaces"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = concat(
      ["arn:${local.partition}:ec2:${var.aws_region}:${local.account_id}:network-interface/*"],
      aws_subnet.private[*].arn,
      [aws_security_group.lambda.arn],
    )
  }

  statement {
    sid    = "PublishToOutputQueue"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.output.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name}-lambda"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}
