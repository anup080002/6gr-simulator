# Phase 5 Test Plan

Status: documentation guard added; runtime test suites pending.

Current guard:

```matlab
setup6GRSimToolkit('Verbose', false);
testPhase5DocumentationSet;
```

Required future suites:

- RRCSetupComplete ASN.1 and SRB1.
- Dedicated configuration decode and ownership.
- UE-specific SearchSpace and C-RNTI PDCCH.
- DCI field layouts for every configured format.
- PDSCH and PUSCH exact TBS and receiver evidence.
- PUCCH Format 0 and Format 1 ACK/NACK/DTX/SR.
- DL and UL HARQ, rate recovery and soft combining.
- SR, BSR and PHR source-ownership guards.
- Dynamic scheduler candidate lineage and OLLA.
- Packet lineage and duplicate/drop accounting.
- UE2 slot-24 deterministic regression.
- No-oracle negative tests.

The repository-wide required command remains:

```matlab
setup6GRSimToolkit('Verbose', false);
testAll;
```
