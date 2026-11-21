# Projekt AWS – asynchroniczne przetwarzanie zleceń

- **Wariant:** zamówienia (`sku`, `quantity`; decyzja `APPROVED` / `REJECTED`)
- **Konto:** własne konto AWS (plan Free z kredytami), praca przez AWS CloudShell
- **Region:** `eu-north-1` (Sztokholm)
- **Oznaczanie zasobów:** nazwy z `-daniel`, tagi `projekt=uwb-chmura`, `wlasciciel=daniel`
- **Prefiks danych:** `student-daniel/`
- LocalStack (`compose.yaml`) służy tylko do lokalnych prób.

## Moje zasoby
| Lab | Zasób | Nazwa |
|---|---|---|
| 3 | Bucket S3 (prywatny) | `zlecenia-daniel-uwb-2026` |
| 3 | Rola IAM (odczyt prefiksu) | `odczyt-zlecen-daniel` |
| – | Budżet | `budzet-uwb` (5 USD) |