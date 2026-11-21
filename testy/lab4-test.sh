#!/bin/bash
# Test Lab 4 na działającym API (uruchamiać w AWS CloudShell z głównego folderu repo)
export AWS_PAGER=""
API=$(aws apigatewayv2 get-apis --query "Items[?Name=='zlecenia-http-api-daniel'].ApiEndpoint" --output text)
TABLE=zlecenia-daniel
FUNC=zlecenia-api-daniel
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ID=$(cat /proc/sys/kernel/random/uuid)
BAD_ID=$(cat /proc/sys/kernel/random/uuid)
UNKNOWN_ID=$(cat /proc/sys/kernel/random/uuid)

BODY='{"requestId":"'$ID'","scenario":"normal","payload":{"sku":"SKU-A","quantity":2}}'
CHANGED='{"requestId":"'$ID'","scenario":"normal","payload":{"sku":"SKU-A","quantity":3}}'
BROKEN_JSON='{"requestId":"'$BAD_ID'","scenario":"normal",'
OUT_OF_CONTRACT='{"requestId":"'$BAD_ID'","scenario":"normal","payload":{"sku":"SKU-A","quantity":-5}}'

req() {  # metoda, ścieżka, [treść]
  echo "> $1 $2"
  if [ -n "$3" ]; then
    echo "  treść: $3"
    curl -s -i -X "$1" "$API$2" -H 'Content-Type: application/json' --data "$3"
  else
    curl -s -i -X "$1" "$API$2"
  fi | grep -iE '^HTTP/|^location:|^\{'
  echo; echo
}

db() {  # stan rekordu prosto z DynamoDB
  echo "> dynamodb get-item $1"
  aws dynamodb get-item --table-name $TABLE --consistent-read \
    --key '{"requestId":{"S":"'$1'"}}' \
    --query 'Item.{status:status.S,sku:payload.M.sku.S,quantity:payload.M.quantity.N}' --output json
  echo
}

{
  echo "API: $API"
  echo "requestId testu: $ID"; echo
  echo "=== 1. POST nowe zlecenie -> oczekiwane 201 ==="; req POST /requests "$BODY"
  echo "=== 2. GET pod zwrócony adres -> oczekiwane 200, DRAFT, apiVersion ==="; req GET "/requests/$ID"
  echo "=== 3. POST te same dane -> oczekiwane 200 ==="; req POST /requests "$BODY"
  echo "=== 4. POST zmienione dane, to samo ID -> oczekiwane 409 ==="; req POST /requests "$CHANGED"
  echo "=== 5. Stan w DynamoDB -> jeden DRAFT, quantity nadal 2 ==="; db "$ID"
  echo "=== 6. POST błąd składni JSON -> oczekiwane 400 ==="; req POST /requests "$BROKEN_JSON"
  echo "=== 7. POST wartość spoza kontraktu (quantity -5) -> oczekiwane 400 ==="; req POST /requests "$OUT_OF_CONTRACT"
  echo "=== 8. Po błędach 400 nic nie zapisano (oczekiwane null) ==="; db "$BAD_ID"
  echo "=== 9. GET innego poprawnego UUID -> oczekiwane 404 ==="; req GET "/requests/$UNKNOWN_ID"
  echo "=== 10. CloudWatch Logs dla $ID ==="
  sleep 15
  aws logs filter-log-events --log-group-name /aws/lambda/$FUNC \
    --filter-pattern "\"$ID\"" --query 'events[].message' --output text
} | sed "s/$ACCOUNT/XXXXXXXXXXXX/g" | tee dowody/lab4-test.txt