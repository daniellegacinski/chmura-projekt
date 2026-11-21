# Lab 5 – SQS i Lambda przetwarzająca

## Środowisko
- Własne konto AWS, region `eu-north-1`, wdrożenie z AWS CloudShell: `infra/lab5-deploy.sh`
- Adres API: `https://ggwh1qprfa.execute-api.eu-north-1.amazonaws.com`, `apiVersion: 1.1.0`

## Przepływ
`POST` → funkcja API zapisuje `PENDING` w DynamoDB → wysyła `{"requestId": ...}` do SQS → `202`
→ funkcja przetwarzająca odbiera wiadomość → decyzja → `COMPLETED` w DynamoDB → `GET` zwraca wynik.

## Zasoby
| Zasób | Nazwa | Uprawnienia |
|---|---|---|
| Kolejka SQS (standard) | `zlecenia-kolejka-daniel` | visibility timeout 60 s = 6 × timeout funkcji (10 s) |
| Funkcja API | `zlecenia-api-daniel` | rola `zlecenia-api-lambda-daniel`: `PutItem/GetItem/UpdateItem` na tabeli, `sqs:SendMessage` na kolejce, logi |
| Funkcja przetwarzająca | `zlecenia-processor-daniel` | rola `zlecenia-processor-lambda-daniel`: odbiór/usuwanie z kolejki, `GetItem/UpdateItem` na tabeli, logi |
| Połączenie kolejka → funkcja | event source mapping | batch 5, `ReportBatchItemFailures` |

## Dowód
Pełny zapis: [`lab5-test.txt`](lab5-test.txt), skrypt: [`../testy/lab5-test.sh`](../testy/lab5-test.sh).

### Dowód 1 – oba stany dla jednego ID (`3df2533f-…`)
| # | Próba | Wynik |
|---|---|---|
| 1 | Wyłączenie połączenia kolejka → funkcja | `Disabled` |
| 2 | `POST` nowe zlecenie | ✅ `202`, `PENDING` |
| 3 | `GET` przy wstrzymanym konsumencie | ✅ `PENDING` |
| 4–5 | Włączenie połączenia, odczyt co 5 s | ✅ `COMPLETED`, `APPROVED / IN_STOCK` |
| 11 | CloudWatch Logs | ✅ API: `pending_saved`, `queued`; przetwarzanie: `start`, `decision_saved:APPROVED` |

### Dowód 2 – ponowne dostarczenie
| # | Próba | Wynik |
|---|---|---|
| 6 | Ponowny `POST` zakończonego zlecenia | ✅ `200` z wynikiem, log `already_completed` |
| 7 | `POST` z innymi danymi, to samo ID | ✅ `409` |
| 8 | Ręczne ponowne wysłanie tej samej wiadomości do SQS | ✅ `completedAt` bez zmian, log `already_completed_skip` – brak drugiego zapisu |

### Błąd wysyłki do SQS
| # | Próba | Wynik |
|---|---|---|
| 9 | `POST` przy niedostępnej kolejce (symulacja: błędny adres kolejki) | ✅ `503`, rekord zostaje `PENDING` |
| 10 | Ponowienie z tym samym ID | ✅ `202`, potem `COMPLETED` |

## Jak system chroni wynik
- **Ponowne dostarczenie po zapisaniu wyniku:** funkcja przetwarzająca najpierw czyta rekord; gdy jest `COMPLETED`, kończy bez zapisu.
- **Rozpoznanie zakończonej pracy:** po statusie `COMPLETED` w DynamoDB (to samo `requestId` w API, wiadomości, tabeli i logach).
- **Równoległe zapisy:** wynik zapisuje się warunkowo (`ConditionExpression: status = PENDING`), więc z dwóch równoczesnych prób wygrywa tylko jedna.
- **Paczka wiadomości:** gdy jedna wiadomość w paczce się nie uda, funkcja zwraca tylko jej `messageId` w `batchItemFailures`; pozostałe są uznane za przetworzone, a błędna wraca do kolejki po upływie visibility timeout.