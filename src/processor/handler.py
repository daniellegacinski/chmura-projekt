"""Funkcja przetwarzająca zlecenia z SQS – Lab 5.

Każda wiadomość to {"requestId": "..."}.
Stany: PENDING -> COMPLETED. Wynik zapisuje się tylko raz.
"""
import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)

# Prosta, przewidywalna reguła na Lab 5 (pełne reguły i testy w Lab 6).
STOCK = {"SKU-A": 5, "SKU-B": 2}


def log(request_id, stage, result):
    print(json.dumps({"requestId": request_id, "stage": stage, "result": result}))


def decide(payload):
    sku, quantity = payload["sku"], int(payload["quantity"])
    if sku not in STOCK:
        return {"decision": "REJECTED", "reason": "UNKNOWN_SKU"}
    if quantity > STOCK[sku]:
        return {"decision": "REJECTED", "reason": "OUT_OF_STOCK"}
    return {"decision": "APPROVED", "reason": "IN_STOCK"}


def process(request_id):
    item = table.get_item(Key={"requestId": request_id}, ConsistentRead=True).get("Item")
    if item is None:
        log(request_id, "processing", "not_found_skip")
        return
    if item["status"] == "COMPLETED":
        # Ponowne dostarczenie: wynik już jest, nie zapisujemy drugi raz.
        log(request_id, "processing", "already_completed_skip")
        return

    log(request_id, "processing", "start")
    result = decide(item["payload"])
    try:
        # Zapis warunkowy: tylko PENDING -> COMPLETED. Chroni przed równoległym drugim zapisem.
        table.update_item(
            Key={"requestId": request_id},
            UpdateExpression="SET #s = :completed, #r = :result, completedAt = :t",
            ConditionExpression="#s = :pending",
            ExpressionAttributeNames={"#s": "status", "#r": "result"},
            ExpressionAttributeValues={
                ":completed": "COMPLETED",
                ":pending": "PENDING",
                ":result": result,
                ":t": datetime.now(timezone.utc).isoformat(),
            },
        )
        log(request_id, "processing", f"decision_saved:{result['decision']}")
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            log(request_id, "processing", "already_completed_skip")
            return
        raise


def handler(event, context):
    """Błąd jednej wiadomości nie cofa całej paczki: zgłaszamy tylko ją (ReportBatchItemFailures)."""
    failures = []
    for record in event.get("Records", []):
        request_id = None
        try:
            request_id = json.loads(record["body"])["requestId"]
            process(request_id)
        except Exception:
            log(request_id, "processing", "error_will_retry")
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}