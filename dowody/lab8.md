# Lab 8 – Kubernetes, rollback i odbiór projektu

## Część A – lokalny Kubernetes
- Klaster: Docker Desktop, tryb **kubeadm**, kontekst `docker-desktop`, 1 węzeł `Ready` (sprawdzone przed zmianami)
- Manifesty w repo: `k8s/deployment.yaml` (2 repliki, sondy `/health`, limity zasobów, użytkownik nie-root), `k8s/service.yaml` (NodePort `30080`)
- Obrazy: zbudowane lokalnie z commitów, z których CI opublikowało obrazy w ECR:
  - wersja 1: `zlecenia-rules-daniel:2804f97` (2.0.0) – kod z `github.com/daniellegacinski/chmura-projekt#2804f97`
  - wersja 2: `zlecenia-rules-daniel:9f6ea68` (2.0.1) – kod z `#9f6ea68`
  - `imagePullPolicy: Never` – klaster używa obrazów z lokalnego Dockera
- Pobranie bezpośrednio z ECR nie było możliwe: `docker login` na Windows zapisuje hasło w Menedżerze poświadczeń, który odrzuca token ECR („The stub received bad data”). Obrazy zbudowano więc z tych samych commitów i z tymi samymi argumentami co w CI; powiązanie obraz ↔ commit zachowuje tag i pole `commit` w odpowiedzi. Lokalne digesty różnią się od digestów w ECR (inna budowa).

### Dowód 1 – odpowiedzi kontenera w kolejności aktualizacji i rollbacku
Pełny zapis: [`lab8-k8s.txt`](lab8-k8s.txt), skrypt: `testy/lab8-k8s.ps1`. To samo zapytanie `POST /decide {"sku":"SKU-A","quantity":6}`:

| Krok | Obraz w podach | `version` | `commit` | Decyzja |
|---|---|---|---|---|
| Wersja 1 | `2804f97` | `2.0.0` | `2804f97` | `REJECTED / OUT_OF_STOCK` |
| Aktualizacja (`kubectl set image`) | `9f6ea68` | `2.0.1` | `9f6ea68` | `REJECTED / OUT_OF_STOCK` |
| Rollback (`kubectl rollout undo`) | `2804f97` | `2.0.0` | `2804f97` | `REJECTED / OUT_OF_STOCK` |

`kubectl rollout history`: rewizja 2 = `obraz 9f6ea68 (2.0.1)`, rewizja 3 = `obraz 2804f97 (2.0.0)`. Decyzja biznesowa jest poprawna we wszystkich wersjach. Stan końcowy: 2 pody z obrazem `2804f97`.

Uwaga: zaraz po zmianie lista podów zawiera jeszcze stare pody – Python jako proces nr 1 w kontenerze nie reaguje na SIGTERM, więc Kubernetes wyłącza je po 30 s (okres łaski). Ruch obsługują już nowe pody, co widać po odpowiedziach.

## Część B – pokaz w AWS
Pełny zapis: [`lab8-aws.txt`](lab8-aws.txt), skrypt: `testy/lab8-aws.sh`. Nowe zlecenie `cbbae324-4f2c-47c0-8e2d-1deacdf36662` (`SKU-B × 1`).

### Dowód 2 – jedno ID w odpowiedziach API i w logach
| Krok | Wynik |
|---|---|
| `POST /requests` | `202`, `PENDING`, `location: /requests/cbbae324-…` |
| `GET` od razu | `PENDING` |
| `GET` po ~6 s | `COMPLETED`, `APPROVED / IN_STOCK` |
| Powtórzenie `POST` | `200`, wynik zachowany |
| Logi funkcji API | `pending_saved` → `queued` → `found` … → `already_completed` |
| Logi funkcji przetwarzającej | `start_attempt_1` → `decision_saved:APPROVED:IN_STOCK` |
| Rekord w DynamoDB | `COMPLETED`, `attempts = 1` |

**Kto co robi:**
- wiadomość do SQS wysłała funkcja `zlecenia-api-daniel` z rolą `zlecenia-api-lambda-daniel` (`sqs:SendMessage` tylko na tej kolejce),
- kolejkę obsłużyła funkcja `zlecenia-processor-daniel` z rolą `zlecenia-processor-lambda-daniel` (odbiór i usuwanie wiadomości),
- stan końcowy zapisano w tabeli DynamoDB `zlecenia-daniel` (zapis warunkowy `PENDING → COMPLETED`).

**Przerwanie między zapisem w DynamoDB a potwierdzeniem w SQS:**
- Po stronie przetwarzania: jeśli funkcja zapisze wynik, ale przerwie się, zanim SQS uzna wiadomość za obsłużoną, wiadomość wróci do kolejki po visibility timeout (60 s). Kolejne uruchomienie odczyta `COMPLETED` i zakończy bez drugiego zapisu (`already_completed_skip`, pokazane w Lab 5). Gdyby dwa uruchomienia trwały równolegle, zapis warunkowy przepuści tylko jedno.
- Po stronie API: jeśli zapis `PENDING` się udał, a SQS nie potwierdził wysyłki, API zwraca `503`; ponowienie z tym samym ID wysyła wiadomość ponownie i zwraca `202` (pokazane w Lab 5).

**Wersja działającej trasy:** `apiVersion = 2.0.1`, wdrożona przez GitHub Actions z commita `9f6ea68`:
https://github.com/daniellegacinski/chmura-projekt/actions/runs/44928925441

**Wynik analizy z Lab 6:** odsetek odrzuceń biznesowych – `standard` 25%, `limit` 75%, `retry` 0% (zgodny z wynikiem referencyjnym).

**Test uzasadniający poprawność zmian:** `test_quantity_equal_to_stock_is_approved` (`testy/test_rules.py`). Sprawdza granicę limitu (`SKU-A × 5` → `APPROVED`). W Lab 7 celowa zmiana `>` na `>=` została przez niego wykryta – testy na pull requeście nie przeszły i wdrożenie się nie uruchomiło:
https://github.com/daniellegacinski/chmura-projekt/actions/runs/44922317966

## Sprzątanie po odbiorze
Skrypt `infra/sprzatanie.sh` (uruchamiać dopiero po odbiorze): najpierw wstrzymuje przyjmowanie zleceń (usuwa HTTP API), wyłącza połączenie kolejka → funkcja, potem usuwa funkcje, logi, kolejkę, tabelę, bucket, repozytorium ECR, role i dostawcę OIDC. Lokalnie: `kubectl delete -f k8s/`.