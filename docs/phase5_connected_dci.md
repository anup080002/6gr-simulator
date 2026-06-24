# Phase 5 Connected DCI

Status: DCI 1_0 and 0_0 strict mini-anchor only.

`+sixgr/+phy/+pdcch/decodeDCIPayload.m` parses the current strict-anchor DCI
payload layouts for 1_0 and 0_0, including frequency assignment, time-domain
assignment, MCS, NDI, RV and HARQ process fields. It intentionally errors on
unsupported formats.

Required Phase 5 behavior:

- Resolve the DCI formats required by the decoded connected-mode configuration.
- Encode and transmit DCI on C-RNTI PDCCH.
- Blind-decode candidates at the UE.
- Derive PDSCH and PUSCH configs from decoded fields only.
- Preserve candidate and rejection lineage for every monitored opportunity.

Pending formats must remain pending in traceability rather than silently
falling back to remembered field layouts.
