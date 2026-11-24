"""transform-data.

AWS Lambda entry point. On every invocation this function:

  1. Reads all records from a DynamoDB table (``name``, ``sex``, ``address``).
  2. Transforms them into a single JSON document.
  3. Ships that document to an SQS queue as the message body.

Security notes
--------------
* No credentials are handled here. The function assumes its execution role and
  boto3 resolves temporary credentials from the Lambda runtime environment.
* All AWS calls go over TLS to regional endpoints by default.
* The table and the queue are referenced by environment variable so the same
  image can be promoted across environments without a rebuild.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
import uuid
from decimal import Decimal
from typing import Any, Iterator

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

#: Fields projected out of each DynamoDB item, in output order.
FIELDS: tuple[str, ...] = ("name", "sex", "address")

#: Maximum size of an SQS message body, in bytes.
SQS_MAX_BODY_BYTES = 262_144


def _required_env(key: str) -> str:
    value = os.environ.get(key)
    if not value:
        raise RuntimeError(f"Required environment variable {key!r} is not set")
    return value


TABLE_NAME = _required_env("TABLE_NAME")
QUEUE_URL = _required_env("QUEUE_URL")

_BOTO_CONFIG = Config(
    retries={"max_attempts": 5, "mode": "standard"},
    connect_timeout=5,
    read_timeout=10,
)

# Clients are built at import time so they survive across warm invocations.
_TABLE = boto3.resource("dynamodb", config=_BOTO_CONFIG).Table(TABLE_NAME)
_SQS = boto3.client("sqs", config=_BOTO_CONFIG)


# --------------------------------------------------------------------------- #
# Extract
# --------------------------------------------------------------------------- #


def _scan_items() -> Iterator[dict[str, Any]]:
    """Yield every item in the table, following pagination.

    The table holds a handful of rows, so a full scan is the right access
    pattern here. Swap this for a query if the table ever grows.
    """
    kwargs: dict[str, Any] = {
        "ProjectionExpression": "#n, sex, address",
        # "name" is a DynamoDB reserved word, so it needs an alias.
        "ExpressionAttributeNames": {"#n": "name"},
        "ConsistentRead": True,
    }
    while True:
        response = _TABLE.scan(**kwargs)
        yield from response.get("Items", [])
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            return
        kwargs["ExclusiveStartKey"] = last_key


def fetch_records() -> list[dict[str, Any]]:
    """Read every row from DynamoDB and normalise it to plain Python types."""
    records = [_normalise(item) for item in _scan_items()]
    # Stable ordering keeps the output deterministic; DynamoDB scans are not.
    records.sort(key=lambda record: record["name"])
    logger.info("Fetched %d record(s) from table %s", len(records), TABLE_NAME)
    return records


def _normalise(item: dict[str, Any]) -> dict[str, Any]:
    """Project an item onto FIELDS, converting DynamoDB types to JSON types."""
    return {field: _to_jsonable(item.get(field)) for field in FIELDS}


def _to_jsonable(value: Any) -> Any:
    if isinstance(value, Decimal):
        # DynamoDB returns all numbers as Decimal.
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, (set, frozenset)):
        return sorted(_to_jsonable(entry) for entry in value)
    if isinstance(value, (bytes, bytearray)):
        return value.decode("utf-8", errors="replace")
    return value


# --------------------------------------------------------------------------- #
# Transform
# --------------------------------------------------------------------------- #


def build_document(records: list[dict[str, Any]], run_id: str) -> dict[str, Any]:
    """Wrap the records in an envelope that a consumer can route on."""
    return {
        "schema_version": "1.0",
        "source": {"type": "dynamodb", "table": TABLE_NAME},
        "run_id": run_id,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(
            timespec="seconds"
        ),
        "record_count": len(records),
        "records": records,
    }


# --------------------------------------------------------------------------- #
# Load
# --------------------------------------------------------------------------- #


def send_to_sqs(document: dict[str, Any], run_id: str) -> str:
    """Publish the JSON document to SQS and return the message id."""
    body = json.dumps(document, separators=(",", ":"), ensure_ascii=False)
    size = len(body.encode("utf-8"))
    if size > SQS_MAX_BODY_BYTES:
        raise ValueError(
            f"Payload is {size} bytes, over the {SQS_MAX_BODY_BYTES} byte SQS "
            "limit. Write the file to S3 and send a pointer instead."
        )

    response = _SQS.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=body,
        MessageAttributes={
            "contentType": {"DataType": "String", "StringValue": "application/json"},
            "recordCount": {
                "DataType": "Number",
                "StringValue": str(document["record_count"]),
            },
            "runId": {"DataType": "String", "StringValue": run_id},
        },
    )
    message_id = response["MessageId"]
    logger.info("Sent %d byte message %s to SQS", size, message_id)
    return message_id


# --------------------------------------------------------------------------- #
# Handler
# --------------------------------------------------------------------------- #


def handler(event: dict[str, Any] | None, context: Any = None) -> dict[str, Any]:
    """Lambda entry point. Runs the full extract/transform/load in one pass."""
    run_id = getattr(context, "aws_request_id", None) or str(uuid.uuid4())
    logger.info("Starting run %s", run_id)

    try:
        records = fetch_records()
        document = build_document(records, run_id)
        message_id = send_to_sqs(document, run_id)
    except (BotoCoreError, ClientError):
        # Let Lambda mark the invocation as failed so the retry/alarm path fires.
        logger.exception("AWS call failed during run %s", run_id)
        raise

    result = {
        "run_id": run_id,
        "record_count": document["record_count"],
        "message_id": message_id,
    }
    logger.info("Run %s complete: %s", run_id, result)
    return result


if __name__ == "__main__":  # pragma: no cover - local smoke test
    print(json.dumps(handler({}), indent=2))
