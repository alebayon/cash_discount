"""One-page synthetic vendor invoice PDFs for README showcase (vendor-known fields only)."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

from fpdf import FPDF

OUT_DIR = Path(__file__).resolve().parent

MARGIN = 18
FONT_BODY = 10
FONT_SMALL = 9
FONT_HEAD = 11
FONT_TITLE = 14

BUYER = "Portfolio Demo AG"
BUYER_CITY = "80331 Munich, Germany"


@dataclass(frozen=True)
class InvoiceSpec:
    doc_number: str
    vendor_name: str
    street: str
    city_country: str
    vat_id: str
    invoice_date: date
    discount_days: int
    net_days: int
    discount_pct: float
    amount: float
    line_description: str
    po: str


def fmt_money(value: float) -> str:
    return f"{value:,.2f}"


def fmt_long_win(d: date) -> str:
    # Windows strftime lacks %-d
    return f"{d.day} {d.strftime('%B %Y')}"


def build_spec(
    *,
    doc_number: str,
    vendor_name: str,
    street: str,
    city_country: str,
    vat_id: str,
    invoice_date: date,
    discount_days: int,
    net_days: int,
    discount_pct: float,
    amount: float,
    line_description: str,
    po: str,
) -> InvoiceSpec:
    return InvoiceSpec(
        doc_number=doc_number,
        vendor_name=vendor_name,
        street=street,
        city_country=city_country,
        vat_id=vat_id,
        invoice_date=invoice_date,
        discount_days=discount_days,
        net_days=net_days,
        discount_pct=discount_pct,
        amount=amount,
        line_description=line_description,
        po=po,
    )


SPECS: list[InvoiceSpec] = [
    build_spec(
        doc_number="5100000016",
        vendor_name="Acme Supplies GmbH",
        street="Musterstrasse 12",
        city_country="10115 Berlin, Germany",
        vat_id="DE123456789",
        invoice_date=date(2024, 9, 15),
        discount_days=5,
        net_days=25,
        discount_pct=0.02,
        amount=1000.00,
        line_description="Office and facility supplies",
        po="4500127890",
    ),
    build_spec(
        doc_number="5100000017",
        vendor_name="Global Parts AG",
        street="Industrieweg 8",
        city_country="80331 Munich, Germany",
        vat_id="DE987654321",
        invoice_date=date(2024, 9, 1),
        discount_days=10,
        net_days=30,
        discount_pct=0.02,
        amount=800.00,
        line_description="Spare parts and components",
        po="4500131042",
    ),
    build_spec(
        doc_number="5100000018",
        vendor_name="Nordic Logistics AB",
        street="Hamngatan 5",
        city_country="111 22 Stockholm, Sweden",
        vat_id="SE556677889901",
        invoice_date=date(2024, 10, 1),
        discount_days=10,
        net_days=30,
        discount_pct=0.02,
        amount=600.00,
        line_description="Freight and warehousing services",
        po="4500132201",
    ),
    build_spec(
        doc_number="5100000019",
        vendor_name="FastPay Services Ltd",
        street="10 Fleet Street",
        city_country="London EC1A 1BB, United Kingdom",
        vat_id="GB123456789",
        invoice_date=date(2024, 10, 15),
        discount_days=10,
        net_days=30,
        discount_pct=0.02,
        amount=550.00,
        line_description="Payment processing services",
        po="4500133308",
    ),
    build_spec(
        doc_number="5100000020",
        vendor_name="Precision Tools SA",
        street="Rue de la Fabrication 14",
        city_country="69001 Lyon, France",
        vat_id="FR12345678901",
        invoice_date=date(2024, 11, 1),
        discount_days=10,
        net_days=30,
        discount_pct=0.02,
        amount=750.00,
        line_description="CNC tooling and calibration",
        po="4500134415",
    ),
]


class InvoicePdf(FPDF):
    def footer(self) -> None:
        self.set_y(-14)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(100, 100, 100)
        self.cell(0, 6, "Synthetic demonstration document - not a real invoice", align="C")


def render(spec: InvoiceSpec, path: Path) -> None:
    inv_no = f"INV-{spec.doc_number}"
    discount_deadline = spec.invoice_date + timedelta(days=spec.discount_days)
    net_due = spec.invoice_date + timedelta(days=spec.net_days)
    discount_amt = round(spec.amount * spec.discount_pct, 2)
    pay_with_discount = round(spec.amount - discount_amt, 2)
    pct_label = int(spec.discount_pct * 100)

    pdf = InvoicePdf()
    pdf.set_auto_page_break(auto=False)
    pdf.set_margins(MARGIN, MARGIN, MARGIN)
    pdf.add_page()
    w = pdf.w - pdf.l_margin - pdf.r_margin

    pdf.set_fill_color(245, 245, 245)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 80)
    pdf.cell(w, 7, "SYNTHETIC DEMONSTRATION ONLY - FICTIONAL DATA", fill=True, align="C")
    pdf.ln(10)
    pdf.set_text_color(0, 0, 0)

    pdf.set_font("Helvetica", "B", FONT_TITLE)
    pdf.cell(w * 0.55, 8, spec.vendor_name)
    pdf.set_font("Helvetica", "", FONT_BODY)
    pdf.cell(w * 0.45, 8, "Bill to:", align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", FONT_SMALL)
    pdf.cell(w * 0.55, 5, spec.street)
    pdf.cell(w * 0.45, 5, BUYER, align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(w * 0.55, 5, spec.city_country)
    pdf.cell(w * 0.45, 5, BUYER_CITY, align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(w * 0.55, 5, f"VAT ID: {spec.vat_id}")
    pdf.ln(8)

    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(w, 10, "INVOICE", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)

    for label, value in [
        ("Invoice number", inv_no),
        ("Invoice date", fmt_long_win(spec.invoice_date)),
    ]:
        pdf.set_font("Helvetica", "", FONT_SMALL)
        pdf.set_text_color(90, 90, 90)
        pdf.cell(w * 0.32, 6, label)
        pdf.set_text_color(0, 0, 0)
        pdf.set_font("Helvetica", "B", FONT_BODY)
        pdf.cell(w * 0.68, 6, value, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(6)

    pdf.set_font("Helvetica", "B", FONT_HEAD)
    pdf.cell(w, 7, "Payment terms", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", FONT_BODY)
    terms = (
        f"{pct_label}% cash discount if payment is received by "
        f"{fmt_long_win(discount_deadline)} ({spec.discount_days} days from invoice date). "
        f"Otherwise net amount due by {fmt_long_win(net_due)} "
        f"({spec.net_days} days from invoice date)."
    )
    pdf.multi_cell(w, 5, terms)
    pdf.ln(4)

    pdf.set_fill_color(230, 230, 230)
    pdf.set_font("Helvetica", "B", FONT_SMALL)
    pdf.cell(w * 0.62, 7, "Description", border=1, fill=True)
    pdf.cell(w * 0.13, 7, "Qty", border=1, fill=True, align="C")
    pdf.cell(w * 0.25, 7, "Amount (EUR)", border=1, fill=True, align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", FONT_BODY)
    pdf.cell(w * 0.62, 8, f"{spec.line_description} - PO {spec.po}", border=1)
    pdf.cell(w * 0.13, 8, "1", border=1, align="C")
    pdf.cell(w * 0.25, 8, fmt_money(spec.amount), border=1, align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)

    pdf.set_font("Helvetica", "B", FONT_BODY)
    pdf.cell(w * 0.75, 7, "Subtotal", align="R")
    pdf.cell(w * 0.25, 7, fmt_money(spec.amount), align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", FONT_BODY)
    pdf.cell(
        w * 0.75,
        6,
        f"Cash discount ({pct_label}% if paid by {discount_deadline.strftime('%d %b %Y')})",
        align="R",
    )
    pdf.cell(w * 0.25, 6, f"- {fmt_money(discount_amt)}", align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "B", FONT_HEAD)
    pdf.cell(w * 0.75, 8, "Amount due with discount", align="R")
    pdf.cell(w * 0.25, 8, fmt_money(pay_with_discount), align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", FONT_SMALL)
    pdf.cell(w * 0.75, 6, "Net amount (if paid after discount period)", align="R")
    pdf.cell(w * 0.25, 6, fmt_money(spec.amount), align="R", new_x="LMARGIN", new_y="NEXT")

    pdf.ln(10)
    pdf.set_font("Helvetica", "", FONT_SMALL)
    pdf.multi_cell(
        w,
        5,
        f"Please remit to: Demo Bank AG, IBAN DE00 1234 5678 9012 3456 78, reference {inv_no}.",
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(path))


def main() -> None:
    for spec in SPECS:
        out = OUT_DIR / f"{spec.doc_number}.pdf"
        render(spec, out)
        print(f"Wrote {out}")


if __name__ == "__main__":
    main()
