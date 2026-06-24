# Phase 5 Known Limitations

Status: limitations are explicit and intentional.

Not yet complete:

- RRCSetupComplete ASN.1 encode/decode.
- Dedicated CellGroupConfig and RadioBearerConfig installation.
- Full connected-mode UE context activation from decoded RRCSetupComplete.
- DCI 0_1 and 1_1.
- Connected PDSCH/PUSCH grants reconstructed only from decoded C-RNTI DCI.
- Connected SR over PUCCH and decoded BSR/PHR scheduler ownership.
- Full DL and UL packet delivery lineage.
- UE2 slot-24 reproduction and root-cause classification.
- Full Phase 5 no-oracle audit.

Out of scope for Phase 5 unless a later phase proves them:

- security activation, ciphering, integrity protection and NAS registration
- full DRB establishment and 5GC user plane
- CSI-RS, CSI reporting, CQI/PMI/RI and PUCCH Format 2 CSI
- SRS, TRS and full PTRS validation
- rank-2, multi-layer transmission and MU-MIMO
- final mobility-duration study
- publication-grade final KPI claims

Any test traffic before standards-established DRB must be classified
`LLS_TEST_DATA_BEARER`, not DRB. Phase 5 baseline remains rank 1.
