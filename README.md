# Projekt AWS – asynchroniczne przetwarzanie zleceń

- **Wariant:** zamówienia (`sku`, `quantity`; decyzja `APPROVED` / `REJECTED`)
- **Konto:** własne konto AWS (plan Free z kredytami), praca przez AWS CloudShell
- **Region:** `eu-north-1` (Sztokholm)
- **Oznaczanie zasobów:** nazwy z `-daniel`, tagi `projekt=uwb-chmura`, `wlasciciel=daniel`
- **Prefiks danych:** `student-daniel/`
- LocalStack (`compose.yaml`) służy tylko do lokalnych prób.

## Kontrakt API (od Lab 4)
- Adres: `https://<api-id>.execute-api.eu-north-1.amazonaws.com` (HTTP API, etap `$default`)
- Dostęp do tras: bez autoryzacji (`NONE`), dane wyłącznie syntetyczne
- `apiVersion`: tekst w formacie `MAJOR.MINOR.PATCH`, np. `"1.0.0"` (zmienna środowiskowa `API_VERSION` funkcji)
- `POST /requests`, treść:
  `{"requestId": "<UUID>", "scenario": "normal" | "transient_once", "payload": {"sku": "SKU-A", "quantity": 2}}`
  - `sku`: `SKU-` + wielkie litery/cyfry, `quantity`: liczba całkowita 1–1000
- Odpowiedzi `POST`: `201` nowy DRAFT (nagłówek `Location: /requests/{id}`), `200` powtórzenie z tymi samymi danymi, `409` to samo ID z innymi danymi, `400` błędny JSON lub wartość spoza kontraktu
- `GET /requests/{id}`: `200` `{requestId, status, apiVersion}` albo `404`
- Statusy: `DRAFT` (Lab 4), `PENDING`, `COMPLETED`
- Kody `reason` (od Lab 5/6): `IN_STOCK`, `OUT_OF_STOCK`, `UNKNOWN_SKU`
- Kody błędów: `INVALID_JSON`, `INVALID_INPUT`, `NOT_FOUND`, `CONFLICT`

## Moje zasoby
| Lab | Zasób | Nazwa |
|---|---|---|
| 3 | Bucket S3 (prywatny) | `zlecenia-daniel-uwb-2026` |
| 3 | Rola IAM (odczyt prefiksu) | `odczyt-zlecen-daniel` |
| 4 | Tabela DynamoDB | `zlecenia-daniel` |
| 4 | Funkcja Lambda (API) | `zlecenia-api-daniel` |
| 4 | Rola wykonawcza funkcji API | `zlecenia-api-lambda-daniel` |
| 4 | HTTP API | `zlecenia-http-api-daniel` |
| – | Budżet | `budzet-uwb` (5 USD) |