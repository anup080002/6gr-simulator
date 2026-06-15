# SIB1 Waveform Recovery Status

AUD-015 is not closed yet. This pass removes the old SIB1 shortcut path and adds a constrained SIB1 ASN.1 anchor profile, but strict waveform recovery still fails closed because MATLAB R2024a public PDCCH/DCI APIs reject SI-RNTI `65535`.

Implemented in this pass:

- `+sixgr/+rrc/+asn1/*` builds, validates, encodes, decodes, hashes, and compares the supported BCCH-DL-SCH/SystemInformationBlockType1 anchor profile.
- `+sixgr/+phy/+rrc/MIB_SIB1_Recovery.m` no longer returns `SIB1.Ok=true` from config payload structs, JSON, defaults, or `SystemInformation` shortcuts.
- `+sixgr/+truth/evaluateLLSRuntimeTruthContract.m` has an explicit SIB1 evidence gate for strict runs.
- `+sixgr/+phy/+broadcast/*` defines the intended SSB/PBCH/SI-RNTI/PDSCH/DL-SCH artifact path and fails closed while SI-RNTI waveform support is unavailable.

Known blocker:

- MATLAB R2024a public `nrPDCCHConfig` and `nrPDCCH` reject RNTI values above `65519`; SI-RNTI is `0xFFFF = 65535`. A direct probe of `nrDCIEncode/nrDCIDecode` with `65535` caused a native access violation in this environment, so strict code must not call those APIs with SI-RNTI.

Next required implementation:

- Add a repo-owned SI-RNTI-capable PDCCH/DCI wrapper for DCI format 1_0: CRC24C masking by SI-RNTI, polar encode/rate-match, PDCCH scrambling/modulation, soft demod/descrambling, polar decode, CRC recovery, and negative wrong-RNTI/no-signal/corruption evidence.
- Once that path exists, enable the positive `runSIB1StrictMiniAnchor` artifacts and only then move AUD-015 from `open` to `fixed`.

Validated commands:

```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); testAll('Names', string({'testMIBSIB1Recovery','testSIB1ASN1RoundTrip','testSIB1WaveformRecoveryAWGN','testSIB1PDCCHNegativeCandidates','testSIB1PDSCHAndASN1Negative','testSIB1NoOracleReceiver','testSIB1ArtifactSchemas','testSIB1TruthContractStrictGate'}));"
```
