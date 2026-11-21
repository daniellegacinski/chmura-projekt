#!/bin/bash
# Sprzatanie po odbiorze projektu (AWS CloudShell). NIE uruchamiac przed odbiorem!
set -uo pipefail
export AWS_PAGER=""
read -p "Usunac WSZYSTKIE zasoby projektu z AWS? Wpisz TAK: " ok
[ "$ok" = "TAK" ] || { echo "Przerwano."; exit 1; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='zlecenia-http-api-daniel'].ApiId" --output text)
QUEUE_URL=$(aws sqs get-queue-url --queue-name zlecenia-kolejka-daniel --query QueueUrl --output text 2>/dev/null)
ESM=$(aws lambda list-event-source-mappings --function-name zlecenia-processor-daniel --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)

echo "1. Wstrzymanie przyjmowania zlecen (usuniecie HTTP API)"
[ -n "$API_ID" ] && aws apigatewayv2 delete-api --api-id "$API_ID"

echo "2. Wylaczenie i usuniecie polaczenia kolejka -> funkcja"
if [ -n "$ESM" ] && [ "$ESM" != "None" ]; then
  aws lambda update-event-source-mapping --uuid "$ESM" --no-enabled >/dev/null
  sleep 30
  aws lambda delete-event-source-mapping --uuid "$ESM" >/dev/null
fi

echo "3. Funkcje i ich logi"
for f in zlecenia-api-daniel zlecenia-processor-daniel; do
  aws lambda delete-function --function-name $f
  aws logs delete-log-group --log-group-name /aws/lambda/$f
done

echo "4. Kolejka i tabela"
[ -n "$QUEUE_URL" ] && aws sqs delete-queue --queue-url "$QUEUE_URL"
aws dynamodb delete-table --table-name zlecenia-daniel >/dev/null

echo "5. Bucket S3 (z obiektami)"
aws s3 rb s3://zlecenia-daniel-uwb-2026 --force

echo "6. Repozytorium ECR (z obrazami)"
aws ecr delete-repository --repository-name zlecenia-rules-daniel --force >/dev/null

echo "7. Role IAM"
del_role() {
  for p in $(aws iam list-role-policies --role-name "$1" --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$1" --policy-name "$p"
  done
  aws iam delete-role --role-name "$1"
}
for r in zlecenia-api-lambda-daniel zlecenia-processor-lambda-daniel github-deploy-daniel odczyt-zlecen-daniel; do
  del_role $r
done

echo "8. Dostawca OIDC GitHub"
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"

echo "Gotowe. Budzet budzet-uwb zostaje (nic nie kosztuje)."