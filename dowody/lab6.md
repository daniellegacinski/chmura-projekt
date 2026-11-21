# Lab 6 – reguły biznesowe i analiza wyników

## Reguły (wariant: zamówienia)
- Moduł: `src/processor/rules.py` – bez SQS i DynamoDB, wywoływany z testów i z funkcji Lambda
- Stan magazynu (jeden dla wszystkich zleceń): `SKU-A` = 5, `SKU-B` = 2
- `quantity` ≤ stan → `APPROVED / IN_STOCK`; większa ilość → `REJECTED / OUT_OF_STOCK`; nieznany SKU → `REJECTED / UNKNOWN_SKU`
- `transient_once`: pierwsza próba kończy się kontrolowanym błędem (`TransientFailure`), wiadomość wraca do kolejki po visibility timeout (60 s), druga próba stosuje zwykłe reguły

## Testy lokalne
`python3 -m unittest discover -s testy -p 'test_*.py' -v` – 7/7 OK (`testy/test_rules.py`), m.in.:
- granica limitu: `SKU-A × 5` i `SKU-B × 2` → `APPROVED`
- przekroczenie: `SKU-A × 6` i `SKU-B × 3` → `REJECTED / OUT_OF_STOCK`
- nieznany produkt: `SKU-X` → `REJECTED / UNKNOWN_SKU`
- `transient_once`: błąd w próbie 1, zwykłe reguły w próbie 2

**Test, który zweryfikował zmianę:** `test_quantity_equal_to_stock_is_approved`. Wykrywa błąd „o jeden” – gdyby reguła miała `quantity >= stan` zamiast `quantity > stan`, zamówienie dokładnie na cały stan (np. `SKU-A × 5`) zostałoby błędnie odrzucone.

`infra/lab6-deploy.sh` wdraża nową wersję funkcji dopiero po przejściu testów.

## Przypadki kontrolowane w AWS
| Przypadek | Zlecenie | Wynik |
|---|---|---|
| Zatwierdzenie | O01 `SKU-A × 1` | `APPROVED / IN_STOCK` |
| Odrzucenie | O06 `SKU-A × 6` | `REJECTED / OUT_OF_STOCK` |
| Chwilowy błąd | O09 `transient_once`, ID `05bd661b-…` | 2 próby, wynik `APPROVED / IN_STOCK` |

Logi funkcji przetwarzającej dla O09 (to samo ID w obu próbach):
```
start_attempt_1
transient_failure_attempt_1
start_attempt_2
decision_saved:APPROVED:IN_STOCK
```
`GET /requests/05bd661b-…` → `COMPLETED`, `APPROVED / IN_STOCK`.

## Analiza próbki z S3
Próbka `s3://zlecenia-daniel-uwb-2026/student-daniel/input/zlecenia.csv` (12 rekordów) wysłana do API z nowymi UUID.
Połączenie wejścia z wynikami: [`lab6-wyniki.csv`](lab6-wyniki.csv) (`caseId`, `group`, `requestId`, decyzja). Skrypt: `analiza/lab6_analiza.py`.
Liczona jest jedna końcowa decyzja na UUID (nie liczba prób).

| Grupa | Zakończone | Odrzucone biznesowo | Odsetek |
|---|---|---|---|
| `standard` | 4 | 1 | 25% |
| `limit` | 4 | 3 | 75% |
| `retry` | 4 | 0 | 0% |

Wynik zgodny z tabelą referencyjną z treści laboratorium. Wszystkie 12 zleceń zakończone.

**Sprawdzenie ręczne (grupa `limit`):** O06 – `SKU-A`, `quantity = 6`, stan `SKU-A = 5` → 6 > 5 → `REJECTED / OUT_OF_STOCK`. Zgodne z wynikiem z API.

## Wniosek
Wyróżnia się grupa `limit` (75% odrzuceń). Jej zamówienia celowo leżą na granicy stanu magazynu lub ją przekraczają: `SKU-A × 6` i `SKU-B × 4` przekraczają stan, a `SKU-X` nie istnieje. Jedyne zatwierdzone (`SKU-A × 5`) jest dokładnie na granicy. O wyniku decydują więc dwa wejścia: kod produktu (`sku`) i to, czy `quantity` mieści się w stanie magazynu.
Grupa `retry` ma 0% odrzuceń, bo wszystkie jej ilości mieszczą się w stanie. Kontrolowany błąd pierwszej próby nie jest odrzuceniem biznesowym – zlecenia czekały jako `PENDING` ok. 60 s i po ponowieniu zostały zatwierdzone.