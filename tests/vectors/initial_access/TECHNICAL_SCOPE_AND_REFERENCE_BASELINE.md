# Technical Scope and Reference Baseline

## Implemented target

`fr1_four_step_ra_rrc_connection_strict_r18`

The target chain is:

```text
SSB/PBCH/MIB
-> Type-0 CSS and SI-RNTI DCI 1_0
-> SIB1 PDSCH/DL-SCH and Release-18 ASN.1 UPER
-> PRACH Msg1
-> RAR Msg2
-> Msg3 RRCSetupRequest
-> Msg4 contention resolution and RRCSetup
-> SRB1
-> RRCSetupComplete
-> RRC_CONNECTED
```

## Pinned specification versions

- 3GPP TS 38.211 V18.8.0
- 3GPP TS 38.212 V18.8.0
- 3GPP TS 38.213 V18.8.0
- 3GPP TS 38.214 V18.8.0
- 3GPP TS 38.321 V18.8.0
- 3GPP TS 38.331 V18.9.0

Codex must store exact versions in executable profile metadata and generated run manifests.

## Deliberately unsupported in the bounded profile

- two-step random access;
- contention-free random access;
- beam-failure recovery access;
- supplementary uplink access;
- NTN access;
- RedCap/eRedCap-specific access.

These are not optional branches of the four-step implementation. They must reject at planning time until separate complete profiles exist.

## Independent-reference requirement

The supplied pack contains independent arithmetic and resource-index floors, plus the complete Type-0 table vector set from the PDCCH phase.

Before completion Codex must add:

1. externally generated Release-18 SIB1 UPER vectors;
2. an independently versioned complete PRACH configuration-index/table vector set;
3. independent or frozen PRACH sequence/cyclic-shift vectors for every declared format/restricted-set tuple.

A second call to the same MATLAB 5G Toolbox function is self-consistency, not an independent reference.
