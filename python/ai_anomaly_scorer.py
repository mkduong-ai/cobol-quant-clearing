#!/usr/bin/env python3
"""
AI/ML Pre-Trade Anomaly Scorer & Fixed-Width Mainframe Feed Generator
=====================================================================
Simulates a hybrid enterprise architecture (such as IBM z16 Integrated
Accelerator for AI or an upstream Python/ONNX feature pipeline) that:

1. Generates Prime Brokerage Master Accounts (`data/ACCOUNTS.DAT`, 64-byte fixed width)
   sorted in ascending order by `AC-ACCOUNT-ID` for COBOL `SEARCH ALL` binary search.
2. Evaluates a multi-factor Isolation-Forest / Logistic-Regression style anomaly
   model over intraday institutional trade executions:
   - Order-to-ADV shock ratio
   - Cross-asset implied volatility regime
   - Off-hours / microsecond burst timestamp clustering
   - Fat-finger notional z-score
3. Serializes the scored trades into strict COBOL fixed-width records
   (`data/TRADES.DAT`, 85-byte layout matching `copybooks/TRADEREC.cpy`).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path


@dataclass
class AccountMaster:
    account_id: str          # PIC X(08)
    client_name: str         # PIC X(20)
    tier: str                # PIC X(04): INST, HFND, PROP
    collateral_posted: float # PIC 9(11)V9(02) -> 13 digits implied decimal
    credit_limit: float      # PIC 9(11)V9(02) -> 13 digits implied decimal
    base_reg_t_bps: int      # PIC 9(04)
    status: str              # PIC X(01): A=Active, F=Frozen

    def to_cobol_record(self) -> str:
        coll_cents = int(round(self.collateral_posted * 100))
        limit_cents = int(round(self.credit_limit * 100))
        rec = (
            f"{self.account_id:<8.8}"
            f"{self.client_name:<20.20}"
            f"{self.tier:<4.4}"
            f"{coll_cents:013d}"
            f"{limit_cents:013d}"
            f"{self.base_reg_t_bps:04d}"
            f"{self.status:<1.1}"
            f" "
        )
        assert len(rec) == 64, f"Expected 64 bytes, got {len(rec)}"
        return rec


@dataclass
class RawTradeTicket:
    account_id: str          # PIC X(08)
    trade_id: str            # PIC X(10)
    timestamp: str           # PIC X(14) YYYYMMDDHHMMSS
    ticker: str              # PIC X(06)
    asset_class: str         # PIC X(02) EQ, OP, FU, FX
    side: str                # PIC X(01) B, S
    quantity: int            # PIC 9(09)
    price: float             # PIC 9(07)V9(04) -> 11 digits implied decimal
    currency: str            # PIC X(03)
    volatility_bps: int      # PIC 9(04)
    counterparty: str        # PIC X(06)
    # ML Feature inputs (used to compute TR-AI-ANOMALY-BPS)
    adv_participation: float # Ratio of order size to average daily volume
    burst_intensity: float   # Order book message rate z-score
    off_market_spread: float # Price deviation from NBBO mid in sigmas


def score_trade_anomaly_bps(ticket: RawTradeTicket) -> int:
    """
    Computes an interpretable ML log-odds anomaly probability (in basis points
    0000..9999) from microstructure features before feeding the mainframe batch.
    """
    notional = ticket.quantity * ticket.price
    notional_log_feature = max(0.0, math.log10(max(notional, 1.0)) - 5.5)

    # Linear log-odds combination (pre-trained weights for institutional flow)
    logit = (
        -3.65
        + 2.80 * ticket.adv_participation
        + 0.75 * ticket.burst_intensity
        + 0.95 * ticket.off_market_spread
        + 0.55 * notional_log_feature
        + 0.00025 * ticket.volatility_bps
    )
    prob = 1.0 / (1.0 + math.exp(-logit))
    return min(9999, max(10, int(round(prob * 10000))))


def format_trade_cobol_record(ticket: RawTradeTicket, ai_bps: int) -> str:
    price_scaled = int(round(ticket.price * 10000))
    rec = (
        f"{ticket.account_id:<8.8}"
        f"{ticket.trade_id:<10.10}"
        f"{ticket.timestamp:<14.14}"
        f"{ticket.ticker:<6.6}"
        f"{ticket.asset_class:<2.2}"
        f"{ticket.side:<1.1}"
        f"{ticket.quantity:09d}"
        f"{price_scaled:011d}"
        f"{ticket.currency:<3.3}"
        f"{ticket.volatility_bps:04d}"
        f"{ai_bps:04d}"
        f"{ticket.counterparty:<6.6}"
        f"{' ':7}"
    )
    assert len(rec) == 85, f"Expected 85 bytes, got {len(rec)}"
    return rec


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    data_dir = root / "data"
    data_dir.mkdir(exist_ok=True)

    # 1. Master Accounts (Strictly sorted by account_id for COBOL SEARCH ALL)
    accounts = [
        AccountMaster("PB000100", "CITADEL QUANT ALPHA ", "HFND", 6_500_000.00, 45_000_000.00, 1500, "A"),
        AccountMaster("PB000200", "TWO SIGMA STAT ARB  ", "HFND", 9_200_000.00, 60_000_000.00, 1250, "A"),
        AccountMaster("PB000300", "JANE STREET DERIV   ", "PROP", 1_400_000.00, 30_000_000.00, 1800, "A"),
        AccountMaster("PB000400", "BLACKROCK GLOBAL EQ ", "INST", 9_800_000.00, 95_000_000.00, 1000, "A"),
        AccountMaster("PB000500", "MILLENNIUM MACRO FX ", "HFND", 3_100_000.00, 50_000_000.00, 1400, "A"),
        AccountMaster("PB000600", "ARCHEGOS LEGACY SWAP", "HFND",   250_000.00,  5_000_000.00, 2500, "F"),
    ]

    accounts_path = data_dir / "ACCOUNTS.DAT"
    with accounts_path.open("w", encoding="ascii", newline="\n") as f:
        for acct in sorted(accounts, key=lambda a: a.account_id):
            f.write(acct.to_cobol_record() + "\n")

    # 2. Intraday Multi-Asset Trade Tickets
    tickets = [
        # Standard institutional flow (Cleared STP)
        RawTradeTicket("PB000100", "TRD2610001", "20261021093001", "NVDA  ", "EQ", "B",  45_000,  138.5000, "USD", 3200, "GSCO  ", 0.08, 0.4, 0.1),
        RawTradeTicket("PB000100", "TRD2610002", "20261021093512", "SPX   ", "OP", "S",   2_500, 5820.2500, "USD", 1850, "MSCO  ", 0.12, 0.5, 0.2),
        RawTradeTicket("PB000200", "TRD2610003", "20261021094219", "AAPL  ", "EQ", "B",  80_000,  232.1500, "USD", 2100, "JPMS  ", 0.06, 0.3, 0.1),
        RawTradeTicket("PB000200", "TRD2610004", "20261021100455", "NDX   ", "FU", "S",   1_200, 20450.000, "USD", 2450, "CME   ", 0.10, 0.6, 0.2),
        # High volatility regime warning (Volatility >= 5500 bps -> WARN) and triggers Margin Call on PB000300
        RawTradeTicket("PB000300", "TRD2610005", "20261021101509", "TSLA  ", "OP", "B",  22_000,  260.7500, "USD", 5850, "CBOE  ", 0.18, 0.9, 0.3),
        RawTradeTicket("PB000300", "TRD2610006", "20261021102144", "MSTR  ", "EQ", "B",  18_500,  215.4000, "USD", 6200, "BAML  ", 0.15, 0.8, 0.4),
        # Standard BlackRock & Millennium flow
        RawTradeTicket("PB000400", "TRD2610007", "20261021110230", "MSFT  ", "EQ", "B",  65_000,  428.8000, "USD", 1900, "GSCO  ", 0.05, 0.2, 0.1),
        RawTradeTicket("PB000500", "TRD2610008", "20261021113000", "EURUSD", "FX", "S", 9500000,    1.0845, "USD",  950, "UBS   ", 0.04, 0.2, 0.0),
        # AI Circuit Breaker Hold #1: Spoofing / Microstructure Burst Anomaly (>= 85% AI Score -> HOLD)
        RawTradeTicket("PB000100", "TRD2610009", "20261021131459", "SMCI  ", "OP", "B",  95_000,   48.9000, "USD", 6400, "ARCA  ", 0.85, 3.8, 2.4),
        # AI Circuit Breaker Hold #2: Elevated AI Score (65%-84%) + Large Notional (>=$5M) -> HOLD
        RawTradeTicket("PB000500", "TRD2610010", "20261021140211", "USDJPY", "FX", "B",  85_000,  151.2500, "USD", 3100, "BARC  ", 0.55, 1.3, 0.7),
        # Hard Reject #1: Single Ticket Fat-Finger > $50M Cap -> REJT
        RawTradeTicket("PB000400", "TRD2610011", "20261021145500", "AMZN  ", "EQ", "B", 320_000,  195.0000, "USD", 2200, "JPMS  ", 0.25, 1.1, 0.5),
        # Hard Reject #2: Frozen Master Account (Archegos Legacy) -> REJT
        RawTradeTicket("PB000600", "TRD2610012", "20261021151022", "PARA  ", "EQ", "B", 150_000,   11.2500, "USD", 4100, "CSFB  ", 0.40, 1.5, 0.8),
        # Hard Reject #3: Unrecognized Master Account ID -> REJT
        RawTradeTicket("PB999999", "TRD2610013", "20261021154500", "GME   ", "OP", "B",  50_000,   24.5000, "USD", 7500, "ROBN  ", 0.70, 2.5, 1.9),
    ]

    trades_path = data_dir / "TRADES.DAT"
    with trades_path.open("w", encoding="ascii", newline="\n") as f:
        for t in tickets:
            ai_bps = score_trade_anomaly_bps(t)
            f.write(format_trade_cobol_record(t, ai_bps) + "\n")

    print(f"[AI Scorer] Wrote {len(accounts)} master accounts -> {accounts_path}")
    print(f"[AI Scorer] Scored & wrote {len(tickets)} fixed-width trade records -> {trades_path}")


if __name__ == "__main__":
    main()
