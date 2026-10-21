      ******************************************************************
      * PROGRAM-ID:  RISKAUDT
      * AUTHOR:      DR. MANH KHOI DUONG
      *              (WITH CODE ASSIST GEMINI 4 ARGON)
      * PURPOSE:     CALLED SUBPROGRAM FOR QUANTITATIVE RISK, SPAN
      *              INITIAL MARGIN, PARAMETRIC 99% VALUE-AT-RISK (VAR),
      *              AND HYBRID AI/ML ANOMALY CIRCUIT BREAKER SCORING.
      *
      *              DEMONSTRATES:
      *              - LINKAGE SECTION & PROCEDURE DIVISION USING
      *              - COMP-3 (PACKED DECIMAL) EXACT FINANCIAL MATH
      *              - EVALUATE TRUE / ALSO DECISION MATRIX
      *              - 88-LEVEL CONDITION NAMES
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. RISKAUDT.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z16.
       OBJECT-COMPUTER. IBM-Z16.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01  WS-QUANT-CONSTANTS.
      *    99% ONE-TAIL NORMAL DISTRIBUTION Z-SCORE = 2.3263
           05  WS-Z-SCORE-99           PIC S9(02)V9(04) COMP-3
                                       VALUE +02.3263.
      *    1 / SQRT(252 TRADING DAYS) = 0.062994
           05  WS-DAILY-SCALE-FACTOR   PIC S9(01)V9(06) COMP-3
                                       VALUE +0.062994.
           05  WS-BPS-DIVISOR          PIC S9(05)       COMP-3
                                       VALUE +10000.

       01  WS-CALC-WORK-AREA.
           05  WS-ASSET-MULTIPLIER     PIC S9(02)V9(04) COMP-3
                                       VALUE +01.0000.
           05  WS-VOL-SURCHARGE        PIC S9(02)V9(04) COMP-3
                                       VALUE +00.0000.
           05  WS-EFFECTIVE-RATE       PIC S9(02)V9(06) COMP-3
                                       VALUE +00.000000.

       LINKAGE SECTION.
       COPY "RISKPARM.cpy".

       PROCEDURE DIVISION USING LK-RISK-AUDIT-AREA.

       0000-MAIN-AUDIT.
           PERFORM 1000-INIT-OUTPUTS
           PERFORM 2000-DETERMINE-ASSET-MULTIPLIER
           PERFORM 3000-COMPUTE-INITIAL-MARGIN
           PERFORM 4000-COMPUTE-PARAMETRIC-VAR
           PERFORM 5000-EVALUATE-HYBRID-AI-RULES
           GOBACK
           .

       1000-INIT-OUTPUTS.
           INITIALIZE LK-OUT-INITIAL-MARGIN
                      LK-OUT-VAR-99
                      LK-OUT-AUDIT-DECISION
                      LK-OUT-REASON-CODE
           .

       2000-DETERMINE-ASSET-MULTIPLIER.
      *    SPAN-STYLE ASSET CLASS RISK WEIGHTING
           EVALUATE LK-IN-ASSET-CLASS
               WHEN 'EQ'
                   MOVE +01.0000 TO WS-ASSET-MULTIPLIER
               WHEN 'OP'
                   MOVE +01.8500 TO WS-ASSET-MULTIPLIER
               WHEN 'FU'
                   MOVE +01.4000 TO WS-ASSET-MULTIPLIER
               WHEN 'FX'
                   MOVE +00.5000 TO WS-ASSET-MULTIPLIER
               WHEN OTHER
                   MOVE +02.0000 TO WS-ASSET-MULTIPLIER
           END-EVALUATE
           .

       3000-COMPUTE-INITIAL-MARGIN.
      *    VOLATILITY SURCHARGE: 20% OF REALIZED VOLATILITY BPS
           COMPUTE WS-VOL-SURCHARGE ROUNDED =
               (LK-IN-VOLATILITY-BPS / WS-BPS-DIVISOR) * 0.2000

           COMPUTE WS-EFFECTIVE-RATE ROUNDED =
               ((LK-IN-BASE-REG-T-BPS / WS-BPS-DIVISOR)
               * WS-ASSET-MULTIPLIER) + WS-VOL-SURCHARGE

           COMPUTE LK-OUT-INITIAL-MARGIN ROUNDED =
               LK-IN-NOTIONAL * WS-EFFECTIVE-RATE
               ON SIZE ERROR
                   SET DECISION-REJECT TO TRUE
                   MOVE 'MATH OVERFLOW ON MARGIN '
                       TO LK-OUT-REASON-CODE
           END-COMPUTE
           .

       4000-COMPUTE-PARAMETRIC-VAR.
      *    1-DAY 99% PARAMETRIC VAR =
      *    NOTIONAL * (ANNUAL_VOL_BPS / 10000) * (1/SQRT(252)) * 2.3263
           COMPUTE LK-OUT-VAR-99 ROUNDED =
               LK-IN-NOTIONAL
               * (LK-IN-VOLATILITY-BPS / WS-BPS-DIVISOR)
               * WS-DAILY-SCALE-FACTOR
               * WS-Z-SCORE-99
               ON SIZE ERROR
                   SET DECISION-REJECT TO TRUE
                   MOVE 'MATH OVERFLOW ON VAR-99 '
                       TO LK-OUT-REASON-CODE
           END-COMPUTE
           .

       5000-EVALUATE-HYBRID-AI-RULES.
      *    HYBRID DETERMINISTIC + AI/ML CIRCUIT BREAKER EVALUATION
           IF DECISION-REJECT
               EXIT PARAGRAPH
           END-IF

           EVALUATE TRUE
               WHEN LK-IN-NOTIONAL > 50000000.00
                   SET DECISION-REJECT TO TRUE
                   MOVE 'SINGLE TICKET > $50M CAP'
                       TO LK-OUT-REASON-CODE

               WHEN LK-IN-AI-ANOMALY-BPS >= 8500
                   SET DECISION-AI-HOLD TO TRUE
                   MOVE 'AI CIRCUIT BREAKER >=85%'
                       TO LK-OUT-REASON-CODE

               WHEN LK-IN-AI-ANOMALY-BPS >= 6500
                AND LK-IN-NOTIONAL >= 5000000.00
                   SET DECISION-AI-HOLD TO TRUE
                   MOVE 'AI ELEVATED + HIGH NOTNL'
                       TO LK-OUT-REASON-CODE

               WHEN LK-IN-VOLATILITY-BPS >= 5500
                   SET DECISION-MARGIN-WARN TO TRUE
                   MOVE 'EXTREME VOL REGIME >=55%'
                       TO LK-OUT-REASON-CODE

               WHEN OTHER
                   SET DECISION-CLEAR TO TRUE
                   MOVE 'STANDARD STP CLEARED    '
                       TO LK-OUT-REASON-CODE
           END-EVALUATE
           .
