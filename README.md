# transform-data

A Lambda function that reads records from DynamoDB, transforms them into a
single JSON document, and ships that document to SQS.

```
┌──────────────┐      Scan       ┌────────────────────┐      SendMessage      ┌──────────────┐
│  DynamoDB    │ ◀────────────── │  Lambda            │ ────────────────────▶ │  SQS         │
│  5 records   │                 │  (container image) │                       │  + DLQ       │
│  name/sex/   │                 │  transform-data    │                       │              │
│  address     │                 └────────────────────┘                       └──────────────┘
└──────────────┘                        ▲
                                        │ image pull
                                   ┌────┴─────┐
                                   │   ECR    │
                                   └──────────┘
```

## Layout

| Path | Contents |
| --- | --- |
| [app/app.py](app/app.py) | The Lambda handler: extract, transform, load |
| [app/Dockerfile](app/Dockerfile) | Lambda container image, Python 3.13 base |
| [app/requirements.txt](app/requirements.txt) | Pinned Python dependencies |
| [infra/](infra/) | Terraform for every AWS resource |
| [infra/scripts/build_and_push.sh](infra/scripts/build_and_push.sh) | Builds and pushes the image during `terraform apply` |

## What gets created

- **DynamoDB table** `transform-data-dev-records` — on-demand, encrypted,
  point-in-time recovery on, seeded with 5 records (`name`, `sex`, `address`).
- **SQS queue** `transform-data-dev-output` — SSE enabled, with a dead-letter
  queue and a policy that denies non-TLS access.
- **ECR repository** `transform-data-dev` — immutable tags, scan on push,
  keeps the last 10 images.
- **Lambda function** `transform-data-dev` — arm64 container image, 256 MB,
  30 s timeout, concurrency capped at 1.
- **IAM role** — scoped to exactly one table, one queue, and one log group.
  No managed policies, no wildcard resources.
- **CloudWatch log group** — 14 day retention.

No VPC, no database password, no secret anywhere: the function authenticates
to DynamoDB and SQS with its execution role over TLS.

## Prerequisites

- Terraform >= 1.4
- Docker with buildx (for the image build)
- AWS CLI v2, authenticated to the target account

> **If you authenticate with `aws login`** (AWS CLI >= 2.42), Terraform will
> report `No valid credential sources found` even though `aws` works. The new
> `login_session` format is CLI-only; Terraform's Go SDK cannot read it. Add
> this line to the relevant profile in `~/.aws/config` to bridge the two:
>
> ```ini
> credential_process = aws configure export-credentials --format process
> ```
>
> `login_session` still takes precedence inside the CLI, so this does not
> recurse. Alternatively, prefix each command with
> `eval "$(aws configure export-credentials --format env)"`.

## Deploy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # edit region, tags, etc.
terraform init
terraform plan
terraform apply
```

`apply` builds the container image, pushes it to ECR, and wires up everything
else in a single pass. The image tag is a hash of `app/`, so editing the
application and re-applying deploys a new image; re-applying with no changes
skips the build.

If your CI pipeline builds the image instead, set `build_and_push_image =
false` and pin `image_tag` to whatever the pipeline pushed.

## Run it

The function has no event source — trigger it yourself:

```bash
terraform output -raw invoke_command   # prints the ready-made command
```

```bash
aws lambda invoke \
  --function-name "$(terraform output -raw lambda_function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' \
  /tmp/out.json && cat /tmp/out.json
```

Response:

```json
{
  "run_id": "8f3c2b11-...",
  "record_count": 5,
  "message_id": "a1b2c3d4-..."
}
```

Then read the message off the queue:

```bash
aws sqs receive-message \
  --queue-url "$(terraform output -raw sqs_queue_url)" \
  --max-number-of-messages 1 \
  --wait-time-seconds 5
```

## Message format

The SQS message body is a single JSON document:

```json
{
  "schema_version": "1.0",
  "source": { "type": "dynamodb", "table": "transform-data-dev-records" },
  "run_id": "8f3c2b11-...",
  "generated_at": "2026-11-24T09:41:07+00:00",
  "record_count": 5,
  "records": [
    { "name": "Alice Johnson", "sex": "Female", "address": "123 Maple Street, Springfield, IL 62704, USA" },
    { "name": "Brian Chen", "sex": "Male", "address": "456 Oak Avenue, Portland, OR 97205, USA" },
    { "name": "Carla Mendes", "sex": "Female", "address": "789 Pine Road, Austin, TX 78701, USA" },
    { "name": "Devon Okafor", "sex": "Non-binary", "address": "1011 Cedar Lane, Atlanta, GA 30303, USA" },
    { "name": "Elena Petrova", "sex": "Female", "address": "1213 Birch Boulevard, Denver, CO 80202, USA" }
  ]
}
```

Message attributes carry `contentType`, `recordCount`, and `runId` so a
consumer can filter without parsing the body.

Records are sorted by name, so the same table always produces the same
document — handy for diffing between runs.

## Local testing

Run the image locally against the real table using the Lambda Runtime
Interface Emulator baked into the base image:

```bash
cd app
docker build -t transform-data:local .

docker run --rm -p 9000:8080 \
  -e TABLE_NAME=transform-data-dev-records \
  -e QUEUE_URL="$(cd ../infra && terraform output -raw sqs_queue_url)" \
  -e AWS_REGION=us-east-2 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  transform-data:local

curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{}'
```

## Tear down

```bash
cd infra
terraform destroy
```

The ECR repository is created with `force_delete = true`, so destroy works
even with images still in it. That is a PoC convenience — turn it off before
this goes anywhere near production.

## Notes and trade-offs

- **Scan vs query.** The table holds five rows, so a consistent full scan is
  the correct access pattern. If it ever grows past a few hundred items,
  replace the scan with a query on a partition key.
- **256 KB ceiling.** The whole document goes in the message body. The handler
  fails loudly if the payload would exceed the SQS limit; at that point switch
  to writing the file to S3 and sending a pointer.
- **No trigger.** Add an EventBridge rule or a function URL in
  [infra/lambda.tf](infra/lambda.tf) when you know how it should fire.
- **Concurrency is capped at 1** because each run republishes the entire
  table; parallel runs would only produce duplicates.
