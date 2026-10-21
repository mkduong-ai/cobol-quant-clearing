//CLRENGIN JOB (ACCT991,'QUANT-RISK'),'PB SPAN/AI BATCH',
//             CLASS=A,MSGCLASS=X,MSGLEVEL=(1,1),NOTIFY=&SYSUID
//*===================================================================*
//* JOB NAME : CLRENGIN                                               *
//* PURPOSE  : NIGHTLY PRIME BROKERAGE CLEARING, SPAN INITIAL MARGIN, *
//*            PARAMETRIC 99% VAR & HYBRID AI CIRCUIT BREAKER BATCH   *
//* PLATFORM : IBM z/OS (ENTERPRISE COBOL FOR z/OS 6.4)               *
//*===================================================================*
//*
//*-------------------------------------------------------------------*
//* STEP 010 : SORT MASTER ACCOUNTS BY ASCENDING ACCOUNT-ID           *
//*            REQUIRED FOR COBOL 'SEARCH ALL' BINARY TABLE LOOKUP    *
//*-------------------------------------------------------------------*
//STEP010  EXEC PGM=SORT
//SYSOUT   DD SYSOUT=*
//SORTIN   DD DSN=PROD.PB.ACCOUNTS.UNSORTED,DISP=SHR
//SORTOUT  DD DSN=PROD.PB.ACCOUNTS.MASTER,
//            DISP=(NEW,CATLG,DELETE),
//            UNIT=SYSDA,SPACE=(CYL,(5,2),RLSE),
//            DCB=(RECFM=FB,LRECL=64,BLKSIZE=0)
//SYSIN    DD *
  SORT FIELDS=(1,8,CH,A)
/*
//*-------------------------------------------------------------------*
//* STEP 020 : EXECUTE CLEARING & HYBRID AI RISK ENGINE (CLRENGIN)    *
//*            DYNAMICALLY / STATICALLY CALLS SUBPROGRAM 'RISKAUDT'   *
//*-------------------------------------------------------------------*
//STEP020  EXEC PGM=CLRENGIN,COND=(0,NE,STEP010)
//STEPLIB  DD DSN=PROD.PB.LOADLIB,DISP=SHR
//         DD DSN=CEE.SCEERUN,DISP=SHR
//ACCTMAST DD DSN=PROD.PB.ACCOUNTS.MASTER,DISP=SHR
//TRDIN    DD DSN=PROD.PB.INTRADAY.TRADES(0),DISP=SHR
//CLRRPT   DD SYSOUT=A,DCB=(RECFM=FBA,LRECL=132,BLKSIZE=0)
//STLLEDGR DD DSN=PROD.PB.SETTLED.LEDGER(+1),
//            DISP=(NEW,CATLG,DELETE),
//            UNIT=SYSDA,SPACE=(CYL,(20,10),RLSE),
//            DCB=(RECFM=FB,LRECL=120,BLKSIZE=0)
//SYSOUT   DD SYSOUT=*
//SYSUDUMP DD SYSOUT=*
//
