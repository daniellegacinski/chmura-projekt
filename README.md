# Projekt AWS – asynchroniczne przetwarzanie zleceń

- **Wariant:** zamówienia (`sku`, `quantity`; decyzja `APPROVED` / `REJECTED`)
- **Konto:** własne konto AWS (plan Free z kredytami), praca przez AWS CloudShell
- **Region:** `eu-north-1` (Sztokholm)
- **Oznaczanie zasobów:** nazwy z `-daniel`, tagi `projekt=uwb-chmura`, `wlasciciel=daniel`
- **Prefiks danych:** `student-daniel/`
- LocalStack (`compose.yaml`) służy tylko do lokalnych prób.

## Kontrakt API
- Adres: `https://ggwh1qprfa.execute-api.eu-north-1.amazonaws.com` (HTTP API, etap `$default`)
- Dostęp do tras: bez autoryzacji (`NONE`), dane wyłącznie syntetyczne
- `apiVersion`: tekst `MAJOR.MINOR.PATCH` (zmienna `API_VERSION` funkcji): `1.0.0` w Lab 4, `1.1.0` od Lab 5
- `POST /requests`, treść:
  `{"requestId": "<UUID>", "scenario": "normal" | "transient_once", "payload": {"sku": "SKU-A", "quantity": 2}}`
  - `sku`: `SKU-` + wielkie litery/cyfry, `quantity`: liczba całkowita 1–1000
- Odpowiedzi `POST` (od Lab 5):
  - `202`: zapisano `PENDING` i SQS potwierdził wysyłkę (nagłówek `Location: /requests/{id}`)
  - `200`: zlecenie już `COMPLETED` (te same dane), w odpowiedzi wynik
  - `409`: to samo ID z innymi danymi, `400`: błędny JSON lub wartość spoza kontraktu
  - `503`: zapis się udał, ale brak potwierdzenia z SQS; ponowienie z tym samym ID ponownie wysyła wiadomość
- `GET /requests/{id}`: `200` `{requestId, status, apiVersion}` (+ `result: {decision, reason}` gdy `COMPLETED`) albo `404`
- Statusy: `DRAFT` (Lab 4) → `PENDING` → `COMPLETED`
- Kody `reason`: `IN_STOCK`, `OUT_OF_STOCK`, `UNKNOWN_SKU`
- Kody błędów: `INVALID_JSON`, `INVALID_INPUT`, `NOT_FOUND`, `CONFLICT`, `QUEUE_UNAVAILABLE`

## Wiadomość w kolejce (od Lab 5)
Minimalna treść: `{"requestId": "<UUID>"}`. Dane zlecenia funkcja przetwarzająca czyta z DynamoDB.
To samo `requestId` jest w API, wiadomości, tabeli i logach.

## Moje zasoby
| Lab | Zasób | Nazwa |
|---|---|---|
| 3 | Bucket S3 (prywatny) | `zlecenia-daniel-uwb-2026` |
| 3 | Rola IAM (odczyt prefiksu) | `odczyt-zlecen-daniel` |
| 4 | Tabela DynamoDB | `zlecenia-daniel` |
| 4 | Funkcja Lambda (API) | `zlecenia-api-daniel` |
| 4 | Rola wykonawcza funkcji API | `zlecenia-api-lambda-daniel` |
| 4 | HTTP API | `zlecenia-http-api-daniel` |
| 5 | Kolejka SQS (standard, visibility 60 s) | `zlecenia-kolejka-daniel` |
| 5 | Funkcja Lambda (przetwarzanie) | `zlecenia-processor-daniel` |
| 5 | Rola wykonawcza funkcji przetwarzającej | `zlecenia-processor-lambda-daniel` |
| 5 | Połączenie kolejka → funkcja | event source mapping (batch 5, ReportBatchItemFailures) |
| – | Budżet | `budzet-uwb` (5 USD) |