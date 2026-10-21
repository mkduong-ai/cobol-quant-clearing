      ******************************************************************
      * COPYBOOK: TRADEREC.CPY
      * PURPOSE:  FIXED-WIDTH INTRADAY TRADE EXECUTION RECORD (85 BYTES)
      *           USED BY CLEARING ENGINE (CLRENGIN) AND AUDIT SUBPROG
      ******************************************************************
           05  TR-ACCOUNT-ID           PIC X(08).
           05  TR-TRADE-ID             PIC X(10).
           05  TR-TIMESTAMP            PIC X(14).
           05  TR-TICKER               PIC X(06).
           05  TR-ASSET-CLASS          PIC X(02).
               88  ASSET-EQUITY                    VALUE 'EQ'.
               88  ASSET-OPTION                    VALUE 'OP'.
               88  ASSET-FUTURE                    VALUE 'FU'.
               88  ASSET-FX                        VALUE 'FX'.
               88  VALID-ASSET-CLASS               VALUES 'EQ' 'OP'
                                                          'FU' 'FX'.
           05  TR-SIDE                 PIC X(01).
               88  SIDE-BUY                        VALUE 'B'.
               88  SIDE-SELL                       VALUE 'S'.
               88  VALID-SIDE                      VALUES 'B' 'S'.
           05  TR-QUANTITY             PIC 9(09).
           05  TR-PRICE                PIC 9(07)V9(04).
           05  TR-CURRENCY             PIC X(03).
           05  TR-VOLATILITY-BPS       PIC 9(04).
           05  TR-AI-ANOMALY-BPS       PIC 9(04).
           05  TR-COUNTERPARTY         PIC X(06).
           05  TR-FILLER               PIC X(07).
