"""Client-facing cash discount report PDF (D67-D71), layout v1 — see docs/decisions.md D79."""
from pathlib import Path

from fpdf import FPDF
from fpdf.enums import TableCellFillMode, VAlign

OUT = Path(__file__).resolve().parent / "cash_discount_report_2024_v1.pdf"

MARGIN = 20
TABLE_INSET = 1.0
FONT_BODY = 10
FONT_SMALL = 9
FONT_HEAD = 12
FONT_TITLE = 15
LINE = 5

CHECKLIST_LINE_HEIGHT = 8
CHECKLIST_PADDING = 4
CHECKLIST_ROW_LINES = 5

# Legal names from seeds/raw_vendor_sap.csv (NAME1)
ACME = "Acme Supplies GmbH"
GLOBAL_PARTS = "Global Parts AG"
NORDIC = "Nordic Logistics AB"
FASTPAY = "FastPay Services Ltd"
PRECISION = "Precision Tools SA"
BUDGET_OFFICE = "Budget Office BV"


def vendors_start_with(*names: str) -> str:
    if len(names) == 1:
        return names[0]
    return "\n".join(f"{i}. {name}" for i, name in enumerate(names, 1))


def _pad_cell(text: str, min_lines: int) -> str:
    lines = text.split("\n")
    while len(lines) < min_lines:
        lines.append(" ")
    return "\n".join(lines)


class ReportPdf(FPDF):
    def footer(self) -> None:
        self.set_y(-12)
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 8, f"Page {self.page_no()}/{{nb}}", align="C")


def content_w(pdf: FPDF) -> float:
    return pdf.w - pdf.l_margin - pdf.r_margin


def table_w(pdf: FPDF) -> float:
    return content_w(pdf) - TABLE_INSET


def para(pdf: FPDF, text: str, size: int = FONT_BODY, style: str = "") -> None:
    pdf.set_x(pdf.l_margin)
    pdf.set_font("Helvetica", style, size)
    pdf.multi_cell(content_w(pdf), LINE, text)
    pdf.ln(2)


def heading(pdf: FPDF, text: str) -> None:
    pdf.ln(3)
    pdf.set_x(pdf.l_margin)
    pdf.set_font("Helvetica", "B", FONT_HEAD)
    pdf.multi_cell(content_w(pdf), 6, text)
    pdf.ln(1)


def simple_table(
    pdf: FPDF,
    col_fracs: tuple[float, ...],
    rows: list[tuple[str, ...]],
    line_height: float = 6,
    padding: float = 2,
) -> None:
    tw = table_w(pdf)
    widths = tuple(tw * f for f in col_fracs)
    with pdf.table(
        width=tw,
        col_widths=widths,
        line_height=line_height,
        padding=padding,
        text_align="LEFT",
        v_align=VAlign.T,
        first_row_as_headings=True,
    ) as table:
        for row_cells in rows:
            row = table.row()
            for text in row_cells:
                row.cell(text)
    pdf.ln(2)


def checklist_table(pdf: FPDF, rows: list[tuple[str, str, str, str]]) -> None:
    tw = table_w(pdf)
    col_fracs = (0.17, 0.33, 0.10, 0.40)
    widths = tuple(tw * f for f in col_fracs)
    header = ("Area", "Do next period", "EUR", "Start with")
    with pdf.table(
        width=tw,
        col_widths=widths,
        line_height=CHECKLIST_LINE_HEIGHT,
        padding=CHECKLIST_PADDING,
        text_align="LEFT",
        v_align=VAlign.M,
        first_row_as_headings=True,
        cell_fill_mode=TableCellFillMode.NONE,
    ) as table:
        hdr = table.row()
        for h in header:
            hdr.cell(h)
        for area, action, eur, vendor in rows:
            row = table.row()
            row.cell(_pad_cell(area, CHECKLIST_ROW_LINES))
            row.cell(_pad_cell(action, CHECKLIST_ROW_LINES))
            row.cell(_pad_cell(eur, CHECKLIST_ROW_LINES))
            row.cell(_pad_cell(vendor, CHECKLIST_ROW_LINES))


def main() -> None:
    pdf = ReportPdf(format="A4", unit="mm")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=22)
    pdf.set_margins(MARGIN, MARGIN, MARGIN)
    pdf.add_page()

    pdf.set_x(pdf.l_margin)
    pdf.set_font("Helvetica", "B", FONT_TITLE)
    pdf.multi_cell(content_w(pdf), 7, "Cash discount performance report")
    para(pdf, "Reporting period: 1 January 2024 - 31 December 2024")
    para(pdf, "Currency: EUR")
    para(
        pdf,
        "All durations in this report use calendar days (including weekends).",
        FONT_SMALL,
        "I",
    )

    heading(pdf, "1. Where the discount went")
    para(
        pdf,
        "In the reporting period, 16 invoices were eligible for a cash discount. "
        "Three took the discount, one was set aside under your exclusion rules, "
        "and twelve lost discount opportunity (leakage).",
    )
    simple_table(
        pdf,
        (0.40, 0.16, 0.22, 0.22),
        [
            ("Stage", "Invoices", "Amount (EUR)", "Share of opportunity"),
            ("Discount opportunity (eligible)", "16", "355.21", "100%"),
            ("Discount taken", "3", "135.01", "38%"),
            ("Set aside (excluded)", "1", "30.00", "8%"),
            ("Lost (leakage)", "12", "190.20", "54%"),
        ],
    )
    para(pdf, "Leakage rate: EUR 190.20 lost / EUR 355.21 opportunity = 53.5%.")

    heading(pdf, "2. Where the EUR 190.20 was lost")
    simple_table(
        pdf,
        (0.54, 0.16, 0.30),
        [
            ("Reason", "Invoices", "Lost discount (EUR)"),
            ("Timing (detail in section 5)", "6", "95.80"),
            ("Paid in time but discount not captured", "2", "28.40"),
            ("Terms vs operational capability", "1", "20.00"),
            ("Data quality", "1", "18.00"),
            ("Too little time at intake", "1", "16.00"),
            ("Compressed intake window", "1", "12.00"),
        ],
    )
    para(pdf, "Total lost: EUR 190.20 across 12 invoices.")

    heading(pdf, "4. What to change next period (excluding timing)")
    bullets = [
        "Paid in time but discount not captured (EUR 28.40): "
        "Propose and schedule payment while the discount is still open; confirm discount is posted when paying in window.",
        f"Terms vs capability (EUR 20.00): Align payment terms with how fast you can pay. Start with: {ACME}.",
        f"Data quality (EUR 18.00): Fix missing receipt or linkage on SAP-only intake. Start with: {FASTPAY}.",
        f"Too little time at intake (EUR 16.00): Shorten receipt-to-ready time. Start with: {GLOBAL_PARTS}.",
        f"Compressed intake (EUR 12.00): Expedite when few days remain at intake. Start with: {NORDIC}.",
    ]
    for b in bullets:
        para(pdf, f"- {b}")

    heading(pdf, "5. Timing loss (EUR 95.80)")
    para(
        pdf,
        "This section splits timing-related loss across process steps. "
        "Amounts show how lost discount is attributed across days in each step; "
        "they sum to EUR 95.80 and are for prioritisation, not a recovery forecast.",
    )

    para(pdf, "5.1 Before SAP posting vs payment", FONT_BODY, "B")
    simple_table(
        pdf,
        (0.62, 0.38),
        [
            ("Part of the process", "Timing loss (EUR)"),
            ("Before invoice is posted in SAP", "49.00"),
            ("Payment (after posting)", "46.80"),
        ],
    )
    para(
        pdf,
        "Payment stage: 3 invoices, EUR 46.80 in total, 39 calendar days after the discount deadline in aggregate.",
    )

    para(pdf, "5.2 Before posting - where to focus", FONT_BODY, "B")
    para(
        pdf,
        "Steps are ordered by share of timing loss. Focus on the largest amounts first.",
    )
    para(
        pdf,
        "- Interface / handoff to SAP: largest share for several suppliers - "
        "shorten the gap between approval in Coupa and posting in SAP.",
    )
    para(
        pdf,
        f"- Verification - invoice on hold (EUR 20.00): release holds that are not required. Supplier: {ACME}.",
    )
    para(
        pdf,
        f"- Verification - open dispute (EUR 16.00): resolve disputes faster. Supplier: {GLOBAL_PARTS}.",
    )
    para(
        pdf,
        f"- {PRECISION} (EUR 13.00): most of this loss sits in interface delay "
        "(approved 24 Sep 2024, posted in SAP 8 Oct 2024). Prioritise faster handoff to SAP; "
        "also record rejection reasons when invoices are sent back (short rework cycle).",
    )
    para(
        pdf,
        "Where no specific blocker is recorded in verification or approval, treat the gap as "
        "needing better labelling or investigation, not as proof of normal processing.",
    )

    para(pdf, "5.3 Payment - after the discount deadline", FONT_BODY, "B")
    simple_table(
        pdf,
        (0.50, 0.22, 0.28),
        [
            ("What we saw", "Amount (EUR)", "Priority"),
            ("Waiting to clear after the deadline", "37.80", "Focus first"),
            ("Payment blocked in SAP during the window", "9.00", "Monitor"),
        ],
    )
    para(
        pdf,
        "Waiting to clear (EUR 37.80): spread across:\n"
        + vendors_start_with(
            f"{NORDIC} (EUR 17.80)",
            f"{FASTPAY} (EUR 20.00)",
        )
        + "\nNo single supplier dominates - improve both payment paths.",
    )
    para(
        pdf,
        f"Payment block (EUR 9.00): {FASTPAY} - release blocks during the discount window "
        "or document a decision to forgo discount.",
    )

    heading(pdf, "6. Reference (not counted as leakage)")
    para(pdf, "Discount taken: 3 invoices, EUR 135.01 posted as cash discount.")
    para(
        pdf,
        "Set aside: 1 invoice, EUR 30.00 opportunity excluded at payment (your rules at clearing).",
    )

    heading(pdf, "7. Action checklist for next period")
    para(
        pdf,
        "Amounts are lost discount in this period - use them to prioritise change, not as a savings guarantee.",
        FONT_SMALL,
        "I",
    )
    checklist_table(
        pdf,
        [
            (
                "Data quality",
                "Fix receipt/linkage on SAP-only intake",
                "18.00",
                FASTPAY,
            ),
            (
                "Terms",
                "Align terms with pay cycles",
                "20.00",
                ACME,
            ),
            (
                "Intake",
                "Shorten receipt-to-ready time",
                "16.00",
                GLOBAL_PARTS,
            ),
            (
                "Intake",
                "Expedite when few days at intake",
                "12.00",
                NORDIC,
            ),
            (
                "Timing - before posting",
                "Cut interface delay; resolve disputes and holds",
                "49.00",
                vendors_start_with(ACME, GLOBAL_PARTS, PRECISION),
            ),
            (
                "Timing - payment",
                "Pay while discount open; clear blocks in window",
                "46.80",
                vendors_start_with(NORDIC, FASTPAY),
            ),
            (
                "Capture",
                "Pay in window with discount taken",
                "28.40",
                vendors_start_with(BUDGET_OFFICE, PRECISION),
            ),
        ],
    )

    pdf.add_page()
    heading(pdf, "Timing actions by process order (EUR 95.80)")
    para(pdf, "Use this order for workshops; amounts follow the split in section 5.")
    simple_table(
        pdf,
        (0.30, 0.70),
        [
            ("Step", "Do next period"),
            ("Intake", "Reduce delay before verification starts"),
            (
                "Interface",
                f"Post to SAP soon after approval - top priority for {PRECISION}",
            ),
            ("Verification", "Release holds; resolve disputes quickly"),
            (
                "Approval",
                "Investigate unlabelled waiting time; record rejection reasons",
            ),
            (
                "Payment - after deadline",
                "Schedule payment before deadline where possible; reduce days waiting to clear",
            ),
            (
                "Payment - block",
                "Release SAP payment blocks during the discount window",
            ),
        ],
        line_height=7,
        padding=3,
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(OUT))
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
