      ******************************************************************
      * PROGRAM-ID:  CLRENGIN
      * AUTHOR:      DR. MANH KHOI DUONG
      *              (WITH CODE ASSIST GEMINI 4 ARGON)
      * PURPOSE:     TIER-1 PRIME BROKERAGE CLEARING, SPAN MARGIN,
      *              NETTING & HYBRID AI ANOMALY SETTLEMENT ENGINE.
      *
      *              ARCHITECTURAL HIGHLIGHTS:
      *              1. LOADS MASTER ACCOUNTS INTO AN INDEXED IN-MEMORY
      *                 TABLE FOR BINARY SEARCH (SEARCH ALL).
      *              2. PROCESSES SEQUENTIAL INTRADAY TRADE FEED.
      *              3. CALLS SUBPROGRAM 'RISKAUDT' FOR PACKED-DECIMAL
      *                 SPAN INITIAL MARGIN, 99% PARAMETRIC VAR &
      *                 HYBRID ML ANOMALY CIRCUIT BREAKER RULES.
      *              4. AGGREGATES NET GROSS/NET EXPOSURE & MARGIN
      *                 CALL DEFICITS PER ACCOUNT USING CONTROL BREAKS.
      *              5. PRODUCES EXECUTIVE EOD CLEARING REPORT AND
      *                 SETTLEMENT LEDGER FEED.
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CLRENGIN.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z16.
       OBJECT-COMPUTER. IBM-Z16.

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACCOUNT-MASTER-FILE
               ASSIGN TO "data/ACCOUNTS.DAT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-ACCT-STATUS.

           SELECT TRADE-INPUT-FILE
               ASSIGN TO "data/TRADES.DAT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-TRADE-STATUS.

           SELECT CLEARING-REPORT-FILE
               ASSIGN TO "output/CLEARING_REPORT.TXT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-REP-STATUS.

           SELECT SETTLEMENT-LEDGER-FILE
               ASSIGN TO "output/SETTLED_LEDGER.DAT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-LEDGER-STATUS.

       DATA DIVISION.
       FILE SECTION.

       FD  ACCOUNT-MASTER-FILE.
       01  FD-ACCOUNT-RECORD.
           COPY "ACCTREC.cpy".

       FD  TRADE-INPUT-FILE.
       01  FD-TRADE-RECORD.
           COPY "TRADEREC.cpy".

       FD  CLEARING-REPORT-FILE.
       01  FD-REPORT-LINE              PIC X(132).

       FD  SETTLEMENT-LEDGER-FILE.
       01  FD-SETTLEMENT-RECORD        PIC X(120).

       WORKING-STORAGE SECTION.

       01  WS-FILE-STATUS-FLAGS.
           05  WS-ACCT-STATUS          PIC X(02) VALUE SPACES.
           05  WS-TRADE-STATUS         PIC X(02) VALUE SPACES.
           05  WS-REP-STATUS           PIC X(02) VALUE SPACES.
           05  WS-LEDGER-STATUS        PIC X(02) VALUE SPACES.
           05  WS-EOF-ACCT-SW          PIC X(01) VALUE 'N'.
               88  EOF-ACCOUNTS                  VALUE 'Y'.
           05  WS-EOF-TRADE-SW         PIC X(01) VALUE 'N'.
               88  EOF-TRADES                    VALUE 'Y'.

      *----------------------------------------------------------------*
      * IN-MEMORY MASTER ACCOUNT TABLE WITH ASCENDING KEY FOR          *
      * FAST BINARY LOOKUP (SEARCH ALL) + PORTFOLIO RISK ACCUMULATORS  *
      *----------------------------------------------------------------*
       01  WS-ACCOUNT-TABLE-AREA.
           05  WS-ACCT-COUNT           PIC 9(03) VALUE 0.
           05  WS-ACCT-ENTRY OCCURS 1 TO 50 TIMES
               DEPENDING ON WS-ACCT-COUNT
               ASCENDING KEY IS TB-ACCOUNT-ID
               INDEXED BY ACCT-IDX.
               10  TB-ACCOUNT-ID       PIC X(08).
               10  TB-CLIENT-NAME      PIC X(20).
               10  TB-TIER             PIC X(04).
               10  TB-COLLATERAL       PIC S9(13)V9(02) COMP-3.
               10  TB-CREDIT-LIMIT     PIC S9(13)V9(02) COMP-3.
               10  TB-BASE-REG-T-BPS   PIC 9(04)        COMP-3.
               10  TB-STATUS           PIC X(01).
               10  TB-GROSS-NOTIONAL   PIC S9(13)V9(02) COMP-3.
               10  TB-NET-DELTA-EXP    PIC S9(13)V9(02) COMP-3.
               10  TB-REQ-INIT-MARGIN  PIC S9(13)V9(02) COMP-3.
               10  TB-PORTFOLIO-VAR99  PIC S9(13)V9(02) COMP-3.
               10  TB-CLEARED-COUNT    PIC 9(05)        COMP-3.
               10  TB-HELD-REJ-COUNT   PIC 9(05)        COMP-3.

      *----------------------------------------------------------------*
      * CURRENT TRADE & BATCH CONTROL TOTALS (COMP-3 PACKED DECIMAL)   *
      *----------------------------------------------------------------*
       01  WS-TRADE-WORK-AREA.
           05  WS-TRADE-NOTIONAL       PIC S9(13)V9(02) COMP-3 VALUE 0.
           05  WS-SIGNED-NOTIONAL      PIC S9(13)V9(02) COMP-3 VALUE 0.
           05  WS-EXCESS-DEFICIT       PIC S9(13)V9(02) COMP-3 VALUE 0.
           05  WS-MARGIN-UTIL-PCT      PIC S9(04)V9(02) COMP-3 VALUE 0.
           05  WS-ACCT-FOUND-SW        PIC X(01)        VALUE 'N'.
               88  ACCT-FOUND                           VALUE 'Y'.
               88  ACCT-NOT-FOUND                       VALUE 'N'.

       01  WS-BATCH-STATISTICS.
           05  WS-TOT-TRADES-READ      PIC 9(07)        COMP-3 VALUE 0.
           05  WS-TOT-CLEARED          PIC 9(07)        COMP-3 VALUE 0.
           05  WS-TOT-MARGIN-WARN      PIC 9(07)        COMP-3 VALUE 0.
           05  WS-TOT-AI-HOLD          PIC 9(07)        COMP-3 VALUE 0.
           05  WS-TOT-REJECTED         PIC 9(07)        COMP-3 VALUE 0.
           05  WS-TOT-GROSS-VOLUME     PIC S9(15)V9(02) COMP-3 VALUE 0.
           05  WS-TOT-REQ-MARGIN       PIC S9(15)V9(02) COMP-3 VALUE 0.
           05  WS-TOT-VAR-99           PIC S9(15)V9(02) COMP-3 VALUE 0.
           05  WS-TOT-MARGIN-CALLS     PIC 9(05)        COMP-3 VALUE 0.
           05  WS-TOT-CALL-DEFICIT     PIC S9(15)V9(02) COMP-3 VALUE 0.

      *----------------------------------------------------------------*
      * SUBPROGRAM LINKAGE PARAMETER BLOCK                             *
      *----------------------------------------------------------------*
       COPY "RISKPARM.cpy".

      *----------------------------------------------------------------*
      * REPORT FORMATTING LINES (132 COLUMNS MAINFRAME PRINTER SPEC)   *
      *----------------------------------------------------------------*
       01  WS-RPT-BANNER-LINE.
           05  FILLER                  PIC X(132) VALUE ALL '='.

       01  WS-RPT-DASH-LINE.
           05  FILLER                  PIC X(132) VALUE ALL '-'.

       01  WS-RPT-TITLE-1.
           05  FILLER                  PIC X(18)
               VALUE 'IBM Z16 // CICS-BA'.
           05  FILLER                  PIC X(76)
               VALUE 'TCH    TIER-1 PRIME BROKERAGE CLEARING, SPAN MARGI
      -              'N & AI RISK ENGINE        '.
           05  FILLER                  PIC X(18)
               VALUE 'JOB: CLRENGIN     '.
           05  FILLER                  PIC X(20)
               VALUE 'RUN DATE: 2026-10-21'.

       01  WS-RPT-SECTION-TRADES.
           05  FILLER                  PIC X(132)
               VALUE 'SECTION 1: INTRADAY TRADE EXECUTION, SPAN MARGIN &
      -              ' HYBRID AI/ML ANOMALY AUDIT LOG'.

       01  WS-RPT-TRADE-HDR.
           05  FILLER                  PIC X(11) VALUE 'TRADE-ID   '.
           05  FILLER                  PIC X(09) VALUE 'ACCOUNT  '.
           05  FILLER                  PIC X(07) VALUE 'TICKER '.
           05  FILLER                  PIC X(03) VALUE 'CL '.
           05  FILLER                  PIC X(02) VALUE 'S '.
           05  FILLER                  PIC X(12) VALUE '   QUANTITY '.
           05  FILLER                  PIC X(13) VALUE '       PRICE '.
           05  FILLER                  PIC X(17)
               VALUE '    NOTIONAL ($) '.
           05  FILLER                  PIC X(15)
               VALUE 'INIT MARGIN($) '.
           05  FILLER                  PIC X(14)
               VALUE ' 1D-VAR-99($) '.
           05  FILLER                  PIC X(06) VALUE 'AI-SC '.
           05  FILLER                  PIC X(05) VALUE 'STAT '.
           05  FILLER                  PIC X(18)
               VALUE 'AUDIT REASON      '.

       01  WS-RPT-TRADE-DTL.
           05  DTL-TRADE-ID            PIC X(10).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-ACCOUNT-ID          PIC X(08).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-TICKER              PIC X(06).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-ASSET-CLASS         PIC X(02).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-SIDE                PIC X(01).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-QUANTITY            PIC ZZZ,ZZZ,ZZ9.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-PRICE               PIC Z,ZZZ,ZZ9.9999.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-NOTIONAL            PIC ZZ,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-INIT-MARGIN         PIC ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-VAR-99              PIC ZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-AI-SCORE            PIC 99.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-DECISION            PIC X(04).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  DTL-REASON              PIC X(18).

       01  WS-RPT-SECTION-ACCOUNTS.
           05  FILLER                  PIC X(132)
               VALUE 'SECTION 2: END-OF-DAY PRIME BROKERAGE PORTFOLIO NE
      -              'TTING, COLLATERAL & MARGIN CALL STATEMENT'.

       01  WS-RPT-ACCT-HDR.
           05  FILLER                  PIC X(09) VALUE 'ACCOUNT  '.
           05  FILLER                  PIC X(21)
               VALUE 'CLIENT INSTITUTION   '.
           05  FILLER                  PIC X(05) VALUE 'TIER '.
           05  FILLER                  PIC X(17)
               VALUE '  GROSS EXPOSURE '.
           05  FILLER                  PIC X(18)
               VALUE '   NET DELTA ($)  '.
           05  FILLER                  PIC X(16)
               VALUE ' REQ MARGIN ($) '.
           05  FILLER                  PIC X(16)
               VALUE ' POSTED COLL($) '.
           05  FILLER                  PIC X(17)
               VALUE ' EXCESS/DEFICIT  '.
           05  FILLER                  PIC X(13) VALUE 'ACTION STATUS'.

       01  WS-RPT-ACCT-DTL.
           05  ADTL-ACCOUNT-ID         PIC X(08).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-CLIENT-NAME        PIC X(20).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-TIER               PIC X(04).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-GROSS-EXP          PIC ZZ,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-NET-DELTA          PIC +ZZ,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-REQ-MARGIN         PIC Z,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-COLLATERAL         PIC Z,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-EXCESS-DEF         PIC +Z,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  ADTL-ACTION-STATUS      PIC X(13).

       01  WS-RPT-SUMMARY-LINE.
           05  SUM-LABEL               PIC X(42).
           05  SUM-COUNT               PIC Z,ZZZ,ZZ9.
           05  FILLER                  PIC X(04) VALUE SPACES.
           05  SUM-AMOUNT-LABEL        PIC X(32).
           05  SUM-AMOUNT              PIC $$$,$$$,$$$,$$9.99.
           05  FILLER                  PIC X(27) VALUE SPACES.

       01  WS-LEDGER-OUT-REC.
           05  LDG-TRADE-ID            PIC X(10).
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-ACCOUNT-ID          PIC X(08).
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-TICKER              PIC X(06).
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-ASSET-CLASS         PIC X(02).
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-SIDE                PIC X(01).
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-NOTIONAL            PIC +0000000000009.99.
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-INIT-MARGIN         PIC +0000000000009.99.
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-VAR-99              PIC +0000000000009.99.
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-DECISION            PIC X(04).
           05  FILLER                  PIC X(01) VALUE '|'.
           05  LDG-REASON              PIC X(24).
           05  FILLER                  PIC X(06) VALUE SPACES.

       PROCEDURE DIVISION.

       0000-MAIN-DRIVER.
           PERFORM 1000-INITIALIZE-BATCH
           PERFORM 2000-LOAD-ACCOUNT-MASTER
           PERFORM 3000-WRITE-REPORT-HEADERS
           PERFORM 4000-PROCESS-TRADE-STREAM
               UNTIL EOF-TRADES
           PERFORM 5000-GENERATE-PORTFOLIO-NETTING
           PERFORM 6000-WRITE-BATCH-CONTROL-TOTALS
           PERFORM 9000-TERMINATE-BATCH
           STOP RUN
           .

       1000-INITIALIZE-BATCH.
           OPEN INPUT  ACCOUNT-MASTER-FILE
                INPUT  TRADE-INPUT-FILE
                OUTPUT CLEARING-REPORT-FILE
                OUTPUT SETTLEMENT-LEDGER-FILE

           IF WS-ACCT-STATUS NOT = '00'
               DISPLAY 'FATAL: CANNOT OPEN ACCOUNTS.DAT STATUS='
                       WS-ACCT-STATUS
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF

           IF WS-TRADE-STATUS NOT = '00'
               DISPLAY 'FATAL: CANNOT OPEN TRADES.DAT STATUS='
                       WS-TRADE-STATUS
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           .

       2000-LOAD-ACCOUNT-MASTER.
           PERFORM UNTIL EOF-ACCOUNTS
               READ ACCOUNT-MASTER-FILE
                   AT END
                       SET EOF-ACCOUNTS TO TRUE
                   NOT AT END
                       ADD 1 TO WS-ACCT-COUNT
                       SET ACCT-IDX TO WS-ACCT-COUNT
                       MOVE AC-ACCOUNT-ID
                         TO TB-ACCOUNT-ID(ACCT-IDX)
                       MOVE AC-CLIENT-NAME
                         TO TB-CLIENT-NAME(ACCT-IDX)
                       MOVE AC-TIER
                         TO TB-TIER(ACCT-IDX)
                       MOVE AC-COLLATERAL-POSTED
                         TO TB-COLLATERAL(ACCT-IDX)
                       MOVE AC-CREDIT-LIMIT
                         TO TB-CREDIT-LIMIT(ACCT-IDX)
                       MOVE AC-BASE-REG-T-BPS
                         TO TB-BASE-REG-T-BPS(ACCT-IDX)
                       MOVE AC-STATUS
                         TO TB-STATUS(ACCT-IDX)
                       INITIALIZE TB-GROSS-NOTIONAL(ACCT-IDX)
                                  TB-NET-DELTA-EXP(ACCT-IDX)
                                  TB-REQ-INIT-MARGIN(ACCT-IDX)
                                  TB-PORTFOLIO-VAR99(ACCT-IDX)
                                  TB-CLEARED-COUNT(ACCT-IDX)
                                  TB-HELD-REJ-COUNT(ACCT-IDX)
               END-READ
           END-PERFORM
           .

       3000-WRITE-REPORT-HEADERS.
           WRITE FD-REPORT-LINE FROM WS-RPT-BANNER-LINE
           WRITE FD-REPORT-LINE FROM WS-RPT-TITLE-1
           WRITE FD-REPORT-LINE FROM WS-RPT-BANNER-LINE
           WRITE FD-REPORT-LINE FROM SPACES
           WRITE FD-REPORT-LINE FROM WS-RPT-SECTION-TRADES
           WRITE FD-REPORT-LINE FROM WS-RPT-DASH-LINE
           WRITE FD-REPORT-LINE FROM WS-RPT-TRADE-HDR
           WRITE FD-REPORT-LINE FROM WS-RPT-DASH-LINE
           .

       4000-PROCESS-TRADE-STREAM.
           READ TRADE-INPUT-FILE
               AT END
                   SET EOF-TRADES TO TRUE
               NOT AT END
                   ADD 1 TO WS-TOT-TRADES-READ
                   PERFORM 4100-VALIDATE-AND-CLEAR-TRADE
           END-READ
           .

       4100-VALIDATE-AND-CLEAR-TRADE.
      *    COMPUTE EXACT TRADE NOTIONAL = QUANTITY * PRICE
           COMPUTE WS-TRADE-NOTIONAL ROUNDED =
               TR-QUANTITY * TR-PRICE

           IF SIDE-SELL
               COMPUTE WS-SIGNED-NOTIONAL = WS-TRADE-NOTIONAL * -1
           ELSE
               MOVE WS-TRADE-NOTIONAL TO WS-SIGNED-NOTIONAL
           END-IF

      *    BINARY SEARCH (SEARCH ALL) ON ASCENDING ACCOUNT TABLE
           SET ACCT-NOT-FOUND TO TRUE
           SEARCH ALL WS-ACCT-ENTRY
               AT END
                   SET ACCT-NOT-FOUND TO TRUE
               WHEN TB-ACCOUNT-ID(ACCT-IDX) = TR-ACCOUNT-ID
                   SET ACCT-FOUND TO TRUE
           END-SEARCH

           IF ACCT-NOT-FOUND
               INITIALIZE LK-RISK-AUDIT-AREA
               SET DECISION-REJECT TO TRUE
               MOVE 'UNKNOWN MASTER ACCOUNT  ' TO LK-OUT-REASON-CODE
           ELSE
               IF TB-STATUS(ACCT-IDX) = 'F'
                   INITIALIZE LK-RISK-AUDIT-AREA
                   SET DECISION-REJECT TO TRUE
                   MOVE 'ACCOUNT STATUS FROZEN   '
                       TO LK-OUT-REASON-CODE
               ELSE
                   PERFORM 4200-INVOKE-RISK-SUBPROGRAM
               END-IF
           END-IF

           PERFORM 4300-UPDATE-PORTFOLIO-BUCKETS
           PERFORM 4400-WRITE-AUDIT-AND-LEDGER
           .

       4200-INVOKE-RISK-SUBPROGRAM.
           INITIALIZE LK-RISK-AUDIT-AREA
           MOVE TR-ACCOUNT-ID        TO LK-IN-ACCOUNT-ID
           MOVE TR-TRADE-ID          TO LK-IN-TRADE-ID
           MOVE TR-ASSET-CLASS       TO LK-IN-ASSET-CLASS
           MOVE WS-TRADE-NOTIONAL    TO LK-IN-NOTIONAL
           MOVE TR-VOLATILITY-BPS    TO LK-IN-VOLATILITY-BPS
           MOVE TR-AI-ANOMALY-BPS    TO LK-IN-AI-ANOMALY-BPS
           MOVE TB-BASE-REG-T-BPS(ACCT-IDX)
                                     TO LK-IN-BASE-REG-T-BPS

           CALL 'RISKAUDT' USING LK-RISK-AUDIT-AREA
           .

       4300-UPDATE-PORTFOLIO-BUCKETS.
           EVALUATE TRUE
               WHEN DECISION-CLEAR
                   ADD 1 TO WS-TOT-CLEARED
                   PERFORM 4350-ACCUMULATE-CLEARED-EXPOSURE
               WHEN DECISION-MARGIN-WARN
                   ADD 1 TO WS-TOT-MARGIN-WARN
                   PERFORM 4350-ACCUMULATE-CLEARED-EXPOSURE
               WHEN DECISION-AI-HOLD
                   ADD 1 TO WS-TOT-AI-HOLD
                   IF ACCT-FOUND
                       ADD 1 TO TB-HELD-REJ-COUNT(ACCT-IDX)
                   END-IF
               WHEN DECISION-REJECT
                   ADD 1 TO WS-TOT-REJECTED
                   IF ACCT-FOUND
                       ADD 1 TO TB-HELD-REJ-COUNT(ACCT-IDX)
                   END-IF
           END-EVALUATE
           .

       4350-ACCUMULATE-CLEARED-EXPOSURE.
           ADD WS-TRADE-NOTIONAL     TO WS-TOT-GROSS-VOLUME
           ADD LK-OUT-INITIAL-MARGIN TO WS-TOT-REQ-MARGIN
           ADD LK-OUT-VAR-99         TO WS-TOT-VAR-99

           IF ACCT-FOUND
               ADD 1                     TO TB-CLEARED-COUNT(ACCT-IDX)
               ADD WS-TRADE-NOTIONAL     TO TB-GROSS-NOTIONAL(ACCT-IDX)
               ADD WS-SIGNED-NOTIONAL    TO TB-NET-DELTA-EXP(ACCT-IDX)
               ADD LK-OUT-INITIAL-MARGIN TO TB-REQ-INIT-MARGIN(ACCT-IDX)
               ADD LK-OUT-VAR-99         TO TB-PORTFOLIO-VAR99(ACCT-IDX)
           END-IF
           .

       4400-WRITE-AUDIT-AND-LEDGER.
           MOVE TR-TRADE-ID          TO DTL-TRADE-ID
           MOVE TR-ACCOUNT-ID        TO DTL-ACCOUNT-ID
           MOVE TR-TICKER            TO DTL-TICKER
           MOVE TR-ASSET-CLASS       TO DTL-ASSET-CLASS
           MOVE TR-SIDE              TO DTL-SIDE
           MOVE TR-QUANTITY          TO DTL-QUANTITY
           MOVE TR-PRICE             TO DTL-PRICE
           MOVE WS-TRADE-NOTIONAL    TO DTL-NOTIONAL
           MOVE LK-OUT-INITIAL-MARGIN TO DTL-INIT-MARGIN
           MOVE LK-OUT-VAR-99        TO DTL-VAR-99
           COMPUTE DTL-AI-SCORE = TR-AI-ANOMALY-BPS / 100.00
           MOVE LK-OUT-AUDIT-DECISION TO DTL-DECISION
           MOVE LK-OUT-REASON-CODE(1:18) TO DTL-REASON
           WRITE FD-REPORT-LINE FROM WS-RPT-TRADE-DTL

      *    WRITE PIPE-DELIMITED DOWNSTREAM SETTLEMENT LEDGER RECORD
           MOVE TR-TRADE-ID          TO LDG-TRADE-ID
           MOVE TR-ACCOUNT-ID        TO LDG-ACCOUNT-ID
           MOVE TR-TICKER            TO LDG-TICKER
           MOVE TR-ASSET-CLASS       TO LDG-ASSET-CLASS
           MOVE TR-SIDE              TO LDG-SIDE
           MOVE WS-SIGNED-NOTIONAL   TO LDG-NOTIONAL
           MOVE LK-OUT-INITIAL-MARGIN TO LDG-INIT-MARGIN
           MOVE LK-OUT-VAR-99        TO LDG-VAR-99
           MOVE LK-OUT-AUDIT-DECISION TO LDG-DECISION
           MOVE LK-OUT-REASON-CODE   TO LDG-REASON
           WRITE FD-SETTLEMENT-RECORD FROM WS-LEDGER-OUT-REC
           .

       5000-GENERATE-PORTFOLIO-NETTING.
           WRITE FD-REPORT-LINE FROM SPACES
           WRITE FD-REPORT-LINE FROM WS-RPT-SECTION-ACCOUNTS
           WRITE FD-REPORT-LINE FROM WS-RPT-DASH-LINE
           WRITE FD-REPORT-LINE FROM WS-RPT-ACCT-HDR
           WRITE FD-REPORT-LINE FROM WS-RPT-DASH-LINE

           PERFORM VARYING ACCT-IDX FROM 1 BY 1
               UNTIL ACCT-IDX > WS-ACCT-COUNT

               COMPUTE WS-EXCESS-DEFICIT =
                   TB-COLLATERAL(ACCT-IDX)
                   - TB-REQ-INIT-MARGIN(ACCT-IDX)

               MOVE TB-ACCOUNT-ID(ACCT-IDX)      TO ADTL-ACCOUNT-ID
               MOVE TB-CLIENT-NAME(ACCT-IDX)     TO ADTL-CLIENT-NAME
               MOVE TB-TIER(ACCT-IDX)            TO ADTL-TIER
               MOVE TB-GROSS-NOTIONAL(ACCT-IDX)  TO ADTL-GROSS-EXP
               MOVE TB-NET-DELTA-EXP(ACCT-IDX)   TO ADTL-NET-DELTA
               MOVE TB-REQ-INIT-MARGIN(ACCT-IDX) TO ADTL-REQ-MARGIN
               MOVE TB-COLLATERAL(ACCT-IDX)      TO ADTL-COLLATERAL
               MOVE WS-EXCESS-DEFICIT            TO ADTL-EXCESS-DEF

               EVALUATE TRUE
                   WHEN TB-STATUS(ACCT-IDX) = 'F'
                       MOVE 'ACCT FROZEN  ' TO ADTL-ACTION-STATUS
                   WHEN WS-EXCESS-DEFICIT < 0
                       MOVE 'MARGIN CALL! ' TO ADTL-ACTION-STATUS
                       ADD 1 TO WS-TOT-MARGIN-CALLS
                       COMPUTE WS-TOT-CALL-DEFICIT =
                           WS-TOT-CALL-DEFICIT
                           + (WS-EXCESS-DEFICIT * -1)
                   WHEN TB-GROSS-NOTIONAL(ACCT-IDX) >
                        TB-CREDIT-LIMIT(ACCT-IDX)
                       MOVE 'LIMIT BREACH ' TO ADTL-ACTION-STATUS
                   WHEN OTHER
                       MOVE 'GOOD STANDING' TO ADTL-ACTION-STATUS
               END-EVALUATE

               WRITE FD-REPORT-LINE FROM WS-RPT-ACCT-DTL
           END-PERFORM
           .

       6000-WRITE-BATCH-CONTROL-TOTALS.
           WRITE FD-REPORT-LINE FROM WS-RPT-DASH-LINE
           WRITE FD-REPORT-LINE FROM SPACES

           INITIALIZE WS-RPT-SUMMARY-LINE
           MOVE 'TOTAL INTRADAY TRADES PROCESSED       :' TO SUM-LABEL
           MOVE WS-TOT-TRADES-READ                        TO SUM-COUNT
           MOVE 'CLEARED GROSS NOTIONAL VOLUME :'
               TO SUM-AMOUNT-LABEL
           MOVE WS-TOT-GROSS-VOLUME                       TO SUM-AMOUNT
           WRITE FD-REPORT-LINE FROM WS-RPT-SUMMARY-LINE

           INITIALIZE WS-RPT-SUMMARY-LINE
           MOVE 'TRADES CLEARED STP (CLRD)             :' TO SUM-LABEL
           MOVE WS-TOT-CLEARED                            TO SUM-COUNT
           MOVE 'TOTAL SPAN INITIAL MARGIN REQ :'
               TO SUM-AMOUNT-LABEL
           MOVE WS-TOT-REQ-MARGIN                         TO SUM-AMOUNT
           WRITE FD-REPORT-LINE FROM WS-RPT-SUMMARY-LINE

           INITIALIZE WS-RPT-SUMMARY-LINE
           MOVE 'TRADES CLEARED W/ VOL WARNING (WARN)  :' TO SUM-LABEL
           MOVE WS-TOT-MARGIN-WARN                        TO SUM-COUNT
           MOVE 'AGGREGATE 1-DAY 99% VAR       :'
               TO SUM-AMOUNT-LABEL
           MOVE WS-TOT-VAR-99                             TO SUM-AMOUNT
           WRITE FD-REPORT-LINE FROM WS-RPT-SUMMARY-LINE

           INITIALIZE WS-RPT-SUMMARY-LINE
           MOVE 'TRADES QUARANTINED BY AI MODEL (HOLD) :' TO SUM-LABEL
           MOVE WS-TOT-AI-HOLD                            TO SUM-COUNT
           MOVE 'TOTAL MARGIN CALL DEFICIT ($) :'
               TO SUM-AMOUNT-LABEL
           MOVE WS-TOT-CALL-DEFICIT                       TO SUM-AMOUNT
           WRITE FD-REPORT-LINE FROM WS-RPT-SUMMARY-LINE

           INITIALIZE WS-RPT-SUMMARY-LINE
           MOVE 'TRADES HARD REJECTED (REJT)           :' TO SUM-LABEL
           MOVE WS-TOT-REJECTED                           TO SUM-COUNT
           MOVE 'ACCOUNTS ISSUED MARGIN CALLS  :'
               TO SUM-AMOUNT-LABEL
           MOVE WS-TOT-MARGIN-CALLS                       TO SUM-AMOUNT
           WRITE FD-REPORT-LINE FROM WS-RPT-SUMMARY-LINE

           WRITE FD-REPORT-LINE FROM WS-RPT-BANNER-LINE
           .

       9000-TERMINATE-BATCH.
           CLOSE ACCOUNT-MASTER-FILE
                 TRADE-INPUT-FILE
                 CLEARING-REPORT-FILE
                 SETTLEMENT-LEDGER-FILE

           DISPLAY '=================================================='
           DISPLAY 'CLRENGIN BATCH COMPLETED SUCCESSFULLY (RC=0000)'
           DISPLAY '  TRADES PROCESSED : ' WS-TOT-TRADES-READ
           DISPLAY '  STP CLEARED      : ' WS-TOT-CLEARED
           DISPLAY '  VOLATILITY WARN  : ' WS-TOT-MARGIN-WARN
           DISPLAY '  AI CIRCUIT HOLD  : ' WS-TOT-AI-HOLD
           DISPLAY '  HARD REJECTED    : ' WS-TOT-REJECTED
           DISPLAY '  MARGIN CALLS     : ' WS-TOT-MARGIN-CALLS
           DISPLAY '=================================================='
           .
