#!/bin/bash
# Lab 7: dostawca OIDC GitHub, prywatne ECR i rola wdrożeniowa (uruchamiać w AWS CloudShell)
set -euo pipefail
export AWS_PAGER=""
cd "$(dirname "$0")/.."

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
# GitHub wysyła "sub" ze stałymi ID właściciela i repozytorium: repo:<login>@<id>/<repo>@<id>:ref:...
# (wartości odczytane z CloudTrail po pierwszej odrzuconej próbie)
GH_REPO="daniellegacinski@240736078/chmura-projekt@1466500022"
ROLE=github-deploy-daniel
ECR_REPO=zlecenia-rules-daniel
API_FUNC=zlecenia-api-daniel
OIDC_HOST=token.actions.githubusercontent.com
OIDC_ARN=arn:aws:iam::$ACCOUNT:oidc-provider/$OIDC_HOST

echo "== 1. Dostawca tożsamości OIDC (GitHub) =="
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider --url "https://$OIDC_HOST" \
    --client-id-list sts.amazonaws.com --tags Key=projekt,Value=uwb-chmura >/dev/null
fi
echo "ok"

echo "== 2. Prywatne repozytorium ECR =="
if ! aws ecr describe-repositories --repository-names $ECR_REPO >/dev/null 2>&1; then
  aws ecr create-repository --repository-name $ECR_REPO \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true \
    --tags Key=projekt,Value=uwb-chmura Key=wlasciciel,Value=daniel >/dev/null
fi
ECR_ARN=$(aws ecr describe-repositories --repository-names $ECR_REPO --query 'repositories[0].repositoryArn' --output text)
FUNC_ARN=$(aws lambda get-function --function-name $API_FUNC --query Configuration.FunctionArn --output text)
echo "ok"

echo "== 3. Rola wdrożeniowa dla GitHub Actions =="
sed -e "s|__OIDC_ARN__|$OIDC_ARN|g" -e "s|__GH_REPO__|$GH_REPO|g" infra/lab7-github-trust.json > /tmp/gh-trust.json
if ! aws iam get-role --role-name $ROLE >/dev/null 2>&1; then
  aws iam create-role --role-name $ROLE --assume-role-policy-document file:///tmp/gh-trust.json \
    --tags Key=projekt,Value=uwb-chmura >/dev/null
else
  aws iam update-assume-role-policy --role-name $ROLE --policy-document file:///tmp/gh-trust.json
fi
sed -e "s|__FUNC_ARN__|$FUNC_ARN|g" -e "s|__ECR_ARN__|$ECR_ARN|g" infra/lab7-deploy-policy.json > /tmp/gh-deploy.json
aws iam put-role-policy --role-name $ROLE --policy-name wdrozenie-lambda-ecr --policy-document file:///tmp/gh-deploy.json
echo "ok"

echo
echo "GOTOWE. Wartość sekretu AWS_ROLE_ARN w GitHub:"
echo "arn:aws:iam::$ACCOUNT:role/$ROLE"