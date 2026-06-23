# Phase 4 Test Plan

This file lists the current committed Phase 4 regression surface and the
remaining acceptance gaps.

## Current Passing Anchor Tests

```matlab
setup6GRSimToolkit('Verbose', false);
testSIB1ToFourStepRAIntegration;
testRAConfigBinding;
testMsg1PRACHWaveformDetection;
testMsg2RARWaveformDecode;
testMsg3PUSCHFromRARGrant;
testMsg4ContentionResolution;
testRANegativeWrongRARNTI;
testRANegativeRARWindowExpiry;
testRANegativeRAPIDMismatch;
testRANegativeMsg3CrcFail;
testRANegativeMsg4IdentityMismatch;
testRACollisionSamePreamble;
testRAOracleGuard;
testRAArtifactSchemas;
```

## Dependency Clusters

```matlab
setup6GRSimToolkit('Verbose', false);
testMIBSIB1Recovery;
testSIB1ASN1RoundTrip;
testSIB1WaveformRecoveryAWGN;
testSIB1PDCCHNegativeCandidates;
testSIB1PDSCHAndASN1Negative;
testSIB1NoOracleReceiver;
testMIBPDCCHConfigSIB1Derivation;
testSIB1ArtifactSchemas;
testSIB1TruthContractStrictGate;
testPDCCHConfigStrictValidation;
testPDCCHWaveformGeneration;
testPDCCHBlindDecodePositiveDCI10;
testPDCCHBlindDecodePositiveDCI00;
testPDCCHWrongRNTIReject;
testPDCCHNoSignalFalseAlarm;
testPDCCHCorruptedPDCCHReject;
testPDCCHCandidateBlindSearch;
testPDCCHWrongDCIFormatReject;
testPDCCHInvalidGrantReject;
testPDCCHFalseAlarmSweep;
testPDCCHLowSNRSweep;
testPDCCHOracleGuard;
testPDCCHArtifactSchemas;
testPDCCHGrantReferencePropagation;
```

## Pending Acceptance Coverage

- Versioned machine-readable PRACH table coverage.
- Complete statistical false-alarm calibration.
- Msg3 HARQ retransmission and soft-combining.
- Two-UE CDL/RF minimum-duration complete RA run.
- Reporting replay without rerunning waveform simulation.
- Full Phase4Ok truth gate.
