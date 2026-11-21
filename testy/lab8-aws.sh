#!/bin/bash
# Lab 8 czesc B: pelny przeplyw nowego zlecenia w AWS (uruchamiac w CloudShell z glownego folderu repo)
export AWS_PAGER=""
cd "$(dirname "$0")/.."

API=$(aws apigatewayv2 get-apis --query "Items[?Name=='zlecenia-http-api-daniel'].ApiEndpoint" --output text)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TABLE=zlecenia-daniel
API_FUNC=zlecenia-api-daniel
PROC_FUNC=zlecenia-processor-daniel
ID=$(cat /proc/sys/kernel/random/uuid)
BODY='{"requestId":"'$ID'","scenario":"normal","payload":{"sku":"SKU-B","quantity":1}}'

req() {  # metoda, sciezka, [tresc]
  echo "> $1 $2"
  if [ -n "$3" ]; then
    echo "  tresc: $3"
    curl -s -i -X "$1" "$API$2" -H 'Content-Type: application/json' --data "$3"
  else
    curl -s -i -X "$1" "$API$2"
  fi | grep -iE '^HTTP/|^location:|^\{'
  echo; echo
}

logs() {
  aws logs filter-log-events --log-group-name "/aws/lambda/$1" --filter-pattern "\"$ID\"" \
    --query 'events[].message' --output text | tr '\t' '\n' | sed 's/^ *//' | grep -v '^$'
}

{
  echo "API: $API"
  echo "Nowe requestId: $ID"; echo

  echo "=== 1. POST nowe zlecenie -> oczekiwane 202 ==="
  req POST /requests "$BODY"

  echo "=== 2. GET od razu pod zwroconym adresem ==="
  req GET "/requests/$ID"

  echo "=== 3. GET co 3 s az do COMPLETED ==="
  for i in $(seq 1 20); do
    R=$(curl -s "$API/requests/$ID")
    echo "[$((i*3)) s] $R"
    echo "$R" | grep -q COMPLETED && break
    sleep 3
  done
  echo

  echo "=== 4. Ponowienie tego samego zlecenia -> oczekiwane 200, wynik zachowany ==="
  req POST /requests "$BODY"

  echo "=== 5. Rekord w DynamoDB (stan koncowy) ==="
  aws dynamodb get-item --table-name $TABLE --consistent-read --key '{"requestId":{"S":"'$ID'"}}' \
    --query 'Item.{status:status.S,decision:result.M.decision.S,reason:result.M.reason.S,attempts:attempts.N,createdAt:createdAt.S,completedAt:completedAt.S}' --output json
  echo

  sleep 15
  echo "=== 6. Logi funkcji API ($API_FUNC) dla tego ID ==="
  logs $API_FUNC
  echo
  echo "=== 7. Logi funkcji przetwarzajacej ($PROC_FUNC) dla tego ID ==="
  logs $PROC_FUNC
  echo

  echo "=== 8. Role wykonawcze ==="
  echo "funkcja API (wysyla do SQS):         $(aws lambda get-function-configuration --function-name $API_FUNC --query Role --output text)"
  echo "funkcja przetwarzajaca (czyta SQS):   $(aws lambda get-function-configuration --function-name $PROC_FUNC --query Role --output text)"
  echo

  echo "=== 9. Wersja dzialajacej trasy ==="
  echo "API_VERSION funkcji: $(aws lambda get-function-configuration --function-name $API_FUNC --query Environment.Variables.API_VERSION --output text)"
  echo "Wdrozona przez GitHub Actions (commit 5eb3d46): https://github.com/daniellegacinski/chmura-projekt/actions/runs/44924926187"
} 2>&1 | sed "s/$ACCOUNT/XXXXXXXXXXXX/g" | tee dowody/lab8-aws.txt