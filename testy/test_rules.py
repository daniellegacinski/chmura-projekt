"""Testy lokalne modułu reguł – Lab 6.

Uruchomienie: python3 -m unittest discover -s testy -p 'test_*.py' -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "processor"))

from rules import TransientFailure, decide  # noqa: E402

APPROVED = {"decision": "APPROVED", "reason": "IN_STOCK"}
OUT_OF_STOCK = {"decision": "REJECTED", "reason": "OUT_OF_STOCK"}
UNKNOWN_SKU = {"decision": "REJECTED", "reason": "UNKNOWN_SKU"}


class TestRules(unittest.TestCase):
    def test_quantity_equal_to_stock_is_approved(self):
        """Granica limitu: ilość równa stanowi magazynu jest zatwierdzona."""
        self.assertEqual(decide("SKU-A", 5, "normal", 1), APPROVED)
        self.assertEqual(decide("SKU-B", 2, "normal", 1), APPROVED)

    def test_quantity_above_stock_is_rejected(self):
        """Ilość o 1 większa niż stan magazynu jest odrzucona."""
        self.assertEqual(decide("SKU-A", 6, "normal", 1), OUT_OF_STOCK)
        self.assertEqual(decide("SKU-B", 3, "normal", 1), OUT_OF_STOCK)

    def test_unknown_sku_is_rejected(self):
        self.assertEqual(decide("SKU-X", 1, "normal", 1), UNKNOWN_SKU)

    def test_transient_once_fails_on_first_attempt(self):
        with self.assertRaises(TransientFailure):
            decide("SKU-A", 1, "transient_once", 1)

    def test_transient_once_uses_normal_rules_on_retry(self):
        self.assertEqual(decide("SKU-A", 4, "transient_once", 2), APPROVED)
        self.assertEqual(decide("SKU-B", 3, "transient_once", 2), OUT_OF_STOCK)

    def test_normal_scenario_never_fails_transiently(self):
        self.assertEqual(decide("SKU-A", 1, "normal", 1), APPROVED)

    def test_reference_sample_gives_expected_rejections(self):
        """Cała próbka z Lab 3: 1/4 standard, 3/4 limit, 0/4 retry."""
        sample = [
            ("standard", "SKU-A", 1), ("standard", "SKU-A", 3), ("standard", "SKU-B", 2), ("standard", "SKU-B", 3),
            ("limit", "SKU-A", 5), ("limit", "SKU-A", 6), ("limit", "SKU-B", 4), ("limit", "SKU-X", 1),
            ("retry", "SKU-A", 1), ("retry", "SKU-A", 4), ("retry", "SKU-B", 1), ("retry", "SKU-B", 2),
        ]
        rejected = {"standard": 0, "limit": 0, "retry": 0}
        for group, sku, quantity in sample:
            scenario = "transient_once" if group == "retry" else "normal"
            attempt = 2 if group == "retry" else 1
            if decide(sku, quantity, scenario, attempt)["decision"] == "REJECTED":
                rejected[group] += 1
        self.assertEqual(rejected, {"standard": 1, "limit": 3, "retry": 0})


if __name__ == "__main__":
    unittest.main()