"""Funkcja przetwarzająca zlecenia z SQS – Lab 5/6.

Każda wiadomość to {"requestId": "..."}.
Stany: PENDING -> COMPLETED. Wynik zapisuje się tylko raz.
Decyzję podejmuje moduł rules.py (Lab 6).
"""
import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

from rules import TransientFailure, decide

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def log(request_id, stage, result):
    print(json.dumps({"requestId": request_id, "stage": stage, "result": result}))


def is_conditional_failure(exc):
    return exc.response["Error"]["Code"] == "ConditionalCheckFailedException"


def start_attempt(request_id):
    """Zwiększa licznik prób, tylko gdy zlecenie jest PENDING.

    Zwraca aktualny rekord albo None, gdy zlecenie nie jest już PENDING.
    """
    try:
        response = table.update_item(
            Key={"requestId": request_id},
            UpdateExpression="ADD attempts :one",
            ConditionExpression="#s = :pending",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":one": 1, ":pending": "PENDING"},
            ReturnValues="ALL_NEW",
        )
        return response["Attributes"]
    except ClientError as exc:
        if is_conditional_failure(exc):
            return None
        raise


def save_result(request_id, result):
    """Zapis warunkowy: tylko PENDING -> COMPLETED. Chroni przed drugim zapisem."""
    try:
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
        return True
    except ClientError as exc:
        if is_conditional_failure(exc):
            return False
        raise


def process(request_id):
    item = table.get_item(Key={"requestId": request_id}, ConsistentRead=True).get("Item")
    if item is None:
        log(request_id, "processing", "not_found_skip")
        return
    if item["status"] == "COMPLETED":
        # Ponowne dostarczenie: wynik już jest, nie zapisujemy drugi raz.
        log(request_id, "processing", "already_completed_skip")
        return

    item = start_attempt(request_id)
    if item is None:
        log(request_id, "processing", "already_completed_skip")
        return
    attempt = int(item["attempts"])
    log(request_id, "processing", f"start_attempt_{attempt}")

    try:
        result = decide(item["payload"]["sku"], int(item["payload"]["quantity"]), item["scenario"], attempt)
    except TransientFailure:
        log(request_id, "processing", f"transient_failure_attempt_{attempt}")
        raise

    if save_result(request_id, result):
        log(request_id, "processing", f"decision_saved:{result['decision']}:{result['reason']}")
    else:
        log(request_id, "processing", "already_completed_skip")


def handler(event, context):
    """Błąd jednej wiadomości nie cofa całej paczki: zgłaszamy tylko ją (ReportBatchItemFailures)."""
    failures = []
    for record in event.get("Records", []):
        request_id = None
        try:
            request_id = json.loads(record["body"])["requestId"]
            process(request_id)
        except TransientFailure:
            # Wiadomość wróci do kolejki po visibility timeout i zostanie przetworzona ponownie.
            failures.append({"itemIdentifier": record["messageId"]})
        except Exception:
            log(request_id, "processing", "error_will_retry")
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}