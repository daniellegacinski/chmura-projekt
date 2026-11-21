"""Reguły biznesowe (wariant: zamówienia) – Lab 6.

Czysta logika: bez SQS i DynamoDB, więc da się ją testować lokalnie
i użyć później w kontenerze (Lab 7).
"""

# Jeden stały stan magazynu: każde zlecenie oceniamy względem tego samego stanu.
STOCK = {"SKU-A": 5, "SKU-B": 2}


class TransientFailure(Exception):
    """Kontrolowany, chwilowy błąd pierwszej próby (scenario=transient_once)."""


def decide(sku, quantity, scenario, attempt):
    """Zwraca {"decision", "reason"} albo rzuca TransientFailure.

    attempt – numer próby przetworzenia tego zlecenia (1, 2, ...).
    """
    if scenario == "transient_once" and attempt == 1:
        raise TransientFailure("kontrolowany błąd pierwszej próby")
    if sku not in STOCK:
        return {"decision": "REJECTED", "reason": "UNKNOWN_SKU"}
    if quantity > STOCK[sku]:
        return {"decision": "REJECTED", "reason": "OUT_OF_STOCK"}
    return {"decision": "APPROVED", "reason": "IN_STOCK"}