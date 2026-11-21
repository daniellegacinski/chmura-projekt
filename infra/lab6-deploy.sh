#!/bin/bash
# Wdrożenie Lab 6: testy reguł + nowa wersja funkcji przetwarzającej (AWS CloudShell)
set -euo pipefail
export AWS_PAGER=""
cd "$(dirname "$0")/.."
PROC_FUNC=zlecenia-processor-daniel

echo "== 1. Testy lokalne modułu reguł =="
python3 -m unittest discover -s testy -p 'test_*.py' -v

echo "== 2. Nowa wersja funkcji przetwarzającej (handler.py + rules.py) =="
rm -f /tmp/processor.zip
(cd src/processor && zip -q /tmp/processor.zip handler.py rules.py)
aws lambda update-function-code --function-name $PROC_FUNC --zip-file fileb:///tmp/processor.zip >/dev/null
aws lambda wait function-updated-v2 --function-name $PROC_FUNC
echo "GOTOWE."