      ******************************************************************
      * COPYBOOK: RISKPARM.CPY
      * PURPOSE:  INTER-PROGRAM COMMUNICATION AREA FOR SUBPROGRAM CALL
      *           BETWEEN CLRENGIN (MAIN) AND RISKAUDT (SUBPROGRAM)
      ******************************************************************
       01  LK-RISK-AUDIT-AREA.
           05  LK-IN-ACCOUNT-ID        PIC X(08).
           05  LK-IN-TRADE-ID          PIC X(10).
           05  LK-IN-ASSET-CLASS       PIC X(02).
           05  LK-IN-NOTIONAL          PIC S9(13)V9(02) COMP-3.
           05  LK-IN-VOLATILITY-BPS    PIC 9(04)        COMP-3.
           05  LK-IN-AI-ANOMALY-BPS    PIC 9(04)        COMP-3.
           05  LK-IN-BASE-REG-T-BPS    PIC 9(04)        COMP-3.
           05  LK-OUT-INITIAL-MARGIN   PIC S9(13)V9(02) COMP-3.
           05  LK-OUT-VAR-99           PIC S9(13)V9(02) COMP-3.
           05  LK-OUT-AUDIT-DECISION   PIC X(04).
               88  DECISION-CLEAR                  VALUE 'CLRD'.
               88  DECISION-MARGIN-WARN            VALUE 'WARN'.
               88  DECISION-AI-HOLD                VALUE 'HOLD'.
               88  DECISION-REJECT                 VALUE 'REJT'.
           05  LK-OUT-REASON-CODE      PIC X(24).
