#!/bin/bash
# Test Lab 6 (AWS CloudShell, z głównego folderu repo)
export AWS_PAGER=""
cd "$(dirname "$0")/.."
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
{
  echo "=== 1. Testy lokalne modułu reguł ==="
  python3 -m unittest discover -s testy -p 'test_*.py' -v
  echo
  echo "=== 2. Próbka z S3 przez działające API i analiza ==="
  python3 -u analiza/lab6_analiza.py
} 2>&1 | sed "s/$ACCOUNT/XXXXXXXXXXXX/g" | tee dowody/lab6-test.txt