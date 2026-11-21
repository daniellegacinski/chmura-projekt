#!/bin/bash
# Test Lab 3: rola odczyt-zlecen-daniel czyta tylko prefiks student-daniel/
# Uruchamiany w AWS CloudShell (eu-north-1)
BUCKET=zlecenia-daniel-uwb-2026
ROLE=odczyt-zlecen-daniel
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

run() { echo "> $*"; "$@" 2>&1; echo; }

{
  echo "=== 1. Tozsamosc przed przyjeciem roli (administrator) ==="
  run aws sts get-caller-identity

  CREDS=$(aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT:role/$ROLE --role-session-name test-odczytu --query Credentials --output json)
  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .SessionToken)

  echo "=== 2. Tozsamosc po przyjeciu roli $ROLE ==="
  run aws sts get-caller-identity

  echo "=== 3. Odczyt wlasnego pliku (prefiks student-daniel/) - oczekiwany sukces ==="
  run aws s3 cp s3://$BUCKET/student-daniel/input/zlecenia.csv -

  echo "=== 4. Odczyt obiektu kontrolnego (prefiks kontrola/) - oczekiwane AccessDenied ==="
  run aws s3api get-object --bucket $BUCKET --key kontrola/kontrolny.csv /tmp/kontrolny.csv

  echo "=== 5. Listowanie wlasnego prefiksu - oczekiwany sukces ==="
  run aws s3 ls s3://$BUCKET/student-daniel/ --recursive

  echo "=== 6. Listowanie prefiksu kontrolnego - oczekiwane AccessDenied ==="
  run aws s3 ls s3://$BUCKET/kontrola/
} | sed "s/$ACCOUNT/XXXXXXXXXXXX/g" | tee lab3-test.txt