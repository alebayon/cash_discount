# Stakeholder cash discount report (PDF)

**Content spec:** `docs/decisions.md` — D67–D71 (narrative), D79–D81 (PDF v1 layout).

**Canonical v1 (not final design):**

| Artifact | Path |
|----------|------|
| Sample PDF | `cash_discount_report_2024_v1.pdf` |
| Generator | `_generate_cash_discount_report_2024_v1.py` |

Regenerate after editing the script:

```bash
pip install fpdf2
python reports/_generate_cash_discount_report_2024_v1.py
```

v1 uses embedded curriculum numbers and vendor legal names from `seeds/raw_vendor_sap.csv` (`NAME1`). Mart-driven export is deferred (D81).
