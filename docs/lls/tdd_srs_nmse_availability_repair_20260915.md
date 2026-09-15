# Shared SRS NMSE availability repair — focused tests passed

Scope: the 5 MHz TDD / configured 12 dB baseline. No active run checkout is
modified. This candidate is prepared in the idle archive-validation checkout.

## Observed defect and root cause

The retained `tdd_5mhz_12db_cc1dae18_20260915` shared SRS row reports
NMSE and true-channel NMSE of -27.5487441552577 dB, 576 compared complex
values and 288 pilot resources, but `NMSEScoringAvailable=0`.

`runSRSChannelEstimation` obtains its independent scoring record from
`sixgr.phy.srs.pilotChannelNMSE` after the practical receiver completes.
That record has `Available=true`. `runWaveformLinkBundle.localCompleteSharedSRS`
copied counts and reference-plane metadata but omitted availability, leaving
the generic row-template default false. This is a reporting defect, not a
reason to adjust the channel estimator, noise or received power.

## Candidate repair

- Add `+sixgr/+truth/bindSharedSRSNMSEEvidence.m` and call it at shared-SRS
  completion. Bind availability and counts only from the actual independent
  scoring record. Require score, source and reference-plane consistency;
  reject fitting, missing-value masking, receiver oracle input and incomplete
  pilot/receive-branch counts. Preserve NaN/unavailable when no score exists.
- Extend `testSRSPilotChannelNMSE` with exact algebra fixtures, including
  zero error (-Inf dB), finite error and inconsistent/missing-record rejection.
  These fixtures are not physical qualification evidence.
- Extend `testSharedPUCCHReceiveOnlyClock` to bind and export the score of its
  actual shared-SRS reception as `received_srs_nmse_evidence.csv`. Its existing
  component limitations and all original assertions remain unchanged.

## Validation status

All three focused tests passed on R2026a Update 4 in 98.24 seconds:
`testSRSPilotChannelNMSE` (1.34 s), `testSharedPUCCHReceiveOnlyClock`
(96.40 s), and `testReceivedSRSTimingEvidence` (0.47 s). The physical
component retained actual SRS scoring and two DTX feedback observations.
Logs: `logs/testall_20260915T144703762Z_42411415` and its ZIP in the
archive-validation checkout. This diagnostic used frozen modified source
based on f6ca7ef5; launcher exit was zero. `git diff --check` passes.

After integration, run required `testAll`, export/artifact, scheduler,
strict-mode and E2E guards on the final source, plus integrated SRS CSV review.
Focused passes alone do not qualify the 12 dB run or the PUCCH detector.

The 2c45b257 integrated run ended at slot 35 with the independent shared
HARQ transport selector's blanket CSI-enabled guard. Its earlier slot-32
QCL boundary passed and three connected DL blocks passed CRC. Its failure
and incomplete artifact recovery remain preserved; this metadata repair
does not resolve that separate integration blocker. Queue 10 was stopped
before any MATLAB guards or full suite launched; required tests remain due.

SRS true-delay/reference-plane reporting, complete measurement closure,
the original detector qualification failure, and full-suite failures remain
separate open work; this patch must not be reported as closing them.
