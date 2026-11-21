#!/bin/bash
# Wdrożenie Lab 5: SQS + funkcja przetwarzająca + nowa wersja API (uruchamiać w AWS CloudShell)
# Wymaga zasobów z Lab 4 (tabela, funkcja API, HTTP API).
set -euo pipefail
export AWS_PAGER=""
cd "$(dirname "$0")/.."

REGION=eu-north-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TABLE=zlecenia-daniel
QUEUE=zlecenia-kolejka-daniel
API_FUNC=zlecenia-api-daniel
API_ROLE=zlecenia-api-lambda-daniel
PROC_FUNC=zlecenia-processor-daniel
PROC_ROLE=zlecenia-processor-lambda-daniel
API_VERSION=${API_VERSION:-1.1.0}
PROC_TIMEOUT=10
VISIBILITY=60   # 6 x czas działania funkcji (zalecenie AWS dla SQS + Lambda)

render() {  # plik_wzorca funkcja -> /tmp/<nazwa>
  sed -e "s|__TABLE_ARN__|$TABLE_ARN|g" -e "s|__QUEUE_ARN__|$QUEUE_ARN|g" \
      -e "s|__ACCOUNT_ID__|$ACCOUNT|g" -e "s|__REGION__|$REGION|g" -e "s|__FUNC_NAME__|$2|g" \
      "$1" > "/tmp/$(basename "$1")"
  echo "/tmp/$(basename "$1")"
}

echo "== 1. Kolejka SQS =="
QUEUE_URL=$(aws sqs create-queue --queue-name $QUEUE \
  --attributes VisibilityTimeout=$VISIBILITY \
  --tags projekt=uwb-chmura,wlasciciel=daniel --query QueueUrl --output text)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn \
  --query Attributes.QueueArn --output text)
TABLE_ARN=$(aws dynamodb describe-table --table-name $TABLE --query Table.TableArn --output text)
echo "$QUEUE_URL"

echo "== 2. Uprawnienia roli API (DynamoDB + wysyłka do SQS) =="
aws iam put-role-policy --role-name $API_ROLE --policy-name api-dynamodb-logi \
  --policy-document "file://$(render infra/lab5-api-policy.json $API_FUNC)"

echo "== 3. Rola funkcji przetwarzającej =="
if ! aws iam get-role --role-name $PROC_ROLE >/dev/null 2>&1; then
  aws iam create-role --role-name $PROC_ROLE \
    --assume-role-policy-document file://infra/lambda-trust-policy.json \
    --tags Key=projekt,Value=uwb-chmura >/dev/null
fi
aws iam put-role-policy --role-name $PROC_ROLE --policy-name processor-sqs-dynamodb-logi \
  --policy-document "file://$(render infra/lab5-processor-policy.json $PROC_FUNC)"

echo "== 4. Funkcja przetwarzająca =="
rm -f /tmp/processor.zip
(cd src/processor && zip -q /tmp/processor.zip handler.py)
if aws lambda get-function --function-name $PROC_FUNC >/dev/null 2>&1; then
  aws lambda update-function-code --function-name $PROC_FUNC --zip-file fileb:///tmp/processor.zip >/dev/null
  aws lambda wait function-updated-v2 --function-name $PROC_FUNC
else
  for i in 1 2 3 4 5 6; do   # świeża rola IAM potrzebuje kilku sekund
    aws lambda create-function --function-name $PROC_FUNC --runtime python3.12 \
      --handler handler.handler --role arn:aws:iam::$ACCOUNT:role/$PROC_ROLE \
      --zip-file fileb:///tmp/processor.zip --timeout $PROC_TIMEOUT \
      --environment "Variables={TABLE_NAME=$TABLE}" \
      --tags projekt=uwb-chmura,wlasciciel=daniel >/dev/null && break
    echo "czekam na rolę IAM..."; sleep 10
  done
  aws lambda wait function-active-v2 --function-name $PROC_FUNC
fi

echo "== 5. Nowa wersja funkcji API ($API_VERSION) =="
rm -f /tmp/api.zip
(cd src/api && zip -q /tmp/api.zip handler.py)
aws lambda update-function-code --function-name $API_FUNC --zip-file fileb:///tmp/api.zip >/dev/null
aws lambda wait function-updated-v2 --function-name $API_FUNC
aws lambda update-function-configuration --function-name $API_FUNC \
  --environment "Variables={TABLE_NAME=$TABLE,QUEUE_URL=$QUEUE_URL,API_VERSION=$API_VERSION}" >/dev/null
aws lambda wait function-updated-v2 --function-name $API_FUNC

echo "== 6. Połączenie kolejka -> funkcja przetwarzająca =="
ESM=$(aws lambda list-event-source-mappings --function-name $PROC_FUNC --event-source-arn "$QUEUE_ARN" \
  --query 'EventSourceMappings[0].UUID' --output text)
if [ "$ESM" = "None" ] || [ -z "$ESM" ]; then
  for i in 1 2 3 4 5 6; do   # uprawnienia do kolejki też potrzebują chwili
    ESM=$(aws lambda create-event-source-mapping --function-name $PROC_FUNC \
      --event-source-arn "$QUEUE_ARN" --batch-size 5 \
      --function-response-types ReportBatchItemFailures --query UUID --output text) && break
    echo "czekam na uprawnienia..."; sleep 10
  done
fi
echo "UUID połączenia: $ESM"
echo "GOTOWE."