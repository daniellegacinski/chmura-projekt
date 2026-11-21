"""API zleceń (wariant: zamówienia).

Lab 4: POST /requests zapisywał DRAFT.
Lab 5: POST zapisuje PENDING i wysyła wiadomość do SQS; 202 dopiero po potwierdzeniu wysyłki.
"""
import base64
import json
import os
import re
from datetime import datetime, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
QUEUE_URL = os.environ["QUEUE_URL"]
API_VERSION = os.environ.get("API_VERSION", "1.1.0")

UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
SKU_RE = re.compile(r"^SKU-[A-Z0-9]{1,20}$")
SCENARIOS = {"normal", "transient_once"}
MAX_QUANTITY = 1000

table = boto3.resource("dynamodb").Table(TABLE_NAME)
sqs = boto3.client("sqs")


def now():
    return datetime.now(timezone.utc).isoformat()


def log(request_id, stage, result):
    """Log zawiera tylko ID, etap i wynik (zasada z README kursu)."""
    print(json.dumps({"requestId": request_id, "stage": stage, "result": result}))


def respond(status, body, headers=None):
    all_headers = {"Content-Type": "application/json; charset=utf-8"}
    all_headers.update(headers or {})
    return {"statusCode": status, "headers": all_headers, "body": json.dumps(body, ensure_ascii=False)}


def error(status, code, message):
    return respond(status, {"error": code, "message": message})


def public_view(item):
    """To, co API pokazuje na zewnątrz."""
    view = {"requestId": item["requestId"], "status": item["status"], "apiVersion": API_VERSION}
    if "result" in item:
        view["result"] = item["result"]
    return view


def validate(body):
    """Zwraca (dane, None) albo (None, opis_błędu)."""
    if not isinstance(body, dict):
        return None, "Treść musi być obiektem JSON."
    if set(body) != {"requestId", "scenario", "payload"}:
        return None, "Wymagane są dokładnie pola: requestId, scenario, payload."
    request_id = body["requestId"]
    if not isinstance(request_id, str) or not UUID_RE.match(request_id):
        return None, "requestId musi być UUID."
    scenario = body["scenario"]
    if not isinstance(scenario, str) or scenario not in SCENARIOS:
        return None, "scenario musi mieć wartość normal albo transient_once."
    payload = body["payload"]
    if not isinstance(payload, dict) or set(payload) != {"sku", "quantity"}:
        return None, "payload musi zawierać dokładnie pola: sku, quantity."
    sku, quantity = payload["sku"], payload["quantity"]
    if not isinstance(sku, str) or not SKU_RE.match(sku):
        return None, "sku musi mieć format SKU-XXX (wielkie litery i cyfry)."
    if isinstance(quantity, bool) or not isinstance(quantity, int) or not 1 <= quantity <= MAX_QUANTITY:
        return None, f"quantity musi być liczbą całkowitą od 1 do {MAX_QUANTITY}."
    return {
        "requestId": request_id.lower(),
        "scenario": scenario,
        "payload": {"sku": sku, "quantity": quantity},
    }, None


def same_request(item, data):
    return (
        item["scenario"] == data["scenario"]
        and item["payload"]["sku"] == data["payload"]["sku"]
        and int(item["payload"]["quantity"]) == data["payload"]["quantity"]
    )


def send_to_queue(request_id):
    """Minimalna wiadomość: tylko requestId. Resztę funkcja przetwarzająca czyta z DynamoDB."""
    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps({"requestId": request_id}))


def promote_draft(request_id):
    """Szkic z Lab 4 przechodzi w PENDING (DRAFT -> PENDING)."""
    try:
        table.update_item(
            Key={"requestId": request_id},
            UpdateExpression="SET #s = :pending",
            ConditionExpression="#s = :draft",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":pending": "PENDING", ":draft": "DRAFT"},
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise


def create_request(event):
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    try:
        body = json.loads(raw)
    except json.JSONDecodeError:
        log(None, "post", "invalid_json")
        return error(400, "INVALID_JSON", "Treść żądania nie jest poprawnym JSON-em.")

    data, problem = validate(body)
    if problem:
        log(None, "post", "invalid_input")
        return error(400, "INVALID_INPUT", problem)

    request_id = data["requestId"]
    location = {"Location": f"/requests/{request_id}"}
    item = {**data, "status": "PENDING", "createdAt": now()}
    try:
        # Zapis warunkowy: nowy rekord tylko pod wolnym kluczem.
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(requestId)")
        log(request_id, "post", "pending_saved")
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise
        existing = table.get_item(Key={"requestId": request_id}, ConsistentRead=True)["Item"]
        if not same_request(existing, data):
            log(request_id, "post", "conflict_changed_data")
            return error(409, "CONFLICT", "Zlecenie o tym requestId istnieje z innymi danymi.")
        if existing["status"] == "COMPLETED":
            log(request_id, "post", "already_completed")
            return respond(200, public_view(existing), location)
        if existing["status"] == "DRAFT":
            promote_draft(request_id)
        # Rekord PENDING już istnieje (np. po wcześniejszym 503) -> wysyłamy wiadomość ponownie.
        log(request_id, "post", "retry_pending")

    try:
        send_to_queue(request_id)
    except (ClientError, BotoCoreError):
        log(request_id, "post", "queue_send_failed")
        return error(503, "QUEUE_UNAVAILABLE",
                     "Nie udało się przekazać zlecenia do kolejki. Ponów żądanie z tym samym requestId.")
    log(request_id, "post", "queued")
    return respond(202, {"requestId": request_id, "status": "PENDING", "apiVersion": API_VERSION}, location)


def get_request(event):
    request_id = (event.get("pathParameters") or {}).get("id", "")
    if not UUID_RE.match(request_id):
        log(None, "get", "invalid_id")
        return error(400, "INVALID_INPUT", "id musi być UUID.")
    request_id = request_id.lower()
    item = table.get_item(Key={"requestId": request_id}, ConsistentRead=True).get("Item")
    if item is None:
        log(request_id, "get", "not_found")
        return error(404, "NOT_FOUND", "Nie ma zlecenia o tym requestId.")
    log(request_id, "get", "found")
    return respond(200, public_view(item))


def handler(event, context):
    route = event.get("routeKey")
    if route == "POST /requests":
        return create_request(event)
    if route == "GET /requests/{id}":
        return get_request(event)
    return error(404, "NOT_FOUND", "Nieznana trasa.")