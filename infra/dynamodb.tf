# The source table. Three attributes - name, sex, address - with "name" as the
# partition key. On-demand billing means it costs effectively nothing at rest.

resource "aws_dynamodb_table" "records" {
  name         = "${local.name}-records"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"

  # Only key attributes are declared; DynamoDB is schemaless for the rest.
  attribute {
    name = "name"
    type = "S"
  }

  server_side_encryption {
    enabled = true # AWS-managed KMS key
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${local.name}-records"
  }
}

# --------------------------------------------------------------------------- #
# Seed data: five generic records.
# --------------------------------------------------------------------------- #

locals {
  seed_records = {
    "alice-johnson" = {
      name    = "Alice Johnson"
      sex     = "Female"
      address = "123 Maple Street, Springfield, IL 62704, USA"
    }
    "brian-chen" = {
      name    = "Brian Chen"
      sex     = "Male"
      address = "456 Oak Avenue, Portland, OR 97205, USA"
    }
    "carla-mendes" = {
      name    = "Carla Mendes"
      sex     = "Female"
      address = "789 Pine Road, Austin, TX 78701, USA"
    }
    "devon-okafor" = {
      name    = "Devon Okafor"
      sex     = "Non-binary"
      address = "1011 Cedar Lane, Atlanta, GA 30303, USA"
    }
    "elena-petrova" = {
      name    = "Elena Petrova"
      sex     = "Female"
      address = "1213 Birch Boulevard, Denver, CO 80202, USA"
    }
  }
}

resource "aws_dynamodb_table_item" "seed" {
  for_each = local.seed_records

  table_name = aws_dynamodb_table.records.name
  hash_key   = aws_dynamodb_table.records.hash_key

  item = jsonencode({
    name    = { S = each.value.name }
    sex     = { S = each.value.sex }
    address = { S = each.value.address }
  })
}
