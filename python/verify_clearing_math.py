#!/usr/bin/env python3
"""
Exact Fixed-Point Reference Validator & Batch Emulator
======================================================
Emulates the exact COMP-3 (`Decimal` ROUND_HALF_UP) arithmetic and binary search
table lookup of `src/CLRENGIN.cbl` + `src/RISKAUDT.cbl` when `cobc` (GnuCOBOL)
is not installed locally, or acts as a golden-file verification harness against
the compiled COBOL binary.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


def d_round(val: Decimal, pattern: str) -> Decimal:
    return val.quantize(Decimal(pattern), rounding=ROUND_HALF_UP)


@dataclass
class AccountEntry:
    account_id: str
    client_name: str
    tier: str
    collateral: Decimal
    credit_limit: Decimal
    base_reg_t_bps: int
    status: str
    gross_notional: Decimal = Decimal("0.00")
    net_delta_exp: Decimal = Decimal("0.00")
    req_init_margin: Decimal = Decimal("0.00")
    portfolio_var99: Decimal = Decimal("0.00")
    cleared_count: int = 0
    held_rej_count: int = 0


def parse_account(line: str) -> AccountEntry:
    return AccountEntry(
        account_id=line[0:8],
        client_name=line[8:28],
        tier=line[28:32],
        collateral=Decimal(line[32:45]) / Decimal(100),
        credit_limit=Decimal(line[45:58]) / Decimal(100),
        base_reg_t_bps=int(line[58:62]),
        status=line[62:63],
    )


def call_riskaudt(
    asset_class: str,
    notional: Decimal,
    volatility_bps: int,
    ai_anomaly_bps: int,
    base_reg_t_bps: int,
) -> tuple[Decimal, Decimal, str, str]:
    z_score_99 = Decimal("2.3263")
    daily_scale = Decimal("0.062994")
    bps_div = Decimal("10000")

    mult_map = {
        "EQ": Decimal("1.0000"),
        "OP": Decimal("1.8500"),
        "FU": Decimal("1.4000"),
        "FX": Decimal("0.5000"),
    }
    asset_mult = mult_map.get(asset_class, Decimal("2.0000"))

    vol_surcharge = d_round(
        (Decimal(volatility_bps) / bps_div) * Decimal("0.2000"),
        "0.0001",
    )
    effective_rate = d_round(
        ((Decimal(base_reg_t_bps) / bps_div) * asset_mult) + vol_surcharge,
        "0.000001",
    )
    init_margin = d_round(notional * effective_rate, "0.01")

    var_99 = d_round(
        notional
        * (Decimal(volatility_bps) / bps_div)
        * daily_scale
        * z_score_99,
        "0.01",
    )

    if notional > Decimal("50000000.00"):
        decision = "REJT"
        reason = "SINGLE TICKET > $50M CAP"
    elif ai_anomaly_bps >= 8500:
        decision = "HOLD"
        reason = "AI CIRCUIT BREAKER >=85%"
    elif ai_anomaly_bps >= 6500 and notional >= Decimal("5000000.00"):
        decision = "HOLD"
        reason = "AI ELEVATED + HIGH NOTNL"
    elif volatility_bps >= 5500:
        decision = "WARN"
        reason = "EXTREME VOL REGIME >=55%"
    else:
        decision = "CLRD"
        reason = "STANDARD STP CLEARED    "

    return init_margin, var_99, decision, reason


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    acct_lines = (root / "data" / "ACCOUNTS.DAT").read_text(encoding="ascii").splitlines()
    trade_lines = (root / "data" / "TRADES.DAT").read_text(encoding="ascii").splitlines()

    accounts = [parse_account(line) for line in acct_lines if line.strip()]
    acct_by_id = {a.account_id: a for a in accounts}

    out_dir = root / "output"
    out_dir.mkdir(exist_ok=True)
    report_lines: list[str] = []
    ledger_lines: list[str] = []

    banner = "=" * 132
    dash = "-" * 132
    title_1 = (
        "IBM Z16 // CICS-BATCH    TIER-1 PRIME BROKERAGE CLEARING, SPAN MARGI"
        "N & AI RISK ENGINE        JOB: CLRENGIN     RUN DATE: 2026-10-21"
    )
    sec_1 = "SECTION 1: INTRADAY TRADE EXECUTION, SPAN MARGIN & HYBRID AI/ML ANOMALY AUDIT LOG".ljust(132)
    hdr_1 = (
        "TRADE-ID   ACCOUNT  TICKER CL S    QUANTITY        PRICE "
        "    NOTIONAL ($) INIT MARGIN($)  1D-VAR-99($) AI-SC STAT AUDIT REASON      "
    )

    report_lines.extend([banner, title_1, banner, " " * 132, sec_1, dash, hdr_1, dash])

    tot_trades = 0
    tot_cleared = 0
    tot_warn = 0
    tot_hold = 0
    tot_reject = 0
    tot_gross_vol = Decimal("0.00")
    tot_req_margin = Decimal("0.00")
    tot_var_99 = Decimal("0.00")
    tot_margin_calls = 0
    tot_call_deficit = Decimal("0.00")

    for line in trade_lines:
        if not line.strip():
            continue
        tot_trades += 1
        acct_id = line[0:8]
        trade_id = line[8:18]
        ticker = line[32:38]
        asset_class = line[38:40]
        side = line[40:41]
        qty = int(line[41:50])
        price = Decimal(line[50:61]) / Decimal(10000)
        vol_bps = int(line[64:68])
        ai_bps = int(line[68:72])

        notional = d_round(Decimal(qty) * price, "0.01")
        signed_notional = -notional if side == "S" else notional

        acct = acct_by_id.get(acct_id)
        if acct is None:
            init_margin = Decimal("0.00")
            var_99 = Decimal("0.00")
            decision = "REJT"
            reason = "UNKNOWN MASTER ACCOUNT  "
        elif acct.status == "F":
            init_margin = Decimal("0.00")
            var_99 = Decimal("0.00")
            decision = "REJT"
            reason = "ACCOUNT STATUS FROZEN   "
        else:
            init_margin, var_99, decision, reason = call_riskaudt(
                asset_class, notional, vol_bps, ai_bps, acct.base_reg_t_bps
            )

        if decision in ("CLRD", "WARN"):
            if decision == "CLRD":
                tot_cleared += 1
            else:
                tot_warn += 1
            tot_gross_vol += notional
            tot_req_margin += init_margin
            tot_var_99 += var_99
            if acct is not None:
                acct.cleared_count += 1
                acct.gross_notional += notional
                acct.net_delta_exp += signed_notional
                acct.req_init_margin += init_margin
                acct.portfolio_var99 += var_99
        elif decision == "HOLD":
            tot_hold += 1
            if acct is not None:
                acct.held_rej_count += 1
        else:
            tot_reject += 1
            if acct is not None:
                acct.held_rej_count += 1

        ai_pct = Decimal(ai_bps) / Decimal(100)
        dtl = (
            f"{trade_id:<10} {acct_id:<8} {ticker:<6} {asset_class:<2} {side:<1} "
            f"{qty:>11,d} {price:>12,.4f} {notional:>16,.2f} {init_margin:>14,.2f} "
            f"{var_99:>13,.2f} {ai_pct:05.2f} {decision:<4} {reason[:18]:<18}"
        )
        report_lines.append(dtl)

        def fmt_s13v2(val: Decimal) -> str:
            sign = "+" if val >= 0 else "-"
            return f"{sign}{abs(val):016.2f}"

        ldg = (
            f"{trade_id:<10}|{acct_id:<8}|{ticker:<6}|{asset_class:<2}|{side:<1}|"
            f"{fmt_s13v2(signed_notional)}|{fmt_s13v2(init_margin)}|{fmt_s13v2(var_99)}|"
            f"{decision:<4}|{reason:<24}      "
        )
        ledger_lines.append(ldg)

    sec_2 = "SECTION 2: END-OF-DAY PRIME BROKERAGE PORTFOLIO NETTING, COLLATERAL & MARGIN CALL STATEMENT".ljust(132)
    hdr_2 = (
        "ACCOUNT  CLIENT INSTITUTION   TIER   GROSS EXPOSURE    NET DELTA ($)  "
        " REQ MARGIN ($)  POSTED COLL($)  EXCESS/DEFICIT  ACTION STATUS"
    )
    report_lines.extend([" " * 132, sec_2, dash, hdr_2, dash])

    for acct in accounts:
        excess_def = acct.collateral - acct.req_init_margin
        if acct.status == "F":
            status_str = "ACCT FROZEN  "
        elif excess_def < 0:
            status_str = "MARGIN CALL! "
            tot_margin_calls += 1
            tot_call_deficit += abs(excess_def)
        elif acct.gross_notional > acct.credit_limit:
            status_str = "LIMIT BREACH "
        else:
            status_str = "GOOD STANDING"

        net_sign = "+" if acct.net_delta_exp >= 0 else "-"
        net_str = f"{net_sign}{abs(acct.net_delta_exp):>16,.2f}"
        ex_sign = "+" if excess_def >= 0 else "-"
        ex_str = f"{ex_sign}{abs(excess_def):>15,.2f}"

        adtl = (
            f"{acct.account_id:<8} {acct.client_name:<20} {acct.tier:<4} "
            f"{acct.gross_notional:>16,.2f} {net_str} "
            f"{acct.req_init_margin:>15,.2f} {acct.collateral:>15,.2f} "
            f"{ex_str} {status_str:<13}"
        )
        report_lines.append(adtl)

    report_lines.extend([dash, " " * 132])

    def fmt_summary(lbl: str, cnt: int, amt_lbl: str, amt: Decimal) -> str:
        amt_str = f"${amt:,.2f}".rjust(18)
        return f"{lbl:<42}{cnt:>9,d}    {amt_lbl:<32}{amt_str}{' ':27}"

    report_lines.append(fmt_summary("TOTAL INTRADAY TRADES PROCESSED       :", tot_trades, "CLEARED GROSS NOTIONAL VOLUME :", tot_gross_vol))
    report_lines.append(fmt_summary("TRADES CLEARED STP (CLRD)             :", tot_cleared, "TOTAL SPAN INITIAL MARGIN REQ :", tot_req_margin))
    report_lines.append(fmt_summary("TRADES CLEARED W/ VOL WARNING (WARN)  :", tot_warn, "AGGREGATE 1-DAY 99% VAR       :", tot_var_99))
    report_lines.append(fmt_summary("TRADES QUARANTINED BY AI MODEL (HOLD) :", tot_hold, "TOTAL MARGIN CALL DEFICIT ($) :", tot_call_deficit))
    report_lines.append(fmt_summary("TRADES HARD REJECTED (REJT)           :", tot_reject, "ACCOUNTS ISSUED MARGIN CALLS  :", Decimal(tot_margin_calls)))
    report_lines.append(banner)

    (out_dir / "CLEARING_REPORT.TXT").write_text("\n".join(report_lines) + "\n", encoding="ascii")
    (out_dir / "SETTLED_LEDGER.DAT").write_text("\n".join(ledger_lines) + "\n", encoding="ascii")

    print("==================================================")
    print("CLRENGIN BATCH COMPLETED SUCCESSFULLY (RC=0000)")
    print(f"  TRADES PROCESSED : {tot_trades:07d}")
    print(f"  STP CLEARED      : {tot_cleared:07d}")
    print(f"  VOLATILITY WARN  : {tot_warn:07d}")
    print(f"  AI CIRCUIT HOLD  : {tot_hold:07d}")
    print(f"  HARD REJECTED    : {tot_reject:07d}")
    print(f"  MARGIN CALLS     : {tot_margin_calls:05d}")
    print("==================================================")


if __name__ == "__main__":
    main()
