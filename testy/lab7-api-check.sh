#!/bin/bash
# Lab 7: odczyt apiVersion i wyniku znanego zlecenia (przed i po wdrożeniu)
export AWS_PAGER=""
API=$(aws apigatewayv2 get-apis --query "Items[?Name=='zlecenia-http-api-daniel'].ApiEndpoint" --output text)
ID=d342f5a7-5b3c-4930-966f-87a8ed4d31fa   # O01 z Lab 6
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')  GET $API/requests/$ID"
curl -s -i "$API/requests/$ID" | grep -iE '^HTTP/|^\{'
echo