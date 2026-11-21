# Lab 7 – Docker i wdrożenie z GitHub Actions

## Kontener z modułem reguł
- `container/app.py` – interfejs HTTP wokół `src/processor/rules.py` (bez SQS i DynamoDB): `POST /decide` zwraca decyzję, `version` i `commit`
- `container/Dockerfile` – `python:3.12-slim`, użytkownik `nobody`, architektura `linux/amd64` (zgodna z lokalnym klastrem)
- `.dockerignore` wyklucza m.in. `.env`

Sprawdzenie lokalne ([`lab7-kontener.txt`](lab7-kontener.txt)) – te same decyzje co moduł z Lab 6:

| Wejście | Kontener | Lab 6 |
|---|---|---|
| `SKU-A × 5` | `APPROVED / IN_STOCK` | O05 `APPROVED / IN_STOCK` |
| `SKU-A × 6` | `REJECTED / OUT_OF_STOCK` | O06 `REJECTED / OUT_OF_STOCK` |
| `SKU-X × 1` | `REJECTED / UNKNOWN_SKU` | O08 `REJECTED / UNKNOWN_SKU` |

## GitHub Actions (`.github/workflows/ci-cd.yml`)
- **`testy`** – na każdym pull requeście i zmianie na `main`: `python -m unittest` (7 testów)
- **`wdrozenie`** – `needs: testy`, tylko `push` na `main`: aktualizuje kod **istniejącej** funkcji `zlecenia-api-daniel`, ustawia `API_VERSION` z pliku `VERSION`, buduje i publikuje obraz w prywatnym ECR z tagiem = 7 znaków SHA commita
- Pull request: wdrożenie pomijane (`skipped`)

Przebieg z nieudanym testem (celowo `>=` zamiast `>` w regule – wykrył go `test_quantity_equal_to_stock_is_approved`, wdrożenie nie ruszyło):
https://github.com/daniellegacinski/chmura-projekt/actions/runs/44922317966

## Dostęp GitHub → AWS przez OIDC (bez kluczy)
- Dostawca tożsamości `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`
- Rola `github-deploy-daniel` – osobna od ról wykonawczych funkcji; zaufanie tylko dla tego repozytorium i gałęzi `main`:
  `repo:daniellegacinski@240736078/chmura-projekt@1466500022:ref:refs/heads/main`
- Uprawnienia (`infra/lab7-deploy-policy.json`): `lambda:UpdateFunctionCode/UpdateFunctionConfiguration/GetFunction*` tylko na funkcji API, publikacja obrazu tylko do repozytorium `zlecenia-rules-daniel`, `ecr:GetAuthorizationToken`
- ARN roli trzymany jako sekret `AWS_ROLE_ARN`; numer konta maskowany w logach

**Napotkany problem:** pierwsze wdrożenie odrzucone (`Not authorized to perform sts:AssumeRoleWithWebIdentity`). CloudTrail pokazał, że GitHub wysyła `sub` ze stałymi ID właściciela i repozytorium (`daniellegacinski@240736078/chmura-projekt@1466500022`), a warunek roli zawierał samą nazwę. Po poprawie warunku ponowne uruchomienie przeszło.

## Dowód 1 – udane wdrożenie i obraz w ECR
Wdrożenie wersji 2.0.0 (merge PR #1, commit `2804f97`):
https://github.com/daniellegacinski/chmura-projekt/actions/runs/44922974832

Wdrożenie wersji 2.0.1 (commit `5eb3d46`):
https://github.com/daniellegacinski/chmura-projekt/actions/runs/44924926187

Prywatne ECR `zlecenia-rules-daniel` (tagi niezmienne, skanowanie przy wysyłce):

| Tag (commit) | Wersja | Digest |
|---|---|---|
| `2804f97` | 2.0.0 | `sha256:1686c64ba60f8f1bccf85b4bc32f20dea3c27c1b29cca0c15f56bcea5084a0b5` |
| `5eb3d46` | 2.0.1 | `sha256:cef1028daf9e2109cb39e0b8dd6c655f29657974be7baba465a0e32202690858` |

Oba obrazy odpowiadają rozróżnialną wersją (`"version"`) – potrzebne do aktualizacji i rollbacku w Lab 8.

## Dowód 2 – odpowiedzi HTTP przed i po wdrożeniu
To samo zlecenie (O01 z Lab 6, `d342f5a7-…`) pod tym samym adresem API:

| | Przed ([`lab7-przed.txt`](lab7-przed.txt)) | Po ([`lab7-po.txt`](lab7-po.txt)) |
|---|---|---|
| Czas | 15:41 UTC | 16:28 UTC |
| `apiVersion` | `1.1.0` | **`2.0.0`** |
| Wynik | `APPROVED / IN_STOCK` | `APPROVED / IN_STOCK` (bez zmian) |