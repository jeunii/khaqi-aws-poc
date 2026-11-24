# Private-only VPC for the Lambda function.
#
# There is deliberately no internet gateway and no NAT gateway. The function
# reaches DynamoDB through a gateway endpoint and SQS through an interface
# endpoint, so its traffic to both services stays on the AWS network and never
# transits the public internet.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # One /24 per AZ, carved out of the VPC CIDR.
  private_subnet_cidrs = [
    for index in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, index + 1)
  ]
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both are required for the SQS interface endpoint's private DNS to work.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# The default security group allows all intra-group traffic. Terraform adopts
# it and strips every rule, so nothing can accidentally rely on it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-default-DO-NOT-USE"
  }
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # No public addressing: these subnets have no route to the internet.
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-${local.azs[count.index]}"
    Tier = "private"
  }
}

# A single route table is enough: every subnet has the same (empty) routing,
# plus the DynamoDB gateway endpoint prefix list route added below.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --------------------------------------------------------------------------- #
# Security groups
# --------------------------------------------------------------------------- #

resource "aws_security_group" "lambda" {
  name_prefix = "${local.name}-lambda-"
  description = "Egress-only group for the ${local.name} Lambda function"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name}-lambda"
  }
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name}-vpce-"
  description = "Interface VPC endpoints for ${local.name}"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name}-vpce"
  }
}

# The function has no inbound rules at all, and only two egress paths.

resource "aws_vpc_security_group_egress_rule" "lambda_to_endpoints" {
  description                  = "HTTPS to interface endpoints (SQS)"
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# Gateway endpoint traffic is routed, not proxied, so it is matched by the
# service's managed prefix list rather than a security group.
resource "aws_vpc_security_group_egress_rule" "lambda_to_dynamodb" {
  description       = "HTTPS to DynamoDB via the gateway endpoint"
  security_group_id = aws_security_group.lambda.id
  prefix_list_id    = aws_vpc_endpoint.dynamodb.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_lambda" {
  description                  = "HTTPS from the Lambda function"
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# --------------------------------------------------------------------------- #
# VPC endpoints
# --------------------------------------------------------------------------- #

# Gateway endpoint: free, and attaches to the route table rather than an ENI.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  # Anti-exfiltration: this endpoint can only reach our own table, so a
  # compromised function cannot push data into a table in another account.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "OnlyThisFunctionOnlyThisTable"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.lambda.arn }
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:DescribeTable",
        ]
        Resource = [
          aws_dynamodb_table.records.arn,
          "${aws_dynamodb_table.records.arn}/index/*",
        ]
      },
    ]
  })

  tags = {
    Name = "${local.name}-dynamodb"
  }
}

# Interface endpoint: one ENI per subnet, billed hourly.
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  # Same anti-exfiltration reasoning: only our queue, only our role.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "OnlyThisFunctionOnlyThisQueue"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.lambda.arn }
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = aws_sqs_queue.output.arn
      },
    ]
  })

  tags = {
    Name = "${local.name}-sqs"
  }
}
