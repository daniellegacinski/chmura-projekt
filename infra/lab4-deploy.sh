#!/bin/bash
# Wdrożenie Lab 4: DynamoDB + Lambda + HTTP API (uruchamiać w AWS CloudShell)
set -euo pipefail
export AWS_PAGER=""
cd "$(dirname "$0")/.."

REGION=eu-north-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TABLE=zlecenia-daniel
FUNC=zlecenia-api-daniel
ROLE=zlecenia-api-lambda-daniel
API_NAME=zlecenia-http-api-daniel
API_VERSION=${API_VERSION:-1.0.0}

echo "== 1. Tabela DynamoDB =="
if ! aws dynamodb describe-table --table-name $TABLE >/dev/null 2>&1; then
  aws dynamodb create-table --table-name $TABLE \
    --attribute-definitions AttributeName=requestId,AttributeType=S \
    --key-schema AttributeName=requestId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=projekt,Value=uwb-chmura Key=wlasciciel,Value=daniel >/dev/null
  aws dynamodb wait table-exists --table-name $TABLE
fi
TABLE_ARN=$(aws dynamodb describe-table --table-name $TABLE --query Table.TableArn --output text)
echo "$TABLE_ARN"

echo "== 2. Rola wykonawcza funkcji =="
if ! aws iam get-role --role-name $ROLE >/dev/null 2>&1; then
  aws iam create-role --role-name $ROLE \
    --assume-role-policy-document file://infra/lambda-trust-policy.json \
    --tags Key=projekt,Value=uwb-chmura >/dev/null
fi
sed -e "s|__TABLE_ARN__|$TABLE_ARN|g" -e "s|__ACCOUNT_ID__|$ACCOUNT|g" \
    -e "s|__REGION__|$REGION|g" -e "s|__FUNC_NAME__|$FUNC|g" \
    infra/lab4-api-policy.json > /tmp/api-policy.json
aws iam put-role-policy --role-name $ROLE --policy-name api-dynamodb-logi \
  --policy-document file:///tmp/api-policy.json
ROLE_ARN=arn:aws:iam::$ACCOUNT:role/$ROLE

echo "== 3. Funkcja Lambda =="
rm -f /tmp/api.zip
(cd src/api && zip -q /tmp/api.zip handler.py)
ENV_VARS="Variables={TABLE_NAME=$TABLE,API_VERSION=$API_VERSION}"
if aws lambda get-function --function-name $FUNC >/dev/null 2>&1; then
  aws lambda update-function-code --function-name $FUNC --zip-file fileb:///tmp/api.zip >/dev/null
  aws lambda wait function-updated-v2 --function-name $FUNC
  aws lambda update-function-configuration --function-name $FUNC --environment "$ENV_VARS" >/dev/null
  aws lambda wait function-updated-v2 --function-name $FUNC
else
  for i in 1 2 3 4 5 6; do   # świeża rola IAM potrzebuje kilku sekund
    aws lambda create-function --function-name $FUNC --runtime python3.12 \
      --handler handler.handler --role $ROLE_ARN --zip-file fileb:///tmp/api.zip \
      --timeout 10 --environment "$ENV_VARS" \
      --tags projekt=uwb-chmura,wlasciciel=daniel >/dev/null && break
    echo "czekam na rolę IAM..."; sleep 10
  done
  aws lambda wait function-active-v2 --function-name $FUNC
fi
FUNC_ARN=$(aws lambda get-function --function-name $FUNC --query Configuration.FunctionArn --output text)

echo "== 4. HTTP API =="
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='$API_NAME'].ApiId" --output text)
if [ -z "$API_ID" ]; then
  API_ID=$(aws apigatewayv2 create-api --name $API_NAME --protocol-type HTTP \
    --tags projekt=uwb-chmura,wlasciciel=daniel --query ApiId --output text)
  INTEG_ID=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY \
    --integration-uri $FUNC_ARN --payload-format-version 2.0 --query IntegrationId --output text)
  aws apigatewayv2 create-route --api-id $API_ID --route-key "POST /requests" --target integrations/$INTEG_ID >/dev/null
  aws apigatewayv2 create-route --api-id $API_ID --route-key "GET /requests/{id}" --target integrations/$INTEG_ID >/dev/null
  aws apigatewayv2 create-stage --api-id $API_ID --stage-name '$default' --auto-deploy >/dev/null
  aws lambda add-permission --function-name $FUNC --statement-id apigw-invoke \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT:$API_ID/*" >/dev/null
fi
API_URL=$(aws apigatewayv2 get-api --api-id $API_ID --query ApiEndpoint --output text)
echo "GOTOWE. Adres API: $API_URL"