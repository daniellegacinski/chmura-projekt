# Lab 4 – HTTP API i stan w DynamoDB

## Środowisko
- Własne konto AWS, region `eu-north-1`, wdrożenie z AWS CloudShell: `infra/lab4-deploy.sh`
- Adres API: `https://ggwh1qprfa.execute-api.eu-north-1.amazonaws.com`
- Trasy bez autoryzacji (`NONE`), dane syntetyczne

## Zasoby
| Zasób | Nazwa |
|---|---|
| Tabela DynamoDB (klucz `requestId`, on-demand) | `zlecenia-daniel` |
| Funkcja Lambda (Python 3.12) | `zlecenia-api-daniel` (`src/api/handler.py`) |
| Rola wykonawcza | `zlecenia-api-lambda-daniel`: tylko `PutItem`/`GetItem` na tabeli i zapis własnych logów |
| HTTP API | `zlecenia-http-api-daniel`: `POST /requests`, `GET /requests/{id}` |

## Dowód
Pełny zapis: [`lab4-test.txt`](lab4-test.txt), skrypt: [`../testy/lab4-test.sh`](../testy/lab4-test.sh).

| # | Próba | Oczekiwane | Wynik |
|---|---|---|---|
| 1 | `POST` nowe zlecenie | `201`, `DRAFT` | ✅ `201`, `location: /requests/{id}` |
| 2 | `GET` pod zwrócony adres | `200`, to samo ID, `DRAFT`, `apiVersion` | ✅ `200`, `apiVersion: 1.0.0` |
| 3 | `POST` te same dane | `200`, jeden draft | ✅ `200` |
| 4 | `POST` zmienione dane, to samo ID | `409`, draft bez zmian | ✅ `409` |
| 5 | Stan w DynamoDB po `409` | `quantity` nadal 2 | ✅ |
| 6 | `POST` błąd składni JSON | `400`, brak zapisu | ✅ `400 INVALID_JSON` |
| 7 | `POST` `quantity: -5` | `400`, brak zapisu | ✅ `400 INVALID_INPUT` |
| 8 | DynamoDB po błędach `400` | brak rekordu | ✅ `null` |
| 9 | `GET` innego poprawnego UUID | `404` | ✅ `404` |
| 10 | CloudWatch Logs | wpisy z ID i wynikiem | ✅ `draft_created`, `found`, `already_exists_same_data`, `conflict_changed_data` |

## Równoczesne żądania z tym samym ID
Zapis używa warunku `attribute_not_exists(requestId)`. DynamoDB utworzy rekord tylko pod wolnym kluczem. Jeśli dwa żądania przyjdą jednocześnie, zapisze się tylko jedno. Drugie dostanie `ConditionalCheckFailedException`, a funkcja odczyta istniejący rekord (`ConsistentRead`) i zwróci `200` albo `409`.