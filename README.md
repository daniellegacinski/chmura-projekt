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
- `apiVersion`: tekst `MAJOR.MINOR.PATCH` (zmienna `API_VERSION` funkcji):
  `1.0.0` w Lab 4, `1.1.0` od Lab 5, od Lab 7 ustawiana przez CI/CD z pliku `VERSION` (`2.0.0`, obecnie `2.0.1`)
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

## Reguły biznesowe (od Lab 6)
- Moduł: `src/processor/rules.py` (bez SQS i DynamoDB)
- Stan magazynu (jeden dla wszystkich zleceń): `SKU-A` = 5, `SKU-B` = 2
- `quantity` ≤ stan → `APPROVED` / `IN_STOCK`; większa ilość → `REJECTED` / `OUT_OF_STOCK`; inny SKU → `REJECTED` / `UNKNOWN_SKU`
- `scenario=transient_once`: pierwsza próba kończy się kontrolowanym błędem, wiadomość wraca do kolejki, kolejna próba stosuje zwykłe reguły
- Chwilowy błąd nie jest odrzuceniem biznesowym: zlecenie zostaje `PENDING` do udanej próby
- Testy: `python3 -m unittest discover -s testy -p 'test_*.py' -v`

## CI/CD (od Lab 7)
- Workflow: `.github/workflows/ci-cd.yml`
  - testy na każdym pull requeście i zmianie na `main`
  - wdrożenie tylko po zmianie na `main` i tylko gdy testy przejdą: aktualizacja funkcji `zlecenia-api-daniel` + obraz w ECR
- Wersja API: plik `VERSION`
- Dostęp do AWS przez OIDC (bez kluczy), rola `github-deploy-daniel`, ARN w sekrecie `AWS_ROLE_ARN`
- Obraz z modułem reguł (`container/`): prywatne ECR `zlecenia-rules-daniel`, tag = 7 znaków SHA commita
- Commity z samymi dowodami mają w opisie `[skip ci]`, żeby nie uruchamiać wdrożenia

## Kubernetes (Lab 8)
- Lokalny klaster: Docker Desktop, tryb kubeadm, kontekst `docker-desktop`
- Manifesty: `k8s/deployment.yaml` (2 repliki, sondy `/health`), `k8s/service.yaml` (NodePort `30080`)
- Test aktualizacji i rollbacku: `powershell -ExecutionPolicy Bypass -File testy\lab8-k8s.ps1`
- Kolejność: wersja 1 (`2804f97`, 2.0.0) → wersja 2 (`9f6ea68`, 2.0.1) → rollback do wersji 1

## Sprzątanie po odbiorze
- AWS: `bash infra/sprzatanie.sh` w CloudShell (pyta o potwierdzenie; najpierw wstrzymuje przyjmowanie zleceń i wyłącza połączenie kolejka → funkcja)
- Lokalnie: `kubectl delete -f k8s/`

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
| 7 | Dostawca OIDC | `token.actions.githubusercontent.com` |
| 7 | Rola wdrożeniowa GitHub Actions | `github-deploy-daniel` |
| 7 | Repozytorium ECR (prywatne) | `zlecenia-rules-daniel` (obrazy `2804f97` = 2.0.0, `9f6ea68` = 2.0.1; `5eb3d46` błędny) |
| 8 | Lokalny Kubernetes (Docker Desktop, kubeadm) | `k8s/deployment.yaml`, `k8s/service.yaml` (NodePort 30080) |
| – | Budżet | `budzet-uwb` (5 USD) |