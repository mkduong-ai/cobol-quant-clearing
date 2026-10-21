      ******************************************************************
      * COPYBOOK: ACCTREC.CPY
      * PURPOSE:  PRIME BROKERAGE CLIENT MASTER ACCOUNT RECORD (64 BYTES)
      ******************************************************************
           05  AC-ACCOUNT-ID           PIC X(08).
           05  AC-CLIENT-NAME          PIC X(20).
           05  AC-TIER                 PIC X(04).
               88  TIER-INSTITUTIONAL              VALUE 'INST'.
               88  TIER-HEDGE-FUND                 VALUE 'HFND'.
               88  TIER-PROP-DESK                  VALUE 'PROP'.
           05  AC-COLLATERAL-POSTED    PIC 9(11)V9(02).
           05  AC-CREDIT-LIMIT         PIC 9(11)V9(02).
           05  AC-BASE-REG-T-BPS       PIC 9(04).
           05  AC-STATUS               PIC X(01).
               88  ACCT-ACTIVE                     VALUE 'A'.
               88  ACCT-FROZEN                     VALUE 'F'.
           05  AC-FILLER               PIC X(01).
