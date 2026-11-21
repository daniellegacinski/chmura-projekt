# Lab 3 – IAM i prywatne dane w S3

## Środowisko
- Własne konto AWS, region `eu-north-1`, komendy uruchamiane w AWS CloudShell
- Numer konta w dowodach zastąpiony `XXXXXXXXXXXX`

## Zasoby
| Zasób | Nazwa | Uwagi |
|---|---|---|
| Bucket S3 | `zlecenia-daniel-uwb-2026` | Block Public Access: wszystkie 4 opcje `true` |
| Mój plik | `student-daniel/input/zlecenia.csv` | nagłówek + 12 rekordów (wariant zamówienia) |
| Obiekt kontrolny | `kontrola/kontrolny.csv` | poza zakresem odczytu roli |
| Rola | `odczyt-zlecen-daniel` | polityka `odczyt-prefiksu` (`iam/odczyt-policy.json`) |

## Uprawnienia roli
- `s3:GetObject` tylko na `zlecenia-daniel-uwb-2026/student-daniel/*`
- `s3:ListBucket` tylko z warunkiem `s3:prefix = student-daniel/*`
- Odczyt i listowanie to osobne uprawnienia, więc sprawdzam je osobno.
- Prefiks `kontrola/` nie jest objęty żadnym `Allow`, więc AWS domyślnie odmawia.

## Dowód
Pełny zapis: [`lab3-test.txt`](lab3-test.txt), skrypt: [`../testy/lab3-test.sh`](../testy/lab3-test.sh).

| # | Tożsamość | Operacja | Wynik |
|---|---|---|---|
| 1 | `AccountFullAccessRole` (administrator) | sprawdzenie tożsamości | – |
| 2 | `odczyt-zlecen-daniel/test-odczytu` | sprawdzenie tożsamości | rola przyjęta |
| 3 | `odczyt-zlecen-daniel` | `GetObject student-daniel/input/zlecenia.csv` | ✅ nagłówek + 12 rekordów |
| 4 | `odczyt-zlecen-daniel` | `GetObject kontrola/kontrolny.csv` | ❌ `AccessDenied` |
| 5 | `odczyt-zlecen-daniel` | `ListBucket` prefiks `student-daniel/` | ✅ widoczny plik |
| 6 | `odczyt-zlecen-daniel` | `ListBucket` prefiks `kontrola/` | ❌ `AccessDenied` |

Oba odczyty (3 i 4) wykonała ta sama rola. Różnią się tylko prefiksem klucza.