# 5 MHz TDD / configured 12 dB receiver checkpoint — 15 September 2026

Priority: only the existing 58-slot continuous-IQ TDD diagnostic now.
400 MHz work is deferred. No geometry-based replacement scenario was committed.
This checkpoint is integration evidence, not qualified main or a 12 dB pass.

## Completed work and retained evidence

The receiver now exports one PUSCH HARQ decision audit per actual receive
occasion, with assignment/context/window identity, completion clock, raw bits,
raw decoder usability, final erasure, actual CRC where applicable, and the
configured conditional codeword confidence. Empty UCI creates no HARQ row.
Duplicate windows and mismatched observation bindings fail loudly.
Audit values are not signal-presence qualification or fabricated TB results.

Files: appendPUSCHHARQDecisionAudit.m, CoupledTruthRuntime.m and
completeSharedPUSCHAfterRejectedControl.m under +sixgr/+truth.
The normal control CSV is pusch_harq_receiver_decisions.csv.

MATLAB R2026a Update 4, frozen dirty source based on 90125db5:

| Test | Result |
| --- | --- |
| testPUSCHShortUCIConfidence | PASS, 23.82 s |
| testServerPUSCHCompatibility | PASS, 0.46 s on R2026a only |
| testSharedRejectedULDueHARQ | PASS, 96.41 s; physical silent PUSCH becomes receiver erasure |
| testTDDSharedPUSCHNonemptyCompletion | PASS, 142.44 s; actual DL/UL transmission and common ACK receipt |
| testTDDSharedPUSCHIndependentCompletion | PASS, 59.97 s; actual UL, empty UCI, no invented DL HARQ |
| testPUSCHHARQDecisionAudit, first attempt | FAIL; CSV type inference and decimal precision, preserved |

Original run: logs/testall_20260915T020317913Z_afce4787, exit 1.
Raw silent-PUSCH evidence: logs/tpf1289c75_5e4d_4a2f_83ce_6f3da1583306.
Signal-present evidence: logs/tdd_shared_pusch_nonempty_completion/tp356fda07_cae7_400e_9748_b111e8c2eb29.

Repair: csvWriteTable has an opt-in RoundTripNumericText mode using 17-digit
real floating-point serialization; default exports and typed DB mirror remain
unchanged. csvReadTable preserves BitsJSON as text, including one-bit fields.
The new test restores declared logical/blank-string CSV types, retaining exact
numeric equality, and tests adjacent doubles below/at/above the 0.99 boundary.
No receiver threshold or original scientific assertion changed.

Second frozen-source run: logs/testall_20260915T021316549Z_4e813853, exit 0:
testPUSCHHARQDecisionAudit, testCSVAtomicPublication,
testCSVEmptySchemaPreservation, testCanonicalWideCSVReadback and
testUCIBitVectorCSVPreservation all PASS.
Logs and ZIPs remain local and ignored, not uploaded as if source.

## Immediate next run and acceptance

Run simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml
on a clean, frozen integration revision, saving to logs/scenario_runs.
Its configured 12 dB is the existing occupied-RE reference Es/N0 input;
measured post-equalization SINR is an output and must not be forced to 12 dB.
This single diagnostic does not establish statistical BLER or detector qualification.

Required next evidence: actual integrated runtime/CSV/PNG measurements,
normal audit export and completion, final-source testAll and NR/config,
strict-proxy, scheduler, export and E2E guards. Original PUCCH 12/1024
false-ACK failure, missed-ACK qualification and broader combined HARQ/CSI/SR
coverage remain open. Do not promote main as qualified.

The two older suites and old queue helper were found absent at 07:30 IST.
Their process-missing receipts and logs are preserved as incomplete, not
passed. Windows recorded low virtual memory; exact termination is unknown.
Do not restart multiple full suites concurrently.

## Windows server commands

Use a separate Git clone, not a source ZIP. Do not pull/edit while MATLAB runs.

```powershell
git lfs install
git clone --branch integration/tdd-12db-20260914 https://github.com/anup080002/6gr-simulator.git 6gr-tdd-validation
cd 6gr-tdd-validation
git lfs pull
git lfs fsck
git status --short
git rev-parse HEAD
$matlabExe = 'C:\Program Files\MATLAB\R2023b\bin\matlab.exe'
& .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe -PreflightOnly
& .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe -Tests @('testServerPUSCHCompatibility')
```

R2023b is NOT qualified for this code: current PUSCH multiplexing uses
nrPUSCHConfig.NumCodewords (introduced in R2024a). The compatibility test
reports that missing API explicitly; do not bypass it or silently reduce
features. R2026a is the locally tested reference. After selecting a compatible
installation with required toolboxes and passing preflight/API checks:

```powershell
$matlabExe = 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe'
& .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe
```

The launcher creates logs/testall_<unique>/ and a sibling ZIP on completion.
Share the ZIP even for failures. Full-suite success is not a substitute for
the separately inspected 12 dB scenario. The scenario command, after suite
termination and with unchanged source, is:

```powershell
& .\scripts\run_monitored_lls_scenario.ps1 -MatlabExe $matlabExe -ScenarioPath 'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml' -OutputDir 'logs/scenario_runs' -RunTag ('tdd_5mhz_12db_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
```

Keep logs/monitored_lls_runs and the scenario output directory as well; the
test-suite ZIP does not automatically include the separate scenario/IQ files.

## Integrated attempt and preflight repair, 07:45–07:54 IST

Clean revision 5cec590b ran the exact scenario. It failed before slot zero:
EnabledAllocationUnresolved / ConnectedMonitoringIdentityMismatch.
buildPlannedREAllocation called PDCCH_Tx with a legacy/default RNTI while the
connected factory required the installed data-channel C-RNTI. Planning also
read the legacy monitoring calendar, not the connected offset/duration.

Repair: connected planning directly materializes the installed PDCCH object
and Toolbox REs using DCIContextFactory identity. No dummy DCI transmission
is necessary to calculate planned geometry. The actual receiver identity
guard is unchanged. Planned rows remain explicitly non-runtime evidence.
Monitoring uses the installed period, offset and consecutive-slot duration,
consistent with the [Toolbox TS 38.213 search-space contract](https://www.mathworks.com/help/5g/ref/nrsearchspaceconfig.html).

A separate output-root defect silently redirected the absolute logs output
request to results. resolveResultsRoot now admits the explicit repo-local
logs tree, with canonical path containment and traversal/sibling regressions.
Other external-root restrictions remain. This is an output location change,
not a PHY or scientific policy change.

Frozen dirty-source regression based on 5cec590b:
logs/testall_20260915T022150605Z_df23cfda, MATLAB exit 0:

| Test | Result |
| --- | --- |
| testConnectedPDCCHPlannedAllocation | PASS, 66.44 s; every enabled allocation on exact scenario, exact Toolbox RE equality, offset/duration and unchanged bad-RNTI rejection |
| testResolveResultsRoot | PASS, 0.38 s; logs retained, traversal/siblings not admitted |
| testDefaultRunFolderProfileRoot | PASS, 0.33 s |
| testCSIRSPlannedCalendar | PASS, 9.04 s |

The first integrated attempt is NOT successful. Its original failure report
and partial exports are retained, including a ZIP under logs:
tdd_5mhz_12db_5cec590b_20260915_failed_preflight.zip.
After the preflight failure was recorded, engine 22704 was deliberately
stopped during report recovery; launcher reported -1. No PHY slot executed.
The stop receipt records this explicitly. No files were deleted.
The next integrated attempt must use a new run tag and clean revision.
Full testAll/guards and statistical detector qualification are still pending.
