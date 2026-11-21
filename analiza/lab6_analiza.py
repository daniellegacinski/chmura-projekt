"""Lab 6: próbka z prywatnego S3 -> działające API -> odsetek odrzuceń per grupa.

Uruchamiać w AWS CloudShell z głównego folderu repo: python3 -u analiza/lab6_analiza.py
"""
import csv
import io
import json
import time
import urllib.error
import urllib.request
import uuid

import boto3

BUCKET = "zlecenia-daniel-uwb-2026"
KEY = "student-daniel/input/zlecenia.csv"
API_NAME = "zlecenia-http-api-daniel"
PROC_LOG_GROUP = "/aws/lambda/zlecenia-processor-daniel"
GROUPS = ["standard", "limit", "retry"]
RESULTS_FILE = "dowody/lab6-wyniki.csv"


def api_url():
    apis = boto3.client("apigatewayv2").get_apis()["Items"]
    return next(a["ApiEndpoint"] for a in apis if a["Name"] == API_NAME)


def http(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read() or b"{}")


def log_events(request_id):
    """Wszystkie wpisy z logów dla ID (CloudWatch zwraca wyniki stronami)."""
    paginator = boto3.client("logs").get_paginator("filter_log_events")
    events = []
    for page in paginator.paginate(logGroupName=PROC_LOG_GROUP, filterPattern=f'"{request_id}"'):
        events.extend(page["events"])
    return sorted(events, key=lambda e: e["timestamp"])


def main():
    api = api_url()
    raw = boto3.client("s3").get_object(Bucket=BUCKET, Key=KEY)["Body"].read().decode("utf-8")
    rows = list(csv.DictReader(io.StringIO(raw)))
    print(f"API: {api}")
    print(f"Próbka: s3://{BUCKET}/{KEY} – {len(rows)} rekordów\n")

    print("=== Wysyłka do API (każdy rekord dostaje nowy UUID) ===")
    for row in rows:
        row["requestId"] = str(uuid.uuid4())
        status, _ = http("POST", f"{api}/requests", {
            "requestId": row["requestId"],
            "scenario": row["scenario"],
            "payload": {"sku": row["sku"], "quantity": int(row["quantity"])},
        })
        print(f"{row['caseId']}  {row['group']:8}  {row['requestId']}  POST -> {status}")

    print("\n=== Zbieranie wyników (GET co 10 s, maks. 5 min) ===")
    pending = {row["requestId"] for row in rows}
    deadline = time.time() + 300
    while pending and time.time() < deadline:
        for row in rows:
            if row["requestId"] not in pending:
                continue
            _, body = http("GET", f"{api}/requests/{row['requestId']}")
            if body.get("status") == "COMPLETED":
                row["decision"] = body["result"]["decision"]
                row["reason"] = body["result"]["reason"]
                pending.discard(row["requestId"])
        if pending:
            print(f"  niezakończone: {len(pending)} – czekam 10 s")
            time.sleep(10)

    print("\n=== Wynik per zlecenie (jedna decyzja na UUID) ===")
    fields = ["caseId", "group", "scenario", "sku", "quantity", "requestId", "decision", "reason"]
    with open(RESULTS_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            row.setdefault("decision", "BRAK")
            row.setdefault("reason", "-")
            writer.writerow(row)
            print(f"{row['caseId']}  {row['group']:8}  {row['sku']:6} x{row['quantity']:>2}  "
                  f"-> {row['decision']:8} {row['reason']}")
    print(f"(zapisano: {RESULTS_FILE})")

    print("\n=== Odsetek odrzuceń biznesowych per grupa ===")
    print("| Grupa | Zakończone | Odrzucone biznesowo | Odsetek |")
    print("|---|---|---|---|")
    for group in GROUPS:
        done = [r for r in rows if r["group"] == group and r["decision"] != "BRAK"]
        rejected = [r for r in done if r["decision"] == "REJECTED"]
        share = f"{100 * len(rejected) / len(done):.0f}%" if done else "-"
        print(f"| `{group}` | {len(done)} | {len(rejected)} | {share} |")
    missing = [r["caseId"] for r in rows if r["decision"] == "BRAK"]
    if missing:
        print(f"UWAGA – niezakończone: {', '.join(missing)}")

    retry = next(r for r in rows if r["group"] == "retry")
    print(f"\n=== Kolejne próby dla {retry['caseId']} (transient_once), ID {retry['requestId']} ===")
    time.sleep(15)
    for event in log_events(retry["requestId"]):
        when = time.strftime("%H:%M:%S", time.gmtime(event["timestamp"] / 1000))
        print(f"{when} UTC  {event['message'].strip()}")
    _, body = http("GET", f"{api}/requests/{retry['requestId']}")
    print(f"\nGET /requests/{retry['requestId']}\n{json.dumps(body, ensure_ascii=False)}")


if __name__ == "__main__":
    main()