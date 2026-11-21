#!/bin/bash
# Test Lab 5 (uruchamiać w AWS CloudShell z głównego folderu repo)
export AWS_PAGER=""
cd "$(dirname "$0")/.."

API=$(aws apigatewayv2 get-apis --query "Items[?Name=='zlecenia-http-api-daniel'].ApiEndpoint" --output text)
TABLE=zlecenia-daniel
API_FUNC=zlecenia-api-daniel
PROC_FUNC=zlecenia-processor-daniel
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
QUEUE_URL=$(aws sqs get-queue-url --queue-name zlecenia-kolejka-daniel --query QueueUrl --output text)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
ESM=$(aws lambda list-event-source-mappings --function-name $PROC_FUNC --event-source-arn "$QUEUE_ARN" --query 'EventSourceMappings[0].UUID' --output text)
ID=$(cat /proc/sys/kernel/random/uuid)
ID503=$(cat /proc/sys/kernel/random/uuid)

body() { echo '{"requestId":"'$1'","scenario":"normal","payload":{"sku":"'$2'","quantity":'$3'}}'; }

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

db() {
  echo "> dynamodb get-item $1"
  aws dynamodb get-item --table-name $TABLE --consistent-read --key '{"requestId":{"S":"'$1'"}}' \
    --query 'Item.{status:status.S,decision:result.M.decision.S,reason:result.M.reason.S,completedAt:completedAt.S}' --output json
  echo
}

wait_esm() {
  for i in $(seq 1 40); do
    S=$(aws lambda get-event-source-mapping --uuid "$ESM" --query State --output text)
    [ "$S" = "$1" ] && break
    sleep 5
  done
  echo "stan połączenia kolejka -> funkcja: $S"; echo
}

wait_completed() {
  for i in $(seq 1 24); do
    R=$(curl -s "$API/requests/$1")
    echo "[$((i*5)) s] $R"
    echo "$R" | grep -q COMPLETED && break
    sleep 5
  done
  echo
}

{
  echo "API: $API"
  echo "requestId testu: $ID"; echo

  echo "=== 1. Wyłączam połączenie kolejka -> funkcja przetwarzająca ==="
  aws lambda update-event-source-mapping --uuid "$ESM" --no-enabled >/dev/null
  wait_esm Disabled
  echo "(dodatkowe 60 s, aż wyłączenie dotrze do wszystkich odbiorców kolejki)"; sleep 60

  echo "=== 2. POST nowe zlecenie przy wstrzymanym konsumencie -> oczekiwane 202 ==="
  req POST /requests "$(body $ID SKU-A 2)"
  echo "=== 3. GET -> oczekiwane PENDING ==="
  sleep 5; req GET "/requests/$ID"

  echo "=== 4. Włączam połączenie ==="
  aws lambda update-event-source-mapping --uuid "$ESM" --enabled >/dev/null
  wait_esm Enabled

  echo "=== 5. GET co 5 s aż do COMPLETED ==="
  wait_completed "$ID"

  echo "=== 6. Ponowny POST zakończonego zlecenia -> oczekiwane 200 z wynikiem ==="
  req POST /requests "$(body $ID SKU-A 2)"
  echo "=== 7. POST zmienione dane, to samo ID -> oczekiwane 409 ==="
  req POST /requests "$(body $ID SKU-A 3)"

  echo "=== 8. Ponowne dostarczenie tej samej wiadomości do kolejki ==="
  echo "Stan PRZED:"; db "$ID"
  echo "> sqs send-message {\"requestId\":\"$ID\"}"
  aws sqs send-message --queue-url "$QUEUE_URL" --message-body '{"requestId":"'$ID'"}' --query MessageId --output text
  sleep 25
  echo "Stan PO (completedAt bez zmian = brak drugiego zapisu):"; db "$ID"

  echo "=== 9. Błąd wysyłki do SQS -> oczekiwane 503 i rekord PENDING ==="
  ENV_OK=$(aws lambda get-function-configuration --function-name $API_FUNC --query Environment --output json)
  ENV_BAD=$(echo "$ENV_OK" | jq -c '.Variables.QUEUE_URL |= . + "-nie-istnieje"')
  aws lambda update-function-configuration --function-name $API_FUNC --environment "$ENV_BAD" >/dev/null
  aws lambda wait function-updated-v2 --function-name $API_FUNC
  echo "(symulacja: funkcja API wskazuje na nieistniejącą kolejkę)"
  req POST /requests "$(body $ID503 SKU-B 1)"
  db "$ID503"
  aws lambda update-function-configuration --function-name $API_FUNC --environment "$ENV_OK" >/dev/null
  aws lambda wait function-updated-v2 --function-name $API_FUNC
  echo "(przywrócono poprawny adres kolejki)"
  echo "=== 10. Ponowienie z tym samym ID przy istniejącym PENDING -> oczekiwane 202, potem COMPLETED ==="
  req POST /requests "$(body $ID503 SKU-B 1)"
  wait_completed "$ID503"

  echo "=== 11. CloudWatch Logs dla $ID ==="
  sleep 10
  echo "-- funkcja API:"
  aws logs filter-log-events --log-group-name /aws/lambda/$API_FUNC --filter-pattern "\"$ID\"" --query 'events[].message' --output text
  echo "-- funkcja przetwarzająca:"
  aws logs filter-log-events --log-group-name /aws/lambda/$PROC_FUNC --filter-pattern "\"$ID\"" --query 'events[].message' --output text
} 2>&1 | sed "s/$ACCOUNT/XXXXXXXXXXXX/g" | tee dowody/lab5-test.txt