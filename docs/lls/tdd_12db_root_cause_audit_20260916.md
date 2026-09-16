# TDD 5 MHz / 12 dB: root-cause audit before further implementation

Audit started: 16 September 2026, approximately 07:52 IST. This is an implementation plan and evidence ledger, not a passing-run certificate. Production changes were paused during diagnosis. After the evidence-backed repair map was delivered, bounded implementation of the first UCI wire/resource work package began in the isolated development checkout. Its latest status is recorded below; the broader work package and integrated qualification remain incomplete.

## Next receiver-publication defect: unreported UE measurements reached the gNB scheduler

Before changing production code, the extended TDD source-authority reproducer supplied identical decoded CSI bits and changed only stored UE-side SINR/source-CRC/vector metadata. `LatestDLFeedback.SINR_dB` changed from **11.25 to 80 dB**, while decoded/policy CQI remained 11 in both cases. This is an actual reducer dependency, not a claimed RF measurement at 80 dB. `logs/csi_wire_only_authority_reproducer_20260916.log` exited **1**, SHA-256 `A6B5ADBD8B9AC7953EAE5FD73B8E3C61BF2FE51475407E9872152A4E5008B614`.

Root cause: `processDueFeedback` passed the whole UE report record into `applyLinkAdaptationToCSIReport` and copied that record's raw SINR, spatial/vector information and source-data CRC into `LatestDLFeedback`. Those quantities are not carried by the configured CQI/RI/PMI/CRI UCI payload. A source-data CRC could also refresh data-feedback bookkeeping independently of received HARQ.

The in-progress repair introduces a field whitelist at that existing publication boundary. It preserves decoded CSI, transport identity and current timing bookkeeping; it reconstructs table-derived MCS from decoded CQI and the configured table. Raw UE measurements, source-data CRC and spatial/vector fields are excluded from scheduler inputs. The original report is retained explicitly in `UEReferenceRecordJSON`, with a CSV round-trip test. Both PUSCH and PUCCH CSI use the same projection; direct gNB UL/SRS knowledge does not. This is **not yet independent transport/occasion ownership**: existing producer report identity and source-time binding remain, and the projection documents that limit.

`logs/csi_wire_authority_v1_20260916.log` completed with **exit 0: nine selected receiver/AMC/export/scheduler tests and both TDD CSI-only/combined-HARQ/CSI shared-PUCCH cases passed**. SHA-256 `EF42D17AFDBA6D4655DBDC73EAF6F24257E542B776A830C36F9BE69306CAF34C`; all 46 prelaunch source hashes matched at completion. The reproducer now gives NaN scheduler SINR for both reference variants and identical scheduler feedback. Original UE SINR/source CRC survive the explicitly named audit field and a CSV round trip under `logs/csi_wire_authority/tpa8885cd8_a1de_465b_a42f_d9672fa521d3/received_csi_report.csv`.

A subsequent export refinement makes both production `csi_feedback_reports.csv` writers preserve the schema and round-trip numeric text. Otherwise the default CSV writer prunes wholly unavailable columns, hiding the explicit unavailable SINR/source-CRC contract. The component CSV test uses those same options. This refinement postdates v1 and still needs its follow-up check. Final-source full-suite/E2E qualification and integrated 12 dB acceptance remain due. A named cumulative development checkpoint is being prepared for preservation; it is not qualified main and does not reconcile every older pending patch.

## 12:34 IST checkpoint: CSI non-delivery consumer repair passes 14 selected guards

`logs/pusch_csi_consumer_v1_20260916.log` completed with **exit 0, 14 selected tests passing**, SHA-256 `39EB7E520C891D4D5A7E67E7E0DC182E2672561B4D97567406E91174329C3899`. All **46** captured changed/new source-file hashes matched at completion; `git diff --check` passed. Tests: TDD CSI source/consumer authority, CSI presence decision, actual present/absent waveform, partial reception, absence mapping, per-part receiver evidence, shared TDD late CSI delivery, `testConfig`, `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`, both strict proxy/fallback guards and scheduler grant consistency. The shared-clock fixture received an actual CSI-RS report, transported it on slot-10 PUSCH and delivered it in slot 11. It still uses the legacy CSI transport binding and does **not** close independently owned normal/rejected-DCI CSI publication.

The exact repaired defect is the consumer's premature success-only length assertion. Missing evidence still rejects; absent/unresolved CSI now reaches non-delivery without replacing scheduler feedback. Successful publication still requires the original received-Part-1 length authority. The reducer's negative inputs are explicitly declared component inputs, complemented by actual waveform and public-codec tests; they are not additional RF trials. Existing assertions and power/detector thresholds were not relaxed.

Changes remain uncommitted in `C:/Users/anup0/AppData/Local/Temp/sixgr_tdd_combined_receiver_20260916` over `5d20e64d`. The IDE checkout contains this audit, not those production edits. The old live full suite and queued older validation do not qualify this source. Final-source unfiltered `testAll`, remaining framework/export/E2E guards, detector and all-measurement closure, accepted 5 MHz / 12 dB execution and consolidation remain due. No process was cancelled and no log or user edit was deleted.

## 12:19 IST checkpoint: PUSCH CSI-presence selection passes bounded waveform tests

`receiveWithCSIPresence.m` now evaluates absent/present interpretations of the same received LLRs using the independently installed CSI configuration. A unique current-transmission TB CRC on the UCI-owning codeword selects the interpretation. Both/neither passing, or no TB, leaves CSI unresolved and retains only mapping-invariant fields. Previous HARQ buffers and transmitter payload/length metadata do not select presence. The policy is catalog-backed (`phy.pusch.csiPresenceDecisionAlgorithm=unique_current_tb_crc`) and wired through `receiveConfiguredUCI.m` into the actual independent `PUSCH_Rx` path. This is a receiver algorithm, not a 3GPP-mandated detector or statistical qualification.

`logs/pusch_csi_presence_v1_20260916.log` exited **0**, with nine selected tests passing: presence ambiguity/no-TB, actual present/absent CSI waveforms, absence map, partial reception, decoder evidence, annotation, configuration, parameter catalog and scenario validation. SHA-256 `1B24B216FF0815F88C435390C583BD3266EE87B163A4FCEE2BBA3893EA183565`. All 44 captured source hashes matched at completion. The actual absent-CSI waveform recovered HARQ and data without publishing CSI; the all-zero codec fixture passed both candidate CRCs and remained unresolved. Actual waveform evidence is retained under development-checkout `logs/tpe907391f_232a_46c9_9702_2e04a3d0456b`.

**Exact integration defect, reproduced before patching:** `CoupledTruthRuntime.consumeDecodedPUSCHCSI` asserted successful received-Part-1 sizing before calling `puschCSIReceiverUsable`. Consequently a receiver-declared absence/unresolved result could not reach the existing not-delivered reducer. The first reproducer instead stopped earlier because its fixture inherited the deferred FDD configuration without the new Format-2 allocation policy (`pusch_csi_consumer_reproducer_20260916.log`, exit 1, SHA-256 `CAD88263C63643A7A53C6B3BEA8BC5A8A498976ABA43BA457BCE03C91706E3F9`). That log is preserved, not treated as consumer proof. The fixture now inherits the existing TDD scenario and reserves the configured UL symbol interval. The TDD reproducer then reached and failed the exact consumer assertion at line 15051 (`pusch_csi_consumer_tdd_reproducer_20260916.log`, exit 1, SHA-256 `7EACA7F941093195B6DC11E16DD1D4A33723D7D218FFC58AB855F68223F84A1D`).

The consumer patch now retains mandatory evidence fields ahead of both paths, handles explicit receiver non-delivery, and requires the original received-Part-1 sizing authority before successful CSI publication. It does not fabricate absent bits or CRC success. `receiveInvariantUCI` supplies paired presence/detection flags. The extended reducer fixture checks unchanged last-valid scheduler feedback, no CSI delivery/execution claim, and rejection of missing authority even on negative decisions; its declared reducer inputs are not RF evidence. The existing actual-codec partial-reception test also exercises the consumer usability helper. At **12:23 IST**, `logs/pusch_csi_consumer_v1_20260916.log` is running 14 selected tests, including the TDD reducer, actual presence waveforms, TDD late CSI delivery, the four required NR/config checks and strict/scheduler guards. Source is frozen during the batch; this is not an unfiltered full-suite run.

**Still open:** producer-gated normal CSI runtime ownership, no-producer/missing-DCI cases, retransmission presence ambiguity, mixed zero/nonzero two-codeword handling, independent combined PUCCH/SR lifecycle, detector qualification, SRS/measurement/export closure and consolidation. No integrated 12 dB success, final-source full-suite pass or MATLAB R2023b compatibility claim follows from these nine tests. No merge, commit, push, log deletion or process cancellation occurred.

## 11:59 IST checkpoint: CSI-absence partial-reception mapping repaired

The preceding turn made progress: the CSI execution-flag repair passed its bounded regression. The current receiver review confirmed another exact implementation gap in the existing partial PUSCH path. `inspectUCIResourceInvariance.m` quantified only configured Part-2 lengths with Part 1 assumed present. `receiveInvariantUCI.m` consequently treated a fixed present-only Part-2 length as enough to recover that block and UL-SCH even though CSI could have been absent. The prior direct public-demultiplexer diagnostic already proved that presence changes data-resource indices; the new regression tests that case in the production helper.

Changes are confined to those two existing receiver helpers, two existing tests, one new matrix test and its `testAll` registration. The map domain now includes `(OCSI1, OCSI2)=(0,0)` alongside installed present-report lengths. Configured-grant UCI is retained independently of CSI absence. HARQ, data and CSI2/CG-UCI are retained only where source indices and required coded lengths agree. Unresolved report lengths are NaN, not invented zeros. UCI-only empty data maps remain absence of data, not successful transport blocks. Primary output must not claim that a conditional CSI-present word has an established resource map.

The first batch `logs/pusch_csi_absence_mapping_v1_20260916.log` exited **1**: six tests passed, including the existing actual PUSCH waveform regression, but the new 24-case map matrix failed. SHA-256 `2722794DA1E952D186BD59527DAF795846684A2AEA8E96F0A4FC0F7C8EB034AB`; all 34 captured source hashes matched. Cause: my new CSI2 index validation incorrectly rejected public-demultiplexer puncturing erasures. Installed `nrULSCHDemultiplex.m` lines 244-251 explicitly restore HARQ-punctured CSI2 positions as zeros. The correction allows exactly those zero erasures while continuing to reject noninteger, wrong-owner and out-of-range indices, and reconstructs erasure LLRs without indexing received sample zero. The new test also requires erasure-containing cases to have been exercised.

The v2 batch completed with **exit 0, all seven tests passing**. `logs/pusch_csi_absence_mapping_v2_20260916.log` SHA-256: `C2F0A6F2B08DC4ADDA7F3E76068BEDCA3834B9B9BE9CA07DBC4E4A5BD5CD893B`. All 34 prelaunch changed/new source hashes matched at completion; `git diff --check` passed. The matrix covers 24 allocation cases including four CSI2-puncturing-erasure cases, plus an absent-CSI codec case that preserves actual HARQ and rejects unresolved data/CSI. Existing resource-invariance, 12 invalid-CSI codec cases, independent codeword decoding, UCI evidence/annotation, and the actual PUSCH waveform regression pass. These are component and waveform regressions, not the integrated TDD scenario or detector qualification.

Existing invalid-CRI tests still independently recover the authored invalid wire word under a declared CSI-present interpretation, and retain HARQ recovery and weak-ACK rejection checks. Their former present-only map assertions were replaced by direct public-map comparisons that include absence; no confidence threshold or CRC gate was relaxed. The production change is 67 added and 23 removed lines across the two existing helpers, not another decoder framework.

**Boundary still open:** this fixes the resource-invariance path used after received CSI interpretation fails. It does not yet resolve CSI presence in the nominal successful-decoder path, select among CSI-present/absent data decodes, wire independent combined PUCCH, or implement normal SR lifecycle. A high short-code posterior remains conditional on a chosen schema, not proof that CSI was sent. The public API itself takes CSI lengths as inputs; it does not infer them ([MathWorks `nrULSCHDemultiplex`](https://www.mathworks.com/help/5g/ref/nrulschdemultiplex.html)). Full-suite, integrated 12 dB, and consolidation remain pending.

Next integration boundary: extend the existing `PUSCHUCIDemultiplexer.receive` / `receiveConfiguredUCI` / `PUSCH_Rx` flow to retain receiver-owned present/absent interpretations and use actual received codeword/TB evidence without borrowing the TX-selected rate-matched length. Reuse `decodeResolvedULSCH` and the common HARQ commit. Preserve unresolved CSI if evidence is ambiguous; an absent UCI-only transmission has no TB CRC to select it. The supplied coding-layout contract also needs careful review: `localResolveRxCodingLayouts` currently requires exact rate-matched length, while `decodeResolvedULSCH` binds that length to each map. Do not simply remove those guards or use a TX layout to choose the receive hypothesis. Required full-suite and broader guards remain due; the still-live old full suite does not qualify these changes. No commit, merge, push, cleanup, or job cancellation occurred.

## 11:44 IST checkpoint: bounded CSI execution-trace repair passes

The v2 batch recorded below is now terminal: `logs/uci_csi_selection_tdd_runtime_v2_20260916.log` exited 0, with actual TDD CSI-only and combined HARQ/CSI delivery cases plus five selected selection/export/scheduler guards passing. Log SHA-256: `C6A387643AABFCABB27CF5BF5648ED42A88492F465F84EF1867B3BFA107DDEEE`. Its 29 captured source hashes matched at completion. This qualifies those bounded cases, not independent normal-runtime omission selection or the integrated 12 dB scenario.

An additional reporting defect was found in `CoupledTruthRuntime.updatePUCCHGrantTraceAfterObservation`: it unconditionally marked a CSI reservation executed when processing a shared physical reception, even if UE selection omitted every CSI report. The development patch sets that logical CSI row to `GrantExecutedFlag=false`, `Status=OMITTED`, and `PUCCHGrantState=csi_report_omitted_by_capacity`, while retaining the receiver's independent `PUCCHDecodeOk` result and the HARQ row's execution state. Receiver success is not forced or erased using UE selection metadata.

The v3 regression passed the real shared TDD reception/power-export section, then failed in its new explicitly analytic copied-state input because the input lacked mandatory `DTXFlag`. Log retained: `logs/uci_csi_omission_trace_v3_20260916.log`, exit 1, SHA-256 `6C1ED981863F3638829B01DD1B0E52232FF36EA6B717CE0385D50D7EDB4B4D7B`; all 29 source hashes matched at completion. The production receiver-disposition assertion remains unchanged. The fixture now explicitly declares `DTXFlag=false`.

The corrected v4 batch completed with **exit 0**: actual combined TDD delivery, both copied-state omission/receiver-result checks, and three selected guards (`testPUCCHCSIWholeReportSelection`, `testArtifactIntegrity`, `testSchedulerGrantConsistency`) passed. Log `logs/uci_csi_omission_trace_v4_20260916.log`, SHA-256 `D873229E2F4330E85977633511749CC9C59EEC28F510886712937EC8D78AD173`. All 29 source hashes matched the prelaunch receipt at completion; `git diff --check` passed. This closes the bounded false execution-flag defect, not all per-report measurement/scoring semantics.

The new copied-state check is not an actual omitted-CSI waveform episode. That episode, the short-payload omission procedure, normal SR lifecycle, independent combined reception, remaining detector/SRS/measurement repairs, final-source required suites and consolidation remain open. No new commit, merge, push, process cancellation, or log deletion occurred.

The next integration root is confirmed directly in current code: `prepareSharedPUCCHFeedbackRuntime` creates `GNBReception` only in its HARQ-only/no-CSI-overlap branch; `buildScheduledHARQTransportReception` explicitly rejects overlapping CSI/SR; and `runPUCCHWaveformTrial` otherwise uses the TX assignment and TX-derived report context. Removing those rejection guards alone would be incorrect. Extend the existing scheduled receive-obligation builder and completion/commit path, preserve independent installed calendars and per-field validity, then prove fixed-IQ invariance under TX-metadata changes. Do not add a second decoder or a second physical capture owner. The isolated omission selection test's explicitly declared receiver schema does not prove this normal-runtime integration.

## 11:29 IST checkpoint: whole-report CSI selection implemented within declared boundary

The next UCI patch is in the isolated development checkout. `PUCCHResourcePlan` now keeps the requested-report digest and selected `TransmittedReport` separately. For dynamic HARQ/CSI overflow, it retains the longest priority-ordered prefix of whole reports that fits the selected resource, recalculating the allocation CRC criterion for each prefix. It does not truncate bits, skip a larger high-priority report to squeeze in a smaller lower-priority one, increase power, or change the original resource set/PRI. The omission branch uses the configured resource width; it is distinct from the minimum-width all-reports-fit branch. `PUCCHConfigBuilder` materializes only the selected report, and the direct combined-assignment API can return that report as its second output. Reusing the original requested report after omission fails the exact digest guard.

`PUCCHReceptionAssignment` supports an explicitly declared gNB omission hypothesis without taking UE report contents/omission metadata. This is a component allocation capability, not yet independent normal-runtime hypothesis selection. `CoupledTruthRuntime` now exports separate UE requested/transmitted report counts, omitted IDs and selection reason. Its TX payload labels/counts use the selected report. These audit values do not force receiver validity. A subsequent unverified reporting refinement distinguishes omitted/not-delivered CSI from decode-failed/not-delivered CSI when the receiver has no usable CSI.

**Standards correction to the earlier capacity patch:** TS 38.213 section 9.2 explicitly assumes 11 CRC bits for resource selection when A>=360. That is distinct from the actual two-code-block CRC count in TS 38.212. `PUCCHResource` now exports `AllocationCRCBits`/`AllocationInputBits` separately from `TotalCRCBits` and separates the selection rate from the actual information-plus-CRC rate. A native-encoding regression at A=385, E=1152 verifies allocation using 396 bits and actual encoder overhead of 22 CRC bits (407 bits); four PRBs satisfy the configured 0.35 selection criterion. This corrects the earlier resource-budget use of the total segmented CRC; the encoder's total-CRC accounting remains intact. See [TS 38.213 sections 9.2 and 9.2.5.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

Evidence: `logs/uci_csi_selection_v1_20260916.log` completed with **exit 0, eight selected tests passing**, SHA-256 `B72104BAA9565AFE5801B8983D4562C1AE22C7C6E772246A46875BD293ADC593`. The new whole-report test checks out-of-order priorities, CRC transitions, retained configured width, actual selected waveform/power, unchanged HARQ, independent declared component RX, stale-request rejection, all-CSI omission leaving four HARQ bits, and duplicate identities. Existing short-SR reference, combined component, CSI-only resource, independent-trial and shared CSI-enabled/nonoccasion tests also pass. The shared nonoccasion case includes two actual isolated DL transmissions and two absent-UCI receiver outcomes; it is not combined CSI reception. All 28 captured changed/new source hashes matched at completion. Capture was at the receipt checkpoint, not a prelaunch repository snapshot.

**Still open:** omitting all CSI with only one or two HARQ/SR bits remaining explicitly raises `CSIOmissionShortPayloadProcedureRequired`. The supported implementation does not pad those bits or silently force a long format. CSI-only multi-report selection and separate Part-2 coding remain guarded. The new omitted-report branch still needs an actual coupled-runtime regression and independent normal receiver selection. SR lifecycle, missing-DCI/transport handling, detector/SRS/measurement closure and consolidation remain open. Do not describe this as complete CSI/HARQ integration.

At this checkpoint `logs/uci_csi_selection_tdd_runtime_v2_20260916.log` is running CSI-only and combined-HARQ/CSI **TDD** shared-clock cases, followed by five selected selection/export/scheduler guards, on frozen development source. The added delivery-reason refinement and shared-clock audit assertions postdate v1. Final-source unfiltered `testAll`, required broader guards and the integrated 5 MHz / 12 dB run remain due. Neither old validation checkout contains these changes; no merge, commit, push, cancellation or log deletion occurred.

## 11:15 IST implementation checkpoint: planned-report binding repaired

The reproduced stale-payload defect below is now repaired in the isolated development checkout, not yet consolidated into the IDE checkout. `PUCCHTransmissionAssignment.fromResourcePlan` carries `plan.ReportDigest` into the immutable assignment. `PUCCHTransmitter.transmit` rejects a different digest before resource mapping/coding. A missing binding rejects unless the assignment is explicitly isolated calibration, is not eligible as connected-mode evidence, and carries no allocation budget. Relabelling a budget-bearing assignment as calibration does not bypass the check.

`testPUCCHCodeRateAllocation` now covers the exact 11-to-12-bit reproducer, changed bits with unchanged length, changed HARQ/SR ownership with unchanged total length, changed RNTI/target slot, five malformed bindings, three missing-binding/bypass attempts, and the explicit calibration factory. The two SR fixtures now re-plan each changed report; their existing reference-waveform and recovery assertions are unchanged. No detector threshold, power scale or acceptance assertion was relaxed.

`logs/uci_report_binding_v1_20260916.log` completed with **exit 0, ten selected tests passing**: allocation/binding, short SR, all 14 original Format-0 reference cases, combined component reception, Formats 0-4 receive equivalence, power-resource authority, planning without power, independent trial reception, active power and normalized transmit reference. SHA-256: `400F55907C30F4A849C281DB521A0AE694763A863CA723328DCAEAAE08677EAF`. The companion source-binding JSON records all 26 changed/new source hashes over base `5d20e64d`; none changed between capture and completion. `git diff --check` also passes.

This closes the exact-report TX binding defect, not all resource/report correctness. Whole-report CSI selection/disposition, SR lifecycle and independent combined-runtime reception remain the next work within the same package. Required unfiltered final-source `testAll`, broader guards and the integrated 12 dB run remain due; this focused receipt cannot substitute for them. No new full-suite queue, process cancellation, commit, merge, push or cleanup occurred. Original failed evidence remains preserved.

## 11:08 IST diagnostic checkpoint: exact payload binding must precede omission

No production code or test assertions were changed during this checkpoint. The 24 changed/new source files still match `logs/uci_capacity_checkpoint_20260916_source_binding.json`. A new, bounded MATLAB diagnostic completed with exit 0 **because it reproduced a defect**, not because the implementation passed qualification.

Evidence: development-checkout `logs/uci_plan_binding_diagnostic_20260916.log`, SHA-256 `F54A637528305D128DC61804EA3D5001DED64D1F5D8169A2389217A38C2BB7A5`.

1. Build the actual configured TDD HARQ plan for 11 bits at `max_code_rate=0.35`; materialization selects one PRB, E=32, and records a satisfied rate of 11/32.
2. Keep the materialized assignment, report ID and epoch unchanged, but construct a typed report containing 12 HARQ bits. Its report digest differs.
3. `PUCCHTransmitter.transmit` accepts it and generates the physical waveform with A=12, E=32. Including its six CRC bits, the actual rate is 18/32=0.5625, while the assignment still describes the 11-bit budget as satisfied.
4. Independently planning the 12-bit report with the same configuration selects two PRBs, E=64. This is not the permitted maximum-resource HARQ-overflow branch: a second configured PRB is available and the reused budget claims success for a different payload.

Exact cause: `PUCCHResourcePlan.ReportDigest` is checked by `PUCCHConfigBuilder.materialize`, but `PUCCHTransmissionAssignment.fromResourcePlan` copies only `plan.Data`, which does not carry that digest. `PUCCHTransmitter.m:11` checks report ID/epoch, not exact report content. Thus a correct planning-time capacity check is not an end-to-end immutable contract. This diagnostic deliberately changes the payload; it does not claim that the integrated runtime has already made that substitution.

### Next patch boundary within the same UCI work package

| Existing file/boundary | Required replacement/addition | Exit proof |
| --- | --- | --- |
| `PUCCHTransmissionAssignment.fromResourcePlan`, `PUCCHTransmitter.transmit` | Carry and enforce the planned transmitted-report digest before coding. Preserve explicit calibration compatibility rather than inventing a digest from the supplied replacement payload. | Original report transmits; same-ID/epoch changed bits, changed length or changed owner layout is rejected. Preserve unchanged power/carrier checks. |
| `PUCCHResourcePlan`, `PUCCHConfigBuilder` | Represent requested and selected transmitted reports separately; bind the selected report, its serialization, resource and power allocation consistently. Keep requested-report identity and whole-report omission reasons as UE audit. | CRC transitions and priority-prefix report selection, including omitted-all-CSI and no-fit boundaries; no truncated bits or inflated resources. |
| `CoupledTruthRuntime` prepare/completion and `appendPUCCHFeedbackTrial` | Replace original producer-derived `hasCSI`/bit-count assumptions with separate TX disposition and independently received field validity. Do not publish omitted CSI, and do not feed UE omission state into gNB hypothesis selection. | Actual selected waveform ownership matches TX audit; fixed RX inputs remain independent of TX metadata; no-producer/absent/ambiguous CSI cannot become successful CSI publication. |

The whole-report priority/capacity procedure is specified in TS 38.213 section 9.2.5.2 ([Release 18.8, page 146](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf)). The all-CSI-omitted boundary that leaves only one or two HARQ/SR bits needs an explicit, verified coding/resource procedure before relaxing the present long-format A>=3 guard. Native encoder support alone does not establish that procedure. This unresolved design detail is not permission to pad payloads or silently reselect a resource.

Normal SR lifecycle, independent combined reception, detector qualification, SRS prediction, final measurement/export verification and source consolidation remain open as itemized below. The old full suite is still executing `d05c1441`; the `5d20e64d` queue still reports `waiting_for_prior_pipeline`. Neither includes these development edits. No additional full-suite queue, process cancellation, merge, commit or push occurred. The pending request to retire these old jobs has not received a response.

## Implementation status at 10:59 IST (11:01 checkpoint)

The isolated development checkout now fixes Format-0 HARQ/SR waveform interpretation, Format-1 SR-only modulation, and absent-SR transmission accounting. It also replaces the interim global HARQ/CSI permission with format-owned configuration. The original 14-case Format-0 reference regression passes unchanged; nine further focused regressions and a six-test per-format-policy batch completed successfully. These are overlapping component/regression batches, not independent statistical episodes or a full-suite pass.

The subsequent capacity patch now separates total CRC and segmentation filler, declares Format-2 `max_code_rate=0.35` in the TDD scenario, and connects procedure-specific allocation to TX planning and independent RX assignments. Selected PRBs bind transmit power bandwidth; runtime carrier geometry must match the allocation. CSI+SR without HARQ retains the configured CSI resource. Whole-report CSI omission, separate Part-2 coding, normal SR lifecycle, Format-1 mixed-resource arbitration, and independent combined-runtime reception remain unfinished. Over-capacity CSI and separate Part-2 now reject before transmission instead of receiving a false capacity claim.

The preceding 18-test guard batch completed with exit 0, including both required E2E guards. It does not qualify the newer capacity patch. The first capacity batch passed its new tests but failed the unchanged quarantined Phase-05 artifact test; that failure is retained. The subsequent ten-test allocation-integration batch and six-test edge/config/power batch both completed with exit 0. No batch here is unfiltered `testAll`. The two existing validation checkouts remain unchanged, and their queued 12 dB run does not contain these corrections. No implementation batch is currently live; the older pipeline remains live, pending the user's decision on retiring obsolete validation jobs.

## Current decision summary (09:57 IST, for the 10:01 planning checkpoint)

The sections below retain the diagnostic history; later counterexamples refine earlier proposed fixes. The bounded short-SR and per-format-permission repairs have crossed their diagnosis gate and are implemented as recorded above. **The complete wire/resource integration gate is not yet closed.** Do not implement a new combined receiver against the currently incomplete resource/coding contract.

| Unit | Proven defect or gap | Remove/replace; reuse/add | Exit evidence |
| --- | --- | --- | --- |
| UCI wire/resource contract | Normal SR omitted; short-format SR mapping wrong; missing per-format permission/rate; 11-to-12-bit CRC transition changes capacity | Replace global interim permission and flat short-SR bits. Reuse installed calendars, existing SR state types, serializer and resource planner; add per-format authority and correct capacity/reservation binding. | Existing SR semantic guard plus public-reference encoding, positive/negative SR, CRC/rate/minimum-PRB boundaries and invalid-policy rejection. |
| Independent combined reception | Actual normal PUCCH uses TX context; CSI publication is producer-gated; missing-DCI/absent-CSI interpretations can be observationally ambiguous | Replace strict-path TX context and producer acceptance authority. Extend existing receive assignments, invariant PUSCH UCI mapping, physical captures and common commit; preserve unresolved fields explicitly. | Fixed-IQ/TX-metadata-poisoning tests, missing/all-missed DCI, absent CSI, transport overlap, duplicate/stale/late commits; no universal unqualified confidence rule. |
| Detector | Original 12/1,024 false ACK failure remains; invalid metrics separately fail open | Replace invalid-input fallback. Retained raw-IQ replay now reproduces the finite metric/counts, and the existing null model identifies an inadequately qualified threshold/search-space policy; reuse physical qualification harness. | Unchanged original gate plus independent signal/noise campaign and supported-format coverage. See the later detector-root reconciliation; qualification remains open. |
| SRS prediction | Missing configured CDM; output anchoring erases gain; complex averaging creates loss; singleton grid axes become antennas; native hopping is misdetected | Replace missing-field CDM default, matrix-shape inference, pre-SINR complex averaging, post-SINR anchor and nonexistent hopping-property lookup. Add explicit domain/support and pilot/data-energy contract to existing estimator/callers. | Reference grouping checked across 468 cases; normalized energy/MMSE checked across 648 cases. Noisy/hopped receiver and integrated prediction checks remain. Thermal-mode energy authority remains separate. |
| Finalization and exports | Old receive-tail abort; FER populations disagree; reference tables omit identity; user snapshot sums successful attempts rather than unique TB delivery | Preserve candidate tail fix. Align existing FER populations and identity binding; reuse existing first-success TB accounting for user goodput, retaining attempt throughput separately. | Final-slot decode; independently recomputed BER/BLER/FER/goodput, including repeated successful decoding after lost ACK; all measurement/CSV/PNG gates on one revision. |
| Regression and consolidation | Some old failures are contradictory fixtures; semantic test missing from suite; SRS test asserts wrong anchor contract; evidence spans revisions | Repair only proved fixtures; register existing omitted guard; replace wrong mathematical expectation with independent assertions. Reconcile stash/patches before merge. | Final-source required suites/guards, successful integrated 5 MHz TDD run, then verified commit/remote/clean tracked tree. |

Still unproved: detector policy qualification under actual RF/timing, noisy/general SRS CDM coverage and thermal-mode energy authority, all historical regression roots, complete measurement/export acceptance, and R2023b execution. Later sections settle the retained finite-metric arithmetic and normalized-path energy interpretation without claiming those broader qualifications. Do not turn this bounded audit into a claim that every simulator issue is known. FDD and 400 MHz remain deferred. No production changes were made during these diagnostic checkpoints, and neither frozen validation revision contains the proposed repairs.

## Source and evidence boundaries

- The IDE checkout is `e6341805`, not the latest candidate. Its existing deletion of `logs/README.md` was left untouched.
- Latest candidate: `5d20e64d`, branch `work/tdd-pucch-noise-authority-20260916`, checkout `sixgr_pusch_receive_only_validation_20260914`. Its clean source remains frozen for validation.
- The executed 58-slot scenario used `d05c1441` in `sixgr_pucch_rx_9fbb6c408dfe4eb09e7cdec366629228`. It exited **1**, after 19 DL and 5 UL completed trials, with `SharedDataReceiveTailNotDrained`. Its failed-report recovery also failed semantic validation. It did not pass.
- At this checkpoint the old `d05c1441` pipeline has moved to `testAll`; the repaired `5d20e64d` scenario is still waiting for that pipeline. A running MATLAB process is not evidence that the repaired scenario is running.
- Detached development checkout `sixgr_tdd_combined_receiver_20260916` is based on `5d20e64d` and now contains the small, uncommitted multiplexing-permission patch started before the analysis-first instruction. It is not the queued candidate. Source locations below refer to that base revision unless explicitly identified as this isolated patch, not the older IDE files.
- Read-only branch ancestry check: no local branch tip lies outside `5d20e64d` ancestry. This does not reconcile the preserved stash, historical patch contents, ignored evidence, or IDE working-tree changes.

## Why the previous work did not close the issues

1. Component APIs and normal runtime routing are not equivalent. The independent PUCCH receiver exists, but normal combined feedback bypasses it.
2. Some tests deliberately supply payload schemas, use high-SNR isolated fixtures, or assert unsupported-case rejection. Passing them does not demonstrate connected, mixed-UCI operation at 12 dB.
3. Implementation and validation revisions diverged. Old-suite passes cannot qualify subsequent edits.
4. Measurement production, finalization and validation use separate contracts. Arithmetic can pass locally while units, populations or required identity columns disagree at export.
5. A detector pilot, an analytical threshold candidate and accounting tests are different deliverables from a held-out noise/signal qualification campaign.
6. Some semantic guards are not registered (`testPUCCHFormat0SRSemantics`); another registered test explicitly asserts an incorrect mean-SINR anchoring contract (`testLLSULSRSRITPMIEstimator`). Test coverage and the mathematical correctness of its expected result both need review.

## Repair decisions, by root cause

### 1. Normal combined PUCCH: confirmed production integration gap

Evidence: `logs/measurement_audit_20260916/control_feedback_0733/receipt.json` in the executed checkout has 195 checks, 190 passing and five failing independent-assignment checks. Actual slots 34, 39, 44, 49 and 54 all report `IndependentReceiverAssignment=0`.

Source chain:

- `+sixgr/+truth/CoupledTruthRuntime.m:1300`: `prepareSharedPUCCHFeedbackRuntime` installs `GNBReception` only for HARQ-only rows with no eligible produced CSI and no available configured CSI occasion. Even an unproduced periodic CSI occasion excludes this path.
- `+sixgr/+truth/buildScheduledHARQTransportReception.m:42`: CSI overlap is explicitly unsupported; SR overlap is rejected at line 58. Its PUSCH transport selector also guards combined CSI.
- `+sixgr/+link/runPUCCHWaveformTrial.m:81`: without `GNBReception`, receiver assignment/context remain the transmitter-side inputs.
- `CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime` then has two feedback-commit routes: independent scheduled mapping versus legacy producer-row application.

Change the existing scheduling/preparation/completion boundary so gNB resource and schema decisions use installed configuration and its transmitted schedules, never UE report contents or chosen length. Reuse `buildConfiguredPUCCHReceiveContext`, `PUCCHReceptionAssignment`, `receivePUCCHObservation` and the scheduled feedback commit. Do not create another receiver stack.

Remove the transmitter-assignment fallback from the **strict shared runtime** after replacement and negative tests. Preserve explicitly labelled component/replay APIs where legitimately needed. Replace the CSI/SR exclusion branch with implemented policy, not a deleted guard. Do not set the independence flag manually.

Unresolved design question: a configured CSI occasion does not prove that the UE can produce CSI. A receiver-owned set of hypotheses may be required, but selecting a short UCI length from unprotected short-block decodes can be ambiguous. Do not select by comparing with expected TX bits or assume every payload has a CRC. First reproduce absent CSI, missing-last-DCI and ambiguous-length cases; document rejection/DTX behavior before implementation.

### 2. SR and multiplexing policy: confirmed missing normal-path inputs

`+sixgr/+phy/+pucch/PUCCHConfigBuilder.m:112` always sets `SchedulingRequestReports=struct([])` in `localPlan`, including `planCombined`. The combined component test supplies SR manually; that does not exercise this runtime builder. Installed SR calendars are not an implemented positive-SR/MAC lifecycle.

No `simultaneousHARQ-ACK-CSI` or corresponding simultaneous-HARQ/CSI policy was found in the inspected configuration and PUCCH planning surface. `PUCCHResourcePlan` chooses resources from payload ownership/count but does not establish that higher-layer permission.

Before wiring combined RX, define this permission in the existing YAML/schema/RRC context, propagate it through `buildInternalConfig`, and enforce it in `PUCCHResourcePlan`/`PUCCHConfigBuilder`. Explicitly configure the intended combined scenario; do not silently disable CSI/SR to pass. Add a real typed SR producer input, calendar/priority/collision handling and decoded-state consumption to the existing runtime path. Standalone SR helpers must not be counted as integration.

Standards basis: [TS 38.213 V18.8.0, 9.2.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf) makes HARQ/CSI multiplexing conditional on higher-layer configuration; otherwise CSI is dropped. Sections 9.2.5.1/2 govern SR and mixed-UCI handling. This is a configuration/procedure requirement, not permission to invent receiver knowledge.

### 3. Missing DCI, DAI wrap and PUSCH: mechanisms exist; combined closure is unproved

Keep the distinct sources of truth: `buildReceivedHARQACKCodebook.m` uses UE received events; `buildScheduledHARQACKMapping.m` uses physically transmitted gNB assignments. `buildSharedPUSCHUCIReceiveContext.m` binds independent UL-DAI authority; normal PUSCH completion invokes the common scheduled feedback commit. These must not be replaced with a shared expected-bit array.

Required work is at the transport boundary and combined policy, not another Type-2 layout implementation. Audit `buildSharedPUSCHCSIReceiveObligation.m`: it selects CSI schema from a configured overlapping occasion; absence of an eligible UE report needs an explicit receiver procedure, not access to `PendingCSITable`. Verify both transports for first/middle/last/all DCI loss, DAI wrap, missing UL DCI, no producer, PUCCH/PUSCH overlap, duplicate/stale/late completion and epoch changes. A zero-UCI or one-positive-HARQ component pass is insufficient.

### 4. PUCCH detector: retained failure is real; accounting is not the repair

Production scenario `lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml` still explicitly selects Format-0 two-symbol threshold 0.42. Retained two-bit noise result is 12/1,024 false ACK bits (1.171875%), exceeding its configured 1% limit. The separate 0.77 model-derived candidate is not installed or qualified. The provided-noise authority bug in `PUCCHReceiver.m` was separately fixed in `a1c9a929`; that is not a false-ACK qualification fix.

This audit reran `python -m pytest tests/test_pucch_noise_evidence_audit.py -q`: **48 passed**. These tests preserve/verify the original failing evidence; they are not 48 new RF episodes or a detector pass.

Do not add more counting wrappers. Use existing baseline/pilot/campaign tools to compare the unchanged original failure, signal-present missed ACK/NACK-to-ACK behavior, actual acquired timing and the receiver metric. Freeze the accepted receiver policy only after development tests; then use separate held-out episodes. `pucch_tdd_detector_held_out.yaml` requests 600 episodes but still declares `development_history_complete: false`. Resolve that evidence limitation honestly; changing the flag alone proves nothing. Format-0 evidence does not qualify Formats 1-4 or the combined payloads used in the actual run.

### 5. CSI timing and original DL-clock failure: do not keep reporting repaired failures

The retained `73867a4` full-suite log records passes for `testCSIRuntimeExecution`, `testCoupledTruthCSIReportSourceAuthority`, `testCSIReportPublicationClock`, shared CSI-clock variants and late PUSCH CSI delivery. The old timing/CRI fixture failures are not established current failures. The original DL clock boundary was crossed; the latest executed abort is the different receive-tail error.

Actual failed-run snapshots have five CSI measurements and four delivered DL CSI reports with successful clock/source/decoded-bit checks. The raw CSI trial's unhydrated report-status fields are not alone proof of a new producer bug: final `localBindCSIReportCausality` in `runWaveformLinkBundle.m:1744` was not reached.

Keep the existing availability/calendar fixes. Test final hydration after successful execution, plus gap/BWP/epoch/no-measurement cases through the combined transport. [TS 38.214 V18.8.0, 5.2.2.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf) excludes measurement-gap slots from valid reference resources and requires qualifying measurements before reporting after activation/configuration changes. A periodic occasion is not proof that CSI was transmitted.

### 6. Final receive tail: root cause fixed in candidate, integration still pending

The executed run stopped advancing physical reception at its last scheduling slot although the last allocation's registered receive window extended past it. The old queue test advanced an extra full slot and missed this production boundary.

`5d20e64d` changes `CoupledWaveformStream.drainDataReceiveTail` and finalization in `runWaveformLinkBundle.m:3834`; it uses the actual registered endpoint without a new scheduled transmission. Four focused tests passed, including exact tail extent and independent PUSCH completion. Keep this repair; do not add a second drain, pad RX with zeros, extend the traffic horizon or suppress the pending-data assertion. Acceptance requires actual final-slot DL decode and final exports on this revision or its tested successor.

### 7. Measurement/export closure: two confirmed contract mismatches and remaining checks

Existing candidate repairs to preserve: normalized/absolute carrier-power separation (`6f2fd2ed`), SSB-window RSRQ preservation (`3258e469`), DL raw/residual SINR export (`41f3f8aa`). These passed focused checks but are not present in the executed `d05c1441` run.

New confirmed FER mismatch: `exportLLSLiveDerivedTables.m::localBuildErrorRateRowsForScope` uses all supplied completed rows; `tools/lls_csv_semantics.py::_raw_rows_for_scope` filters through the SINR-analysis/warm-up population. Actual DL data contain 19 rows across frames 4,5,6; the filtered population is 11 rows across frames 5,6. Exported `ObservedFrames=3` cannot equal the validator's two frames. Also, MATLAB and Python use different ordinary frame-key rules and different crash handling.

Repair the FER population contract, not the reported number to satisfy a test. Use executed finalized TB outcomes for run FER; distinguish any post-warm-up FER explicitly. Do not discard decode failures merely because SINR is unavailable. Align run/UE, sweep/drop/frame and error semantics in the existing producer and Python validator. Add fixtures with warm-up, missing SINR, CRC failure, crash and repeated frame IDs across sweep points.

New confirmed identity mismatch: `runWaveformLinkBundle.m::localBuildCQITableReferenceTable` and `localBuildMCSTableReferenceTable` omit `ConfigHash`/`ScenarioID`; the semantic gate requires both. The actual CSV headers confirm the omission. Bind the resolved identity at the existing writer boundary; audit the duplicate system-level writer. Keep reference tables labelled as configuration/reference, not RF observations. Do not manufacture measured rows or weaken required identity checks.

Failed-run recovery also reported missing angular diagnostic and checkpoint/determinism evidence. These artifacts are absent after the aborted run; a successful-run producer defect is not yet established. Trace `exportPHYSignalDiagnostic`, `exportLLSReportingBundle`, `buildPhase7ReadinessArtifacts` and recovery orchestration before modifying them. Preserve the original PHY error alongside recovery failure; do not synthesize conformance evidence for an incomplete run.

Remaining integrated checks: power/noise/loss and reference planes; scoped RSRP/RSSI/RSRQ; configured reference SNR versus measured post-equalization SINR; full-symbol EVM; channel estimates/NMSE; BER/BLER/FER and their populations; unique-TB goodput versus scheduled/wall-clock throughput; CSI/SRS timing/source; final CSV-to-PNG identity and numbers. Existing partial EVM/accounting passes are useful evidence, not all-measurement closure.

### 8. Regression debt: distinguish symptoms, proven fixture faults and unknown causes

Retained `73867a4` full suite failed/incompleted and then exhausted memory. Its stale `summary.json` says running; terminal `launcher.json` says exit 1. Four intentionally failing `regressionHarnessProbeTest` messages are harness self-tests, not four simulator defects. Fourteen real pre-OOM failures remain a historical list, not fourteen reproduced failures on `5d20e64d`:

| Test(s) | Evidence / next minimal action |
| --- | --- |
| `test6GLLSMultiUserBeamforming` | `MissingReceivedULTiming`; FDD scenario, deferred, prevents an unqualified claim of full `testAll` success. |
| `testLLSCoupledTruthHARQRoundTrip` | Same error class; source diagnosis below identifies disabled access against required received timing. Inherits the FDD causal scenario; repair/runtime qualification deferred with FDD, not a reason to inject timing into TDD. |
| `testPRACHRuntimeULDirectionAntennaContract` | Assertion expects old resolver text `executed_PRACH_transmitter_indices`; producer now emits `executed_PRACH_native_grid_and_applied_port_mapping`. Verify actual indices/domain against TX, then repair stale text expectation without relaxing occupancy checks. |
| `testTRSRuntimeControlGatingEvidenceContract` | Receiver evidence unusable; inspect retained receiver status/clock/occasion. Root cause not yet established. |
| `testRAStageCarrierSlotBinding` | Fixture changes `Msg3Slot` to 23 while decoded RAR still schedules 15. Make the authored RAR/TDRA and target slot agree; retain independent expected DM-RS checks and mismatch rejection. |
| `testRADownlinkPowerScaling`, `testRuntimeOperatingAuthority` | No legal Msg4/setup before expiry 78 with K2=1. Enumerate the fixture's legal allocations; distinguish contradictory fixture from scheduler error before changing either. |
| `testLLSRawTrialProvenance` | Nonfinite input during exact resource accounting. Locate original nonfinite operand; do not fill it with a plausible TBS or finite default. |
| `testLLSResultRichness`, `testLLSReportBundle` | Unsupported configured TRS symbol pair; reconcile fixture with installed pattern and test explicit rejection of invalid pairs. Do not disable TRS to pass. |
| `testLLSHARQExercise` | Fixture sets selected K1=2 but does not update allowed K1 candidates. Author consistent selection/candidate list; retain invalid-selection rejection. |
| `testLLSScenarioStatusPropagation` | Missing explicit PDSCH execution profile. Inspect intended connected/calibration authority; no automatic fallback to calibration. |
| `testLLSResolvedFeatureConfigAuthority` | Fixture disables legacy power-control fields while canonical `rf_frontend.ul_power_control` takes precedence. Inspect resolved inheritance, align intended canonical declaration and test conflicting aliases. Do not silently change production power authority. |
| `testULNoiseVarianceValidation` | Specific explicit-noise bug repaired in `a1c9a929`; original assertion passed in focused rerun. Final-source suite still due. |

Later `testLLSPUSCHHARQACKRuntimeFeedback`, `testLLSPUCCHWaveformFeedback` and `testFRCNoiseReferenceContract` failed with out-of-memory. Rerun with capacity before attributing PHY defects. Older `docs/lls/testall_5689ed33_failures_20260915.csv` retains a broader historical list; it must be reconciled against the final suite, not erased or asserted current wholesale. R2023b remains a separate unverified compatibility target.

## What to remove, and what not to remove

- Replace strict-runtime TX-derived receiver assignment/context and legacy producer-row feedback commits with the existing independent scheduled path once combined cases pass. Do not delete legitimate isolated APIs without caller review.
- Replace inconsistent FER population/grouping logic; consolidate duplicate reference-table identity binding. Do not change PHY outcomes to make exports agree.
- Remove contradictory fixture overrides after proving the intended fixture contract; keep negative assertions and original failed evidence.
- Do not add another receiver, a new orchestration framework, repeated count/audit wrappers, a second schema system or another automatically launched full-suite queue.
- Do not delete guards, old logs, stash, patches or branches merely to make the repository look clean. Reconcile content first. Do not delete a failing test as a fix.

## Ordered completion plan and estimates

1. **Before code:** reproduce the remaining uncertain roots and settle the combined TX/RX contract (CSI absence, SR, last-DCI ambiguity and installed multiplex permission). Budget 1-3 focused engineering hours; this is not a promised fix deadline.
2. **First implementation task, after the diagnosis/design gate:** complete one normal combined-feedback path through the existing boundaries, including source-isolation tests that poison TX payload/length while keeping receiver inputs unchanged. Then cover both transports and missing/late/duplicate cases. The earlier 1-2 working-day allowance is withdrawn as an unsupported forecast, not replaced by a guaranteed 2-3 hour completion. Estimate the actual patch only after the receiver ambiguity and ownership contract are settled.
3. **Existing tail repair and reporting contract fixes:** targeted production-path reproducers, corrected finalization, final FER/identity checks, and all measurement-family review. Budget 4-8 engineering hours plus execution; broader historical regressions may extend it.
4. **Freeze one revision:** focused gates first, then unfiltered `testAll` and required NR/config/strict/scheduler/export/E2E guards. Do not launch redundant full suites while changing source. An older 26-test guard batch took about 1.72 hours; the full suite has no reliable finish bound because previous runs crashed/OOMed.
5. **Integrated 5 MHz TDD / configured 12 dB:** run on that frozen source, inspect actual last-slot completion, independent UCI ownership and final CSV/PNG. The prior failed attempt occupied about 100 minutes including recovery; a rerun ETA is not a pass guarantee. A diagnostic run is possible before qualification, but must be labelled unqualified.
6. **Detector qualification:** current 600-episode plan at observed paired-pilot runtime of 624.49 seconds per eight-case episode implies roughly 104 serial compute hours, before auditing/overhead. This is an extrapolation, not a benchmark of the second server. Measure that server first; any parallelization must preserve independent seeds/state and frozen receiver policy. The existing plan is not a same-day full qualification.
7. **Consolidate only with evidence:** reconcile stash/patches/IDE edits, keep logs recoverable, verify final commit and remote, and report remaining deferred FDD/R2023b issues explicitly. Preserve the configured sweep `[-30,-20,-10,0,10,12,20,30,40]`; 400 MHz remains deferred.

No claim that all root causes are established: remaining uncertainties are explicit. No full-suite pass, qualified-main merge or successful 12 dB run is claimed by this audit.

## Analysis-first checkpoint: direct reproducers and design consequences

Evidence directory for this checkpoint: `C:/Users/anup0/AppData/Local/Temp/sixgr_tdd_combined_receiver_20260916/logs`. These are diagnostic results, not a final-source qualification campaign. The isolated permission patch touches PUCCH configuration/planning only; the scheduler/TRS/RA source investigated here remains at `5d20e64d`.

| Finding | Direct proof | What to change / what not to change |
| --- | --- | --- |
| Multiplexing permission guard works in isolation | `pucch_multiplex_permission_v1_20260916.log`: five focused tests pass, including combined TX/RX component waveforms. | Keep isolated pending design review. Its boolean guard does not implement CSI dropping, SR lifecycle, normal combined reception or every resource-set restriction. Do not label it integration complete. |
| Short UCI lengths are not universally distinguishable | `short_uci_length_ambiguity_20260916.log`: all 8 three-bit and 16 four-bit prefixes produce identical `nrUCIEncode(...,64)` output when extended by seven zero bits. | Do not implement a universal winner-by-CRC/metric receiver. `UCIDecoder` correctly marks CRC inapplicable for small payloads; its neutral `CRCPassed=true` is not evidence of payload length. |
| The ambiguity survives actual PUCCH generation | `uci_waveform_ambiguity_20260916.log` and `.mat`: a typed, valid 7-bit CSI report (CRI=0, RI=1, PMI=0, CQI=0) consists of zeros. A four-bit HARQ-only report and the same HARQ plus this CSI generate bit-identical grids and time-domain waveforms on the same declared Format-2 resource. | This is an actual encoded-waveform component counterexample, not a complete RRC-conformance or noisy runtime qualification. No receiver can distinguish those two waveform inputs without additional independently known procedure information. Do not infer absent-versus-zero CSI from a decoder success flag. |
| Exact-grant fixture omits its data clock | `root_diagnostics_20260916.log`: original raw-provenance grant has no `ScheduledAbsoluteSlot`, Frame=1, Slot=1; original exact accounting fails on finite-input validation. A diagnostic slot binding advances to a different TRS error. | In `testLLSRawTrialProvenance.m`, construct canonical grant timing before `finalizeExactPHYFeasibility`, and carry that same timing through grant freezing. Keep `SchedulerBase.m` finite/ownership assertions. A plausible default in production is not a fix. |
| Same raw-provenance fixture has a second TRS configuration defect | Diagnostic slot binding exposes unsupported/missing TRS symbol pair. `localForceOneByOneWaveformFixture` supplies TRS slot authority but not a valid symbol pair. | Author the complete intended SISO TRS resource in the fixture's scenario input before config resolution. Do not disable TRS or invent reserved RE counts. Recheck `testLLSResultRichness`/`testLLSReportBundle`, which enable TRS on a base scenario without an authored pair. |
| RA timing configuration is duplex-infeasible | `root_diagnostics_phase2_20260916.log`: Msg4 symbols `[2,12]`, setup symbols `[0,14]`, K2=1; enumeration of every slot 0-77 finds zero legal DL/UL pairs, before resource checks. | Repair the authored setup-completion timing/grant consistently in `master_geometry_based.yaml` and dependent tests after checking allowed TDRA/DCI and processing time. Keep `RAEventScheduler` rejection. Do not relax TDD direction or extend timers hoping for a pair that never occurs. This is a broader TDD regression, not proof the 5 MHz scenario has the same configuration. |
| TRS runtime availability and strict scoring are different | Same log and `trs_root_diagnostic.mat`: detection 0.95335 > 0.55, coverage=1, channel estimate `3276x9x4`, runtime evidence usable=true, but NMSE unavailable and StrictOk=false with `trs_strict_components_incomplete:channel`. | `scoreTRSDetection.m:18` requires independently scored NMSE. The fixture calls standalone `runTRSTracking`; the normal shared completion passes executed channel references at `runWaveformLinkBundle.m:12954`. Rebuild the test around that actual observation/scoring path. Do not restore pilot-fit SINR as independent measured SINR, or remove the NMSE gate. |
| Status fixture lacks execution authority | First diagnostic log: inherited `phy.pdsch.executionProfile` and `run.pdschExecutionProfile` both empty; the test's YAML never specifies a profile. | In `testLLSScenarioStatusPropagation`, explicitly declare the intended isolated calibration profile, or build real connected assignments if connected status is the test intent. Keep `MissingExecutionProfile` rejection; no implicit fallback. |
| PUCCH EVM needs an explicit reference label | `PUCCHReceiver.m::localEVM` uses nearest QPSK decisions; `runPUCCHWaveformTrial.m` exports it as `ReceiverEVMPercent`. `testReceiverEVMReferenceNormalization` tests DL/UL data-channel reference EVM, not this PUCCH metric. | Retain decision-directed EVM under an explicit source/domain label. If reference EVM is required, score actual retained TX and receiver symbols offline without feeding TX information back to the receiver. A 90-degree QPSK rotation gives zero nearest-decision error but 141.4% original-reference EVM: these are not interchangeable metrics. Scope pi/2-BPSK/other-format review separately from the present Format-2 execution. |

The first diagnostic's TRS printing encountered a `<missing>` string formatting error. It is preserved in that log, not counted as a simulator failure. The phase-2 diagnostic saved the actual result and printed nonfinite fields safely; both logs are retained.

Additional RA counterfactual enumeration in the waveform diagnostic: over slots 0-19, K2=2 permits Msg4 slots `[2,7,12,17]`, K2=3 permits `[1,6,11,16]`, K2=4 permits `[0,5,10,15]`; K2=1 permits none. These are duplex-only candidates, not proof that changing one number gives valid decoded setup DCI, processing time or reservation ownership.

The HARQ-roundtrip fixture also explicitly disables initial access and random access while using the shared waveform runtime. `CoupledTruthRuntime.m:5142` marks shared UL timing required; `attachReceivedULTimingAuthority.m:13` rejects the missing received TAG. This explains the authority conflict at the source level; the repaired fixture still needs a focused physical rerun. Restore actual acquired/decoded timing in this fixture instead of inserting zero TA or disabling the requirement.

Selected diagnostic SHA-256 receipts:

- Short-code log: `5F131C90ED6C2CEDBEF6CA5DE1CF8582DCD607793F4FFED9F75EC7F42695D440`.
- Phase-2 root log: `264C338B4BA958D8867EB97D9D529023E1FD46A3EBF0E3AE8DF5E2C00DA59CAB`.
- Encoded-waveform counterexample log: `9BABCF174A4358AAC1BB96ECC61569D803DAD168EB2459B7C435F05B75D7429B`.
- Encoded-waveform retained MAT: `3092D08CA4A7DEB9024C6F8F37D1DBEC531263915A5451F27C03875B7AA8C6BC`.

### Combined-feedback design constraints before implementation

1. **Receiver inputs:** actual gNB transmitted DCI ledger, installed RRC/report configuration, gNB-known reference-signal schedule, acquisition/receive samples and immutable observation identity. Neither UE pending report presence, UE-selected payload length, expected ACK values nor UE pending-SR state may choose the receiver schema.
2. **Transmitter inputs:** UE-decoded DCI history and UE-produced eligible CSI/SR. Keep these authorities separate even when both objects reside in one simulator process.
3. **Missing last DCI:** `buildScheduledHARQACKMapping` retains only the last gNB grant for resource selection. The UE's last received DCI can be earlier. Review all physically transmitted candidate selections and Type-2 length implications; do not fix only middle gaps or assume an exact-length test detects physical short-code ambiguity.
4. **Ambiguity:** codeword equality is a mathematical limit, not a decoder defect. A candidate design may retain all observationally equivalent interpretations and apply only unambiguous HARQ identities; it must not publish CSI whose presence/value cannot be established. This is a receiver-design proposal, not a 3GPP-mandated algorithm or a qualified policy. Prove its false-ACK/missed-feedback behavior before choosing it. Do not silently convert every ambiguous case into a successful combined report.
5. **CSI:** installed calendar alone is insufficient. Establish which omissions are knowable from configured gaps/activation and actual gNB RS scheduling; handle residual uncertainty without using UE measurement availability as an oracle. PUSCH needs its own rate-matching/CSI-absence analysis, not reuse of the PUCCH small-block counterexample as a PUSCH proof.
6. **SR:** reuse the existing MAC `SchedulingRequestState` with explicit arrivals, grants, prohibit expiry and retransmission events; connect it to the existing PUCCH planner. The gNB calendar defines possible SR identities, not their positive values. `UCIReportSerializer.sr` currently concatenates input values; do not call it general multiple-SR encoding. For the relevant Format-2/3/4 overlap procedure, encode the ordered SR identity with `ceil(log2(K+1))` bits, not K independent flags; preserve single-SR behavior and transport-specific collision rules.
7. **One commit path:** replace strict-runtime TX-derived assignment and producer-row HARQ application only after independent combined reception passes. Preserve component APIs and negative guards until their production callers have a correct replacement. Exactly one physical observation may update each HARQ/CSI/SR owner; stale epochs and duplicate completions remain rejected.

The small-block result is consistent with the shared basis-sequence construction in [TS 38.212 V18.8.0, 5.3.3.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf). Multiplexing permission, SR coding and collision procedures are reviewed against [TS 38.213 V18.8.0, 9.2.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf). Neither source defines the simulator's detector threshold as a universal 3GPP acceptance value.

### Minimal patch sequence and closure tests

| Order | Existing files to change | Delete/replace | Required proof before moving on |
| --- | --- | --- | --- |
| A | `PUCCHConfigBuilder`, `PUCCHRRCContext`, `PUCCHResourcePlan`, existing YAML/schema; `CoupledTruthRuntime` prepare boundary | Missing permission and permanently empty SR input; keep separate TX/RX authority | Permission allowed/absent/false; invalid policy; actual SR positive/negative and lifecycle; legal collision cases with no oracle inputs |
| B | `buildScheduledHARQTransportReception`, `buildConfiguredPUCCHReceiveContext`, `buildSharedPUSCHCSIReceiveObligation`, existing runtime prepare/completion, `runPUCCHWaveformTrial` | HARQ-only exclusion and strict-runtime fallback to transmitter assignment, after replacement is ready | Actual waveform first/middle/last/all-missed DCI, DAI wrap, CSI absent/present, SR overlap, PUCCH/PUSCH selection, no producer, duplicate/stale/late events; poison TX metadata while fixed RX inputs produce identical receiver decisions |
| C | `exportLLSLiveDerivedTables`, `tools/lls_csv_semantics.py`, existing MCS/CQI reference writers | Divergent FER populations/frame identities and missing resolved identity columns | Warm-up, missing SINR, decode failure/crash, repeated SFN across sweep/drop; identical MATLAB/Python populations; all reference rows bind real resolved config |
| D | Only proved contradictory test/scenario fixtures listed above | Missing clock, missing resource declarations, contradictory K1/K2/profile/alias overrides | Original tests pass with their numerical/ownership assertions intact; explicit invalid-input tests still fail; do not make all historical failures one blanket fixture rewrite |
| E | Existing measurement producers and exports only where paired evidence identifies a defect | Mislabelled reference planes/populations; no wholesale new measurement framework | Recompute each family below from retained actual observations; any unavailable measurement stays unavailable with reason |
| F | Frozen source; no edits during execution | Retire redundant future queues only with authority; never delete failed evidence | Final-source focused guards, unfiltered `testAll`, required NR/config/scheduler/strict/export/E2E tests, then inspect complete 5 MHz TDD 12 dB run and final CSV/PNG |

### All-measurement acceptance ledger (not yet closed)

| Family | Independent check / required scope |
| --- | --- |
| Power, noise, loss | Trace each applied scale once from TX to RX; distinguish watts/mW/normalized IQ, active-symbol/slot means, per-port/total power, sample/grid/equalized noise. Use actual channel/noise contributions; no gain fitted to desired output. |
| RSRP/RSSI/RSRQ | Declare SS/CSI/SRS resource and receive plane; use linear powers and matched bandwidth/time windows before dB conversion. Verify the RSRQ numerator and RSSI denominator refer to the same measurement scope. Do not relabel normalized power as dBm. |
| SINR | Separate configured 12 dB reference operating point, realized input SINR, pilot diagnostics and post-equalization SINR. They need not equal one another. Retain desired/interference/noise reference contributions for independent comparison, outside receiver decision inputs. |
| EVM | Full-observation reference energy, actual receiver symbols, no payload gain/phase fit; label decision-directed and known-reference metrics separately. Preview samples are not the full measurement population. |
| Channel estimates | Per-resource/branch/layer estimates; independent applied-channel references for NMSE. A pilot self-fit is not a channel-truth comparison. |
| BER/BLER/FER | Exact reference/decoded bit populations, CRC/TB identity, crash/DTX distinctions and confidence/trial counts; no removal of failed rows solely because SINR is absent. |
| Throughput/goodput | Successfully delivered unique TB bits counted once; label scheduled-airtime, measurement-window and end-to-end denominators; retransmissions are not new delivered payload. |
| CSI/SRS feedback | Actual resource, epoch, source, completion/publication/consumption timestamps and freshness; no report fabricated from a periodic calendar. |
| CSV/PNG | Source revision/config hash, resource/UE/sweep scope, units, row identities and numerical reconciliation; plots must derive from the same validated population. |

Measurement definitions must be pinned per specification rather than assuming every NR document has version 18.8.0. The inspected measurement reference is [TS 38.215 V18.2.0, 5.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf); confirming the repository's exact measurement-version contract remains part of the ledger.

### Timebox and stop conditions

- Use the user's 2-3 hours for **diagnosis and design**, starting approximately 08:01 IST: target design checkpoint 10:01, outer review checkpoint 11:01 on 16 September. These are checkpoints, not claims that all code and long-running physical tests will pass by then.
- Before implementation starts, every proposed changed behavior needs a reproducer or a documented missing interface, an authority decision, a bounded file list, and a closure test. Mark unresolved cases; do not describe this audit as exhaustive proof of the entire simulator.
- Long physical qualification is separate from coding time. Preserve measured runtimes, required episode counts and original statistical gates; report a failed or incomplete campaign honestly.
- As of the checkpoint, the old `d05c1441` full suite still runs and the `5d20e64d` scenario is queued. Neither that queue nor the isolated permission patch includes the combined-feedback design above. FDD and 400 MHz stay deferred.

## 08:35 IST checkpoint: missing-DCI and absent-CSI proofs

All diagnostics in this section finished with process exit 0. They are bounded component counterexamples, not a passing integrated scenario. No production source was changed for these diagnostics.

### PUCCH: missing-last-DCI can change CSI meaning without changing samples

`last_dci_ambiguity_20260916.log` re-encodes the retained slot-39 payload pattern, `11110111100`, under two typed interpretations on the same fixed Format-2 component resource:

| Interpretation | Information bits | Decoded CSI | Physical result |
| --- | --- | --- | --- |
| Four HARQ bits + seven CSI bits | `11110111100` | RI=1, CQI=12 | Identical encoded bits and time-domain waveform |
| Three HARQ bits + seven CSI bits | `1111011110` | RI=2, CQI=14 | Identical encoded bits and time-domain waveform |

This proves that the earlier absent-zero-CSI counterexample is not the only problem. Losing a final assignment can shift the HARQ/CSI boundary and produce another valid CSI value with indistinguishable samples. It does not prove that both hypotheses are legal for every production RRC/DCI resource configuration; the receiver must first constrain hypotheses with independently known scheduling and resource information. Neither a decoder success flag nor higher SNR resolves exact waveform equality.

The same diagnostic supplies seven assignment events with DAI `1,2,3,4,1,2,3` and retains only the final three received events. The existing UE Type-2 builder returns three bits for assignments 5,6,7; it cannot reconstruct the hidden first four assignments from those two-bit counters. Keep that honest limitation. Do not add scheduler knowledge to the UE builder to make the lost cycle reappear.

### PUSCH: conditional CSI confidence is not evidence that CSI was sent

`pusch_csi_absence_20260916.log` uses actual OFDM TX/RX, four HARQ bits, an installed five-bit CSI Part 1 and rank-dependent Part 2, and time-domain noise variance `1e-7`. It exercises the same received capture under each declared schema:

| CSI transmitted | RX expects CSI | TB CRC | HARQ | CSI Part 1 result |
| --- | --- | --- | --- | --- |
| No | No | Pass | Correct | Absent |
| No | Yes | Fail | Correct | `10011`, marked usable; conditional posterior=1 |
| Yes | No | Fail | Correct | Absent |
| Yes | Yes | Pass | Correct | `00000`, marked usable; conditional posterior=1 |

The evidence already labels this posterior `conditional_on_transmission` and `SignalPresenceQualified=false`. The defect would be treating that conditional acceptance as proof of CSI presence in the runtime, not the arithmetic of the conditional posterior itself. Do not raise its threshold above 0.99 and claim to solve this counterexample: the false interpretation already scores 1.

`pusch_absence_maps_20260916.log` independently probes public demultiplexer index maps using configuration labels, not received samples. For budgets `(CSI1,CSI2)=(0,0),(5,1),(5,2)`, all three use the same 192 HARQ source indices; UL-SCH source-index counts differ: 1536,1444,1430. This explains why HARQ survived while the wrong CSI schema broke TB decoding in this fixture. It is a configuration-map proof, explicitly not additional physical execution evidence or a universal resource-invariance claim.

Required changes:

- Extend the existing `inspectUCIResourceInvariance`/`receiveConfiguredUCI` boundary to represent independently legal absent/present CSI budgets, not only Part-2 lengths under assumed-present CSI. Reuse actual demapper LLRs and independent resource maps.
- Where valid UL-SCH is present, evaluate the candidate rate-matching layouts and retain CRC/decoding evidence per candidate. A unique consistent candidate can be useful evidence; one four-case diagnostic does not qualify a universal selection rule. If candidates remain unresolved, preserve field-specific uncertainty.
- Never gate otherwise independently established HARQ on UL-SCH CRC merely because the CSI hypothesis is uncertain. Likewise, separately protected CSI must not be universally tied to data CRC. UCI-only PUSCH and both-candidates-pass/fail require explicit tests.

### PUSCH publication is still producer-gated

Exact source: `CoupledTruthRuntime.m::consumeDecodedPUSCHCSI`, lines 14975-15103 at the audited candidate. It returns immediately when `grant.UCIOnPUSCHCSIReportIdentity` is absent, requires exactly one unprocessed `PendingCSITable` row with `pusch_bound`, and compares the stored expected bits with `harqOut.ExpectedCSIPart1Bits/ExpectedCSIPart2Bits` before publication.

Those checks protect a TX reservation but do not define an independent receiver publication path. A decoded report without a UE producer is currently excluded before receiver evidence can be handled. Replace the publication prerequisite with the installed receiver obligation, actual observation identity/clock, decoded fields and receiver validity. Keep producer reservation reconciliation as a separate post-reception bookkeeping/scoring operation. Do not simply delete binding checks and permit unbound publication. Publish and consume only usable receiver decisions; preserve false detections and unavailable/ambiguous decisions in receiver audit even when no TX row exists.

### Missed UL DCI: transport arbitration and combining remain unsupported

`buildScheduledHARQTransportReception` selects PUSCH from the transmitted UL schedule; `buildScheduledPUCCHHARQReception` refuses that selection. But transmitting an UL DCI is not proof that the UE received it. `completeSharedPUSCHAfterRejectedControl` explicitly rejects:

- CSI (`RejectedULUCITransportOwnershipRequired`);
- an existing UE PUCCH producer (`RejectedULExistingPUCCHProducerOwnershipRequired`);
- a receive-only retransmission (`RejectedULReceiverHARQCombiningRequired`).

These are documented missing implementations, not spurious assertions to remove. Replace exclusive scheduled-transport suppression with independently scheduled candidate receive windows and a common per-obligation disposition. Actual received samples must determine receiver evidence. Keep UE TX disposition separate; missing UL DCI may leave a real PUCCH transmission. On retransmission, use the gNB-owned soft buffer/NDI/RV identity and distinguish current-window reception from combined decoding. Do not invent a new UE TB, score nonexistent transmitted bits, or commit feedback twice.

### Actual 12 dB startup narrows one CSI-absence case

The failed `d05c1441` trace has CSI measurements at slots 32,37,47,52,57. Its report occasion 34 has reference slot 29, preceding the first actual CSI-RS execution at 32; it carried three HARQ bits without CSI. Later PUCCH occasions 39,44,49,54 carried CSI. This distinguishes a known startup eligibility condition from an arbitrary missing report.

The receiver must derive that exclusion from the gNB's actual reference-signal transmission/configuration history, not from the UE's measurement results or pending-report table. Retain compact executed-RS identity/epoch/time metadata at the existing physical commit boundary if no suitable gNB-owned ledger is already exposed. A configured periodic calendar alone is insufficient. Slot numbers here use the runtime/export convention; new tests must make any zero-based conversion explicit.

### Refined implementation contract and decisive tests

1. Build only independently legal receiver interpretations from actual transmitted grants, installed RRC, reference-resource eligibility and possible last-received DCI/transport choices. Preserve their assignment identities, not just a possible bit count. Do not assume the gNB knows which DCI the UE decoded.
2. Reuse each physical receive capture. Group observationally identical short-codeword interpretations without manufacturing confidence by counting duplicate interpretations. Per-length conditional posteriors cannot rank absent/present schemas. The exact likelihood/presence policy still needs qualification; this audit does not prescribe an untested universal detector.
3. `mapScheduledHARQFeedback` currently has a single validity flag and requires the full vector length. Add receiver-owned per-assignment validity only if the ambiguity resolver can prove consistent identity/outcome across retained interpretations. Keep legacy exact-vector behavior for its legitimate callers. Do not pad absent bits with ACK/NACK and call them decoded.
4. Reuse `commitScheduledHARQFeedbackRuntime` for one bound, clock-valid commit per obligation; join CSI/SR receiver results at the same ownership boundary. Producer metadata must not change decoding, acceptance or scheduler values.
5. Required counterexample regressions: both PUCCH waveforms above; all-zero CSI extension; whole DAI-cycle loss; all four PUSCH absence cases; unchanged versus changed resource maps; missing UL DCI with actual PUCCH; receive-only retransmission; CSI decoded without a producer; duplicate/stale/late completion; poisoned TX payload/length/identity with fixed receiver inputs.

These are bounded extensions to existing receiver/planning/commit interfaces, not a new receiver framework. Integration remains paused until the receiver ambiguity policy and ownership changes have their explicit acceptance tests. The old suite is still running on `d05c1441`; the `5d20e64d` scenario is still queued and cannot validate these proposed changes.

Additional SHA-256 receipts:

- PUSCH absence log: `8F6263D9923EA9B79DF7D6F352271F15DDA710922F6AB03B1F75E0C98B451A13`.
- PUSCH absence MAT: `37D6FE2B52C561D66C37BE2F4238406420B508EFEF86EE48E3219020BAB997A5`.
- Last-DCI ambiguity log: `C63EB2B5C2CDF8B555720D82F9A77092E7F034612B543DC6CFA9CA9E5D507681`.
- Last-DCI ambiguity MAT: `C60686F08C7D9BB7C068EC142C50AF378E0504DE8EEA5FEB4D70B9090727BDBF`.

## SR/resource-sizing dependency: direct scenario evidence

`diagnose_tdd_sr_wire_budget_20260916.m` completed with exit 0. It loads the candidate's actual TDD configuration, calls existing `buildConfiguredSRCalendar` and `resolveLongPUCCHSROverlap`, and joins the five retained `d05c1441` PUCCH rows. This is a configuration/execution-trace diagnostic, not another RF run. No SR polarity was guessed.

The installed SR resource has period 5, zero-based offset 3, and symbols 12-13. The retained Format-2 resource 10 also occupies symbols 12-13. Each of the five retained occasions therefore has one same-priority overlapping SR opportunity. The existing overlap helper already returns one SR information bit, but its inspected callers are tests, not normal runtime preparation.

| Runtime slot | Recorded HARQ/CSI information bits | Required SR field width | Corrected total for the same HARQ/CSI content | Coding consequence |
| --- | --- | --- | --- | --- |
| 34 | 3 | 1 | 4 | Short block, no CRC |
| 39 | 11 | 1 | 12 | Polar + CRC6 |
| 44 | 8 | 1 | 9 | Short block, no CRC |
| 49 | 11 | 1 | 12 | Polar + CRC6 |
| 54 | 11 | 1 | 12 | Polar + CRC6 |

The SR field represents negative as well as positive SR under this overlap procedure. Omitting it because no positive SR has been prepared is not equivalent to encoding negative SR. [TS 38.213 V18.8.0, 9.2.5.1-2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf) defines the overlap-dependent field width and order. `UCIEncodingPlan` exposes the 11/12-bit coding boundary; the existing combined component test already exercises a 12-bit HARQ/SR/CSI waveform, but the normal builder supplies no SR input.

**Consequence for the earlier ambiguity proof:** retain the no-SR waveform counterexample as a valid component case, but do not call that the final corrected waveform for this scenario's SR-overlapping occasions. Correct SR integration changes its coding problem. Missing-last-DCI can still change length/resource hypotheses; a CRC reduces undetected error probability, not to zero. The short-block and absent-CSI cases remain necessary tests in appropriate configured occasions.

### Missing max-code-rate/minimum-resource contract

The inspected `pucch_resources` schema, `PUCCHRRCContext`, `PUCCHResourcePlan`, `PUCCHResourceSetResolver`, `PUCCHFormatValidator`, and `PUCCHTransmitter` have no configured `maxCodeRate` path. Set selection uses a payload threshold; resource validation checks format/payload/symbol tuples; the transmitter uses the entire configured `NumPRBs`. These do not implement the rate-constrained minimum-PRB and CSI multiplex/drop procedure of TS 38.213 9.2.5.1-2.

The retained resource uses two PRBs, two symbols and 64 coded bits. After adding the required SR field, the 12-bit payload carries six CRC bits: its rate over that unchanged resource is `(12+6)/64 = 0.28125`. A hypothetical configured maximum rate 0.25 would not fit; blindly adopting 0.25 as a default would create a new inconsistency. This calculation is a resource-capacity check, not a measured BER/SINR result. The scenario must explicitly author its allowed rate and resource capacity; the implementation must enforce it and apply the specified report dropping procedure when appropriate. Do not silently increase power, add PRBs, discard CSI, or select a rate to conceal a failing result.

Bounded changes, before receiver-policy freeze:

1. Extend the existing YAML catalog/RRC format configuration with validated maximum-code-rate authority, and author it in the TDD scenario. Preserve the distinction between the configured maximum resource and the actual selected allocation. Review existing fixture configurations explicitly rather than giving connected mode an implicit rate.
2. In `PUCCHConfigBuilder` and runtime preparation, reuse the installed SR calendar/overlap helper. Supply a typed TX SR indication from UE MAC state; build RX field width/identity independently from configured opportunities. In `UCIReportSerializer`, encode one ordered SR identity for multiple overlapping opportunities, not K independent booleans. Existing single-SR bits remain the K=1 case.
3. In `PUCCHResourcePlan`, apply permission/priority/CSI-dropping and rate-constrained resource selection with the correct CRC count. Bind the selected PRBs to TX, RX candidates, reservation ownership and the power bandwidth term. Preserve configuration resource identity separately from actual allocation identity.
4. Only then freeze combined receiver hypotheses and update the normal prepare/receive/commit routing. Reuse existing 12-bit combined component execution as a baseline, then test 11/12 and 19/20 boundaries, minimum-PRB boundaries, negative/positive SR, unsupported capacity, and absent/false multiplex permission.

RRC placement correction: [TS 38.331 V18.8.0, PUCCH-Config / PUCCH-FormatConfig](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.08.00_60/ts_138331v180800p.pdf), pages 957-964, places `maxCodeRate` and `simultaneousHARQ-ACK-CSI` in the per-format configuration referenced by format2/3/4. The isolated pre-pause patch's global boolean is therefore only an interim guard, not the final configuration model. Replace it with format-owned authority before integration; do not proliferate a second global rate/permission lookup. The allowed maximum-rate enum values are 0.08,0.15,0.25,0.35,0.45,0.60,0.80. A format-2 permission must not accidentally authorize a format-3 or format-4 combined report. Test mixed-format permission conflicts and missing configured rate explicitly.

For the present non-interlaced Format-2 resource, the retained 64-bit capacity must not be divided by its `occ_length` field. MathWorks documents Format-2 `SpreadingFactor`/`OCCI` for single-interlace NR-U configurations; these properties have existed since R2023b, not only R2026a. [nrPUCCH2Config documentation](https://www.mathworks.com/help/5g/ref/nrpucch2config.html) This corrects a possible compatibility/sizing assumption, not a demonstrated R2023b execution pass. Preserve the actual `nrPUCCHIndices` capacity and explicit interlacing applicability when implementing sizing.

### SR state ownership is more than adding a zero bit

Two existing classes have distinct roles: `+sixgr/+l2/+mac/SchedulingRequestState` is a mutable event machine; `+sixgr/+phy/+pucch/SchedulingRequestState` is a slot/polarity snapshot. Reuse those roles rather than adding a third state machine. The MAC class does not own a sample/slot timer, its maximum-transmission property is not enforced internally, and its `UL_GRANT` event clears pending state. The coordinator must not send that event on every transmitted UL DCI or every partial grant. For BSR-triggered SR, cancellation is tied to the specified BSR transmission or sufficient granted capacity, not simply any grant. [TS 38.321 V18.8.0, 5.4.4](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.08.00_60/ts_138321v180800p.pdf)

Source inspection also finds `CoupledTruthRuntime.buildSchedulerUEState` reads `state.ULQueueBits` directly; normal truth-runtime searches find no construction of the MAC SR/BSR state machines. This establishes that current queue scheduling is not proof of a received-SR-driven MAC loop. Separate UE queue state from gNB received requests/buffer reports for that claimed capability. An explicitly declared PHY traffic/scheduler abstraction can be useful, but must not be labelled as a completed causal SR/BSR implementation. Tests must include arrival, insufficient/sufficient received grant, missed UL DCI, actual SR transmission, prohibit expiry, maximum transmissions, decoded SR at gNB, and release/epoch reset.

No production implementation has been added in this checkpoint. These findings reorder the existing repair plan: fix the complete TX/RX wire-budget and resource contract before spending effort on a decoder policy for the incomplete payload layout.

Evidence hashes:

- SR wire-budget log: `F2423F6A15E6671A62A1AE3F6AC9C2BF7EC6F789326AC50BA882335B429B6110`.
- SR wire-budget MAT: `443D449D975093E3AED7455DE888B148DDBBE5E9EE921F4F0AA02CDF62046B96`.

## Resource/coding and detector-input checkpoint (16 September, approximately 09:00 IST)

### Public resource/encoder cross-check completed

`diagnose_pucch_capacity_boundary_20260916.m` completed with exit 0. Public `nrPUCCHIndices` returns 32 and 64 coded bits for one and two PRBs respectively on the declared two-symbol, non-interlaced Format-2 resource. The minimum PRBs below include the CRC from `UCIEncodingPlan`; `cannot fit` means the declared maximum of two PRBs is insufficient, not permission to silently enlarge it.

| Information bits | CRC bits | Rate 0.25 | Rate 0.35 | Rate 0.60 | Rate 0.80 |
| --- | --- | --- | --- | --- | --- |
| 4 | 0 | 1 | 1 | 1 | 1 |
| 9 | 0 | 2 | 1 | 1 | 1 |
| 11 | 0 | 2 | 1 | 1 | 1 |
| 12 | 6 | cannot fit | 2 | 1 | 1 |
| 19 | 6 | cannot fit | cannot fit | 2 | 1 |
| 20 | 11 | cannot fit | cannot fit | 2 | 2 |

The script also inserts a declared negative SR into the earlier four-HARQ/seven-CSI coding example and compares its 12-bit polar codeword with all 2,048 possible 11-bit short-block words. Minimum Hamming distances are 6 at E=32 and 20 at E=64. The exact equality in the earlier no-SR example therefore does not survive this correction. This is a codeword comparison, not a universal proof of unique receiver interpretation or noisy reception. E=32 is included as a mathematical encoder comparison, not a declaration that it meets the scenario's eventual configured rate.

No scenario rate has been selected or changed. Author the rate from the intended declared payload/resource budget; do not choose it by searching for an observed pass. The selected minimum allocation must be shared by reservation, transmission, receiver hypotheses and the bandwidth-dependent power term. Recompute capacity and CRC after a permitted CSI report subset is selected.

Receipts:

- Capacity/coding log: `72C13008D72C6A175B4183F16FF07EC1B5408671E46406E2D293A60E893C3275`.
- Capacity/coding MAT: `3D8283E05A241AD4B53C6BA8875FA00D2C7F65D83830C707AB7E5043E52D6FD1`.

### Detector malformed-input bug is separate from statistical qualification

`diagnose_pucch_detector_invalid_input_20260916.m` completed with exit 0. Eight helper calls, across Formats 0 and 2, return `Detected=true, DTX=false` for a nonempty decoded word with a NaN metric, infinite metric, vector metric, or NaN threshold.

The exact cause is `+sixgr/+phy/+pucch/PUCCHDetector.m::decide`: invalid metrics fall through to `dtx=isempty(decoded)`. A NaN threshold makes the finite-metric comparison false. Decoded bits are not independent evidence that a physical signal was present. `PUCCHReceiver.receive` accepts a numeric scalar threshold without checking finite/range constraints; the normal `runPUCCHWaveformTrial` threshold resolver already performs stronger validation.

Required replacement: validate the detector's threshold and format contract, and reject invalid metrics or explicitly mark the observation unusable with a reason. Remove the nonempty-decoded-word presence fallback. Add direct malformed-input tests and receiver-entry tests, retaining valid finite-metric behavior. Do not modify the original noise-only false-ACK limit.

This diagnostic contains **zero physical episodes** and does **not** identify the cause of the retained 12/1,024 failure; those observations used valid finite metrics. Fixing this defensive bug is necessary but cannot qualify the detector.

- Invalid-input log: `A22802B329C87499751E4CEBB59E8E0410DF4F14739FF55A905FC7DC3C17EDA1`.

### Reuse the existing physical capture and common commit

Source review confirms that `CoupledWaveformStream.queuePUCCHPreparation` already registers the actual TX/pre-RF/post-RF observation. `bindUnselectedPUCCHObservation` changes its disposition without deleting the capture. The completion path records these planes in `SharedUnselectedPUCCHObservations`, explicitly with no decoder or feedback commit. This is the existing capture to reuse for a legal alternate PUCCH interpretation after missed UL DCI; no second channel/noise execution is needed.

`commitScheduledHARQFeedbackRuntime` already checks the completed physical buffer and clock, validates rows before application and rejects repeated obligation digests across transports. Keep this common commit. The proposed integration replaces receiver interpretation and producer-dependent publication prerequisites, not this ownership/clock machinery. Do not remove unsupported-transfer guards until the new transport disposition is tested.

### Short-format SR: actual modulation mismatch reproduced

`diagnose_short_pucch_sr_20260916.m`, second run, completed with exit 0. It constructs existing typed reports/assignments, executes `PUCCHTransmitter`, and compares the unscaled mapped symbols with public format-specific `nrPUCCH` references. Each Format-0 reference also passes a public decode round trip using separate HARQ and SR lengths. No fading/noise execution is involved.

| Format | HARQ | Positive SR | Current implementation versus reference |
| --- | --- | --- | --- |
| 0 | absent | 1 | Relative symbol error sqrt(2) |
| 0 | 0 | 1 | Exact match in this case |
| 0 | 1 | 1 | Relative symbol error sqrt(2) |
| 0 | [0,1] | 1 | Current path rejects `InvalidFormatPayload`; public reference encodes/decodes successfully |
| 1 | absent | 1 | Relative symbol error 2 (opposite reference symbols) |

Root cause and bounded replacement:

- `PUCCHTransmitter.transmit` flattens HARQ/SR and supplies the resulting bit vector to `nrPUCCH` for both short formats. For Format 0, use the separate HARQ/SR API and the applicable configured overlap/resource procedure. For Format-1 positive SR without HARQ, the reference input is zero, not the SR boolean one. Do not apply long-format SR concatenation indiscriminately to short formats. [MathWorks nrPUCCH](https://www.mathworks.com/help/5g/ref/nrpucch.html)
- `PUCCHFormatValidator`/planning validates a flattened information count. Replace that part with typed, format-specific HARQ/SR legality; do not simply increase the short-format bit limit from two to three, which would also admit invalid three-HARQ-bit payloads.
- `PUCCHReceiver.receive` currently supplies a scalar total length to `nrPUCCHDecode`; `localCellBits` keeps only the first output cell. Format 0 needs independent HARQ/SR lengths and both decoded fields. Derive lengths from receiver-owned configuration/obligations, not the transmitted report. Preserve SR absence/negative/DTX distinctions. [MathWorks nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html)
- Required tests: every zero/one/two-HARQ combination with positive/negative SR, SR-only/no-transmission, invalid three-HARQ payload, Format-1 SR resource collision handling, and TX/RX oracle isolation. Matching one bit pattern is not enough: the HARQ=0 case above demonstrates why.

The first diagnostic incorrectly asserted that every one-HARQ/positive-SR flattened mapping must differ. It stopped at the matching HARQ=0 case; this is a diagnostic assumption error, not a production test failure. The second run records both matching and mismatching cases. The original log is preserved. Neither diagnostic changes a production assertion or qualifies short-format detection. These short-format defects must be addressed for claimed SR support, but the five retained baseline feedback rows use Format 2; do not attribute that run's receive-tail abort to these short-format defects.

- Completed diagnostic log: `77455758B385ED8616DF941E5BC095BE03B233A694422AF483F4D625D70F85FC`.
- Preserved first diagnostic log: `AFB92E521838DADE93B24646D02852F5C02F959178CF279DD150376AA06CB1F6`.

### Implementation entry gate and scope

The first implementation unit remains the **complete UCI wire/resource contract**, not a speculative receiver wrapper: per-format permission/rate configuration, correctly typed SR, format-specific coding, capacity/CRC/minimum allocation, and consistent reservation/power/resource binding. Replace the interim global-permission patch within that unit. Prove this unit with reference encoding and boundary tests before changing normal receiver routing.

The next unit is independent combined reception/publication using the existing capture and commit machinery, with explicit unresolved-field handling. Receiver hypothesis acceptance still requires measured false-detection/missed-detection qualification; this document does not turn a proposed ambiguity policy into a proven solution.

Production integration remains paused at this checkpoint. The analysis target remains 10:01 IST, with 11:01 IST as the outer review checkpoint, **not a guaranteed implementation or qualification finish**. Current findings are sufficient to reject blind integration, but do not establish every historical regression or every integrated measurement as diagnosed. The old `d05c1441` suite is still running and `5d20e64d` is still queued; neither contains these proposed repairs.

## Receiver-boundary review: preserve working mechanisms and close coverage gaps

### CSI presence matrix: preserve independently mapped HARQ

`diagnose_pusch_presence_map_matrix_20260916.m` completed with exit 0. It reuses the retained PUSCH allocation and independently probes public demultiplexer indices for 1,2,3,4,11,12 HARQ bits, both with a 528-bit TB and without UL-SCH, under CSI budgets `(0,0)`, `(5,1)`, `(5,2)`.

- All twelve configurations preserve the same HARQ source indices across those three CSI budgets.
- All six data-bearing configurations change UL-SCH source indices with the CSI budget. For four HARQ bits the respective data lengths are 1536,1444,1430.
- UCI-only configurations have no UL-SCH bits or TB CRC to disambiguate CSI presence. An empty UL-SCH map being invariant is not successful data decoding.

This broadens the earlier one-case configuration proof; it still does not establish invariance for every allocation, beta offset, modulation or codeword. It uses integer index labels only, not synthetic samples passed off as RF evidence.

`PUSCHUCIDemultiplexer.receive` already invokes `receiveInvariantUCI` when received CSI Part-1 interpretation fails. `inspectUCIResourceInvariance` currently enumerates Part-2 lengths only under an assumed-present Part 1. Extend that existing candidate domain to independently legal CSI presence/absence; preserve configured-grant UCI ownership and puncturing erasures. Do not discard all HARQ merely because the CSI schema or data CRC is unresolved, and do not assume its resource map is invariant without checking.

`PUCCHReceiver.ReceiverUsable` currently means detected, not CRC-qualified. `testPUCCHReceiverCRC` explicitly verifies a detected wrong-RNTI waveform with failed CRC; `runPUCCHWaveformTrial.Ok` separately checks CRC. Preserve these distinct meanings or migrate them explicitly across all consumers. Do not make every CRC failure DTX to manufacture detector performance, and do not publish ACK/CSI from the detection flag alone.

- Presence-matrix log: `F3AA415A3CACB1F70D3A70FFA573E762324C735B4988419653B5E08C0DE13F3F`.

### Exact place for gNB-owned reference-signal eligibility

Source tracing narrows the earlier proposed reference-execution metadata:

- `PreparedDataTransmission.Tx.CSIRSRuntimeEvent` retains the mapped CSI-RS resources, including `ResourceEvents.ResourceID`, `SymbolSet`, mapped indices and cell-common ownership. `PDSCH_Tx` distinguishes emitted CSI-RS from a reserved-only common plane. These fields describe preparation until their samples execute.
- `CoupledWaveformStream.queueData` registers the actual contribution and TX observation. Its `DataTX` event fires one sample after the **first** active contribution sample; it does not prove that later CSI-RS symbols in that slot have executed.
- `commitSharedDataTransmission` retains the grant, TB bits, identity and start evidence but not per-resource CSI-RS execution. `ControlTrials.CSIRS` is populated by UE receiver completion and must not become the gNB's oracle for measurement availability.

Use the existing prepared resource metadata and physical event/observation clock to retain a compact transmitted-RS eligibility record only after the relevant resource samples have actually been consumed. Scope it by cell, carrier/BWP, resource, epoch and source slot; deduplicate a cell-common emission across receiving UEs. Do not mark a reserved-only resource transmitted, count a future symbol at the data-start event, or copy UE measurement usability into this record. No second waveform generation or channel execution is needed.

Decisive tests: prepared-but-not-executed RS; data start before the CSI symbol; completion at the exact symbol endpoint; reserved-only peer component; repeated common-resource observers; different epoch/BWP; configured occasion without an actual emission; actual emission with failed/unavailable UE measurement. An actual gNB emission permits a CSI hypothesis but does not establish that the UE measured or reported it.

### Existing SR reference test is absent from the normal suite

The repository already contains `tests/testPUCCHFormat0SRSemantics.m` and its YAML vectors for all zero/one/two-HARQ combinations with both SR values. It generates independent public reference symbols and feeds them to the receiver. The inspected candidate's `testAll.m` does not register it; searches of test/script callers find only its definition, and the queued 33-guard batch also omits it.

Reuse this test instead of adding a duplicate Format-0 matrix. Register it in the final suite when implementing the SR repair, keeping its independent reference and assertions. Extend coverage separately for the demonstrated Format-1 issue. `testPUCCHPhase05` has a local test named `testSchedulingRequestMultiplexing` that only asserts the fixture's format is 1; that assertion is not waveform SR multiplexing coverage. Strengthen the actual semantic test boundary instead of counting a suggestive test name as proof.

The existing test was then run **unchanged** on the isolated candidate and reached terminal exit 1 (`sixgr:test:PUCCHFormat0SRSemanticsMismatch`). Its saved 14-row CSV shows:

- TX matches only 2/14 cases; RX matches only 2/13 signal-present reference cases.
- The two matching cases have one HARQ bit equal to zero, with either SR polarity.
- No-HARQ negative SR has no public reference transmission, but the current transmitter produces a waveform. The repair must represent a valid no-transmission disposition, not create a zero-bit successful reception or add a noise-only waveform to TX.
- All eight two-HARQ/SR combinations are rejected by the current flattened payload validation; reference reception also fails under the scalar three-bit receiver length.

Files: `logs/existing_short_sr_guard_20260916.log` and `logs/existing_short_sr_guard_20260916/format0_sr_reference.csv` / `.mat` in the isolated diagnosis checkout. This is a completed diagnosis, **not a fixed SR implementation**. The prior isolated multiplexing-permission patch does not change short-format serialization, modulation or decoding; it cannot explain away these failures.

- Existing SR test log SHA-256: `9E6C37A394F84E4FCC491B0C73354BCCDDB1A52127816AFA1D88DE04695549CB`.
- Existing SR test CSV SHA-256: `216135D01088F31FBE281D4491B2E0F9E997255339379A8F9E962EBEAC43FC6F`.

## SRS-to-PUSCH prediction: a mathematical contract defect, not missing plot polish

Source inspection and a controlled receiver-input diagnostic identify another measurement/scheduling repair that must precede all-measurement closure. The relevant source is unchanged between the failed `d05c1441` run and candidate `5d20e64d`.

`+sixgr/+phy/+ul/estimateSRSRITPMI.m` first evaluates candidate precoders using the MMSE covariance `(I + Heff' * Heff / nVar)^-1`. It then computes `calibrationOffset_dB = anchor_dB - widebandMeanSINR_dB` and adds that offset to every selected layer. The final mean is therefore forced to the anchor, irrespective of the combining/precoding gain already represented by the selected channel. The anchor is not a declared SRS-to-data energy conversion.

`measureULLinkState.m` explicitly labels its SRS pilot-reconstruction SINR `diagnostic_reference_signal_quality_not_for_scheduling`. Nevertheless, `runSRSChannelEstimation.m::localResolvePUSCHSchedulingSINRAnchor` selects that same quantity for the reference-SNR operating mode, and the anchored estimator publishes `power_plane_calibrated_predicted_pusch_data_channel_scheduling_input`, status `PASS`. `CoupledTruthRuntime` accepts that anchored prediction. Labelling a quantity as predicted does not establish the missing mathematical power-plane conversion.

### Independent combining check

`diagnose_srs_anchor_combining_20260916.m` completed with exit 0. It declares one transmit port, equal unit pilot/data energy, unit channel coefficients and independent noise variance 0.1 per receive branch. This is a deterministic algebraic receiver-input fixture, not fading-channel execution. It probes public `nrEqualizeMMSE` with a desired-symbol vector and individual noise-basis vectors and independently evaluates the resulting signal/noise ratio. The public equalizer and the repository's unanchored MMSE prediction agree:

| Receive branches | Per-branch pilot SNR | Independent post-combining SNR | Anchored prediction | Gain removed |
| --- | --- | --- | --- | --- |
| 1 | 10 dB | 10 dB | 10 dB | 0 dB |
| 2 | 10 dB | 13.0103 dB | 10 dB | 3.0103 dB |
| 4 | 10 dB | 16.0206 dB | 10 dB | 6.0206 dB |

For this declared single-layer case the independent result is `sum(abs(h).^2)/nVar`. No configured target SINR is used to fit the result. The API uses channel and received noise variance as its inputs; see [MathWorks nrEqualizeMMSE](https://www.mathworks.com/help/5g/ref/nrequalizemmse.html).

The six actual SRS rows at slots 30,35,40,45,50,55 use this anchoring path. Their prediction means equal their pilot measurements (approximately 1.21-1.24 dB), with offsets from -2.2561 to -2.2105 dB. This establishes that the path is relevant to the retained run; it does not assert that the exact counterexample's 3.0103 dB error applies to that fading/MIMO scenario.

### Required repair, not a numeric retune

1. Establish a receiver-owned SRS-to-PUSCH reference-energy/port-mapping contract: what pilot amplitude is already in `Hest`, what data energy is assumed, the applicable precoder normalization and the disturbance covariance/reference plane. Use declared/causally available power-control information; do not read future UE waveform power as a receiver oracle.
2. Apply any justified pilot-to-data amplitude conversion to the channel/energy **before** evaluating each MMSE rank/TPMI candidate. Keep combining gain, layer interference and the per-candidate MI objective consistent with the final prediction. If required power information is unavailable, retain explicit unavailable prediction rather than normalizing an output to a convenient scalar.
3. Remove the `anchor - selected_mean` output shift from the strict scheduling path. Keep pilot-residual quality as its separately labelled diagnostic. Do not replace this with a new fitted offset, configured 12 dB, a geometry-derived target or a forced rank-one result.
4. Update `runSRSChannelEstimation` and `CoupledTruthRuntime` acceptance to the new physical reference contract. Keep independent NMSE scoring outside receiver decisions.
5. Replace the existing `testLLSULSRSRITPMIEstimator` assertion that forces the mean to an arbitrary 6.25 dB anchor with independently derived power/combiner invariants. That old assertion verifies the defective contract, not correct post-equalization physics. Retain valid RI/TPMI/codebook tests, and add one/two/four branches, equal/unequal pilot/data energy, rank-dependent precoders, coloured disturbance, and missing-authority rejection. Run final-source full and NR/export guards.

This repair is required for mathematical prediction accuracy; it does not mean SRS channel estimates, actual injected power or the independent NMSE score are necessarily wrong. A retained-capture replay is being used to separate these claims.

- Combining diagnostic log SHA-256: `EB3A968DECE169490BF8C33BD533FF4FEC5099BA9851E8ED9451F386F5CE3698`.

### Retained SRS capture: NMSE reproduced, noise denominator discrepancy isolated

`diagnose_retained_srs_measurement_20260916.m`, third run, completed with exit 0 on the first actual SRS capture (runtime slot 30). It replays only the retained post-RF/digital-gain-compensated received samples through the practical receiver, then uses the original executed channel coefficients for separate scoring. No transmitter, channel or random noise is rerun.

| Quantity | Result |
| --- | --- |
| Original NMSE | -27.548744155257737 dB |
| Recomputed NMSE | -27.548744155257737 dB |
| Compared channel values | 576 (two receive branches, two SRS ports) |
| Unique physical pilot REs | 144 |
| Reconstructed pilot signal power | 5.4554454484626715 |
| Actual received-minus-reconstructed pilot residual power | 0.0626469639360971 |
| Receiver noise variance used in the SINR denominator | 4.1061093226997558 |
| Original/replayed/direct-grid SINR using the current denominator rule | 1.2339970940072136 dB |

The independent grid calculation sums all configured port contributions on each physical RE, then compares with the captured receive grid. It matches the current pilot-metric arithmetic. The next root is therefore the noise estimator/its applicability, not a missing port sum in this particular metric. A fitted-pilot residual alone is not an unbiased noise oracle and must not simply replace the receiver estimate.

`SRS_Rx.m::localEstimateSRSNoHop` supplies `CDMLengths` only if that field exists in the `nrSRSIndices` information structure. Otherwise `nrChannelEstimate` uses its default no-despreading setting. The [MathWorks SRS channel-state estimation example](https://www.mathworks.com/help/5g/ug/nr-uplink-channel-state-information-estimation-using-srs.html) instead explicitly derives SRS CDM lengths from the configured sounding signal. The [channel-estimator contract](https://www.mathworks.com/help/5g/ref/nrchannelestimate.html) distinguishes frequency/time CDM despreading from subsequent averaging. A same-grid CDM counterfactual is in progress to test this specific cause before choosing any correction.

The first diagnostic stopped on the MATLAB/HDF5 Windows long-path limit. The second explicitly supplied NaN injection metadata and was correctly rejected; the production path omits unavailable injection metadata and estimates noise from received references. The third follows that path. Both earlier failed logs are preserved as diagnostic setup failures, not simulator PHY failures.

- Byte-identical short-path copy SHA-256 (also verified against the original 44,900,048-byte capture): `5B6C928D97A395F3B97AFF9F5AED65D5AE26C704E2A43B62724D88F011900D12`.
- Completed replay log SHA-256: `F05EFFF37C252E2ED16973722C384562AA6CD238E32C031F0F41F6701A6A79A5`.

### SRS estimator-input root confirmed on the same captured grid

`retained_srs_cdm_probe_20260916.log` completed with exit 0. The actual `nrSRSIndices` metadata has **no `CDMLengths` field**, so `SRS_Rx` takes its no-despreading branch. The two configured ports occupy the same physical pilot REs. Their known reference sequences have two-position cross-inner-product magnitude at most `4.613e-14`, confirming the pairwise orthogonal structure independently of any received value.

| Frequency/time CDM input | Estimated grid noise | NMSE | Resolved averaging window |
| --- | --- | --- | --- |
| [1,1] (current implicit setting) | 4.1061093227 | -27.548744 dB | [7,3] |
| [2,1] (matching the two-position orthogonal group) | 0.0717743564 | -28.598619 dB | [7,3] |
| [4,1] (diagnostic comparison only) | 0.0689516870 | -28.681346 dB | [7,3] |

Every row uses the **same actual received grid**, SRS symbols, measured timing and independent channel-scoring reference. No power, injected noise, propagation loss, channel execution or expected target SINR is changed. The four-position comparison is not permission to select a longer group because it happens to improve this sample. The two-position configuration is justified by the installed reference-sequence structure. Qualify the resulting receiver estimate statistically; do not force it to equal either the 0.06265 fitted-pilot residual or a known injection label.

Required implementation additions/removals:

1. In `+sixgr/+phy/+ul/SRS_Rx.m`, replace the `isfield(srsInfo,'CDMLengths')` default-to-no-despreading assumption with explicit SRS CDM resolution from the configured port/comb/cyclic-shift/resource structure. Reuse that authority for normal and hopped occasions. Do not hardcode two for all scenarios or silently fall back to no-CDM after a configuration error.
2. Keep CDM despreading separate from the averaging window and retain the actual resolved estimator settings in receiver evidence. The current function overwrites `estInfo.AveragingWindow` with the requested `[0,0]`, hiding the public estimator's resolved `[7,3]`; retain requested and resolved values separately rather than overwriting measured execution metadata.
3. Add configured-reference orthogonality tests for supported one/two/four-port layouts, comb and cyclic-shift variants, hopping and partial resources, plus invalid/ambiguous configuration rejection. Use noisy actual waveforms to check noise-estimate bias and NMSE without substituting injected noise into the runtime receiver.
4. Replay all six retained SRS captures, then run normal TDD SRS-to-PUSCH integration with corrected covariance and physical pilot/data energy conversion. Keep the original capture/reports immutable. These two fixes must be tested together because the wrong noise estimate affects RI/TPMI selection before the separate output-anchoring defect.

This explains why good channel NMSE and existing scoring/ownership tests did not close the scheduling-measurement issue: those tests do not establish correct received noise estimation or an accurate SRS-to-PUSCH SINR transformation. The inspected SRS receiver and measurement files are identical in `d05c1441` and `5d20e64d`; the queued candidate does not already contain these repairs.

- CDM diagnostic log SHA-256: `49EF71C955C1E1F95F4C051E70E0B6CFBEB08FF983BEC5169CA181F96250CE09`.
- CDM diagnostic MAT SHA-256: `A6DBC88C14FFA9EB9DC4AF61C8087CD4F1B51DFE5D34406409BB787EC026F964`.

## SRS grid contract: two additional independently reproduced defects

`logs/diagnose_srs_grid_contract_20260916.m` in the isolated development checkout completed with exit 0. This is a controlled channel/equalizer-input diagnostic, **not** a new waveform execution or an observed error magnitude in the retained 12 dB scenario. Production source is unchanged.

### Complex averaging creates a false frequency-selectivity loss

`estimateSRSRITPMI.m::localPRBAveragedChannel` averages complex channel coefficients over each PRB (lines 280 and 299), before the nonlinear MMSE SINR/MI calculation. A pure frequency-dependent common phase therefore reduces its calculated channel gain even when every resource element has unchanged channel magnitude and spatial structure.

Counterexample: 12 subcarriers, two symbols, two receive branches, one transmit port, unit magnitude, received branch-noise variance 0.1. Apply `exp(-j*2*pi*k*15000*2e-6)` equally to both branches. The phase is the frequency response of a 2 microsecond pure delay; this diagnostic supplies the frequency response directly and does not simulate timing acquisition.

| Calculation | Flat phase | Frequency-dependent phase |
| --- | --- | --- |
| Existing unanchored prediction | 13.0102999566 dB | 11.0854267736 dB |
| Independent per-RE `nrEqualizeMMSE` signal/noise-basis result | 13.0102999566 dB | 13.0102999566 dB |

The spurious loss is **1.9248731831 dB**, exactly `-10*log10(abs(mean(phase)).^2)`. This is distinct from the later output-anchor defect. Removing only that anchor would expose, not repair, this upstream error. The reference uses the public equalizer's extracted per-resource channel/noise contract ([MathWorks nrEqualizeMMSE](https://www.mathworks.com/help/5g/ref/nrequalizemmse.html)).

Required change: evaluate candidate effective channels and MMSE SINR/MI on valid per-resource observations, then aggregate the resulting linear SINR and MI using explicit observation weights. Do not average complex channel phases as a substitute for averaging signal quality. Preserve one precoder selection across its configured scheduling domain; per-RE evaluation does not authorize independently selected per-RE TPMIs. Any intentional reduced-resolution approximation must be separately labelled, not silently used for strict prediction. Keep actual channel-estimator smoothing separate from this predictor aggregation.

Closure tests: common per-RE phase invariance, amplitude-selective and spatially selective channels, one/two/four receive branches, rank/precoder power normalization, and independent per-RE equalizer comparisons. Retain the old failing counterexample.

### Singleton dimensions confuse grid axes with antennas and ports

At line 253 the same helper treats every MATLAB matrix as a wideband receive-by-transmit channel. MATLAB represents `ones(12,2,1,1)` as a `12x2` matrix, so a legitimate single-receive/single-port grid is interpreted as **12 receive antennas and two SRS ports**. The diagnostic's expected 10 dB becomes **20.7918124605 dB** after restriction to the configured one-port PUSCH codebook. It also reports one SRS symbol instead of two.

The actual retained scenario has two receive branches and two SRS ports; this counterexample is **not** the explanation for its observed SRS noise value. It proves a separate supported-shape hazard that the repair must not perpetuate. Current grid callers include `runSRSChannelEstimation`, `measureULLinkState`, and `estimateULChannelFromSRS`; matrix-based experiment/beam-selection callers also exist, so changing the interpretation of every matrix globally would break a legitimate interface.

Required change: make the input domain explicit (resource grid versus wideband spatial matrix), with expected receive/port dimensions and observed resource support. Propagate the domain at existing callers and validate it. Do not infer the domain solely from `ndims`, expand a scalar over a fading grid, or silently select the first symbol as if it were the first antenna port. Preserve intentional matrix-based algebraic/component callers via their explicit domain.

Closure tests: `KxLx1x1`, `KxLxRx1`, `KxLx1xP`, full MIMO grids, single-symbol grids, explicit spatial matrices, and contradictory dimensions rejected. Trace every call site before removing the heuristic.

The SRS repair unit is now explicitly: configured CDM/noise evidence, explicit grid domain, per-resource candidate evaluation, physical pilot/data reference conversion, and removal of output anchoring. Those are related changes to existing routines, not five new estimator frameworks.

- Diagnostic log SHA-256: `3FA969C17F1581AAC9C72DC6AA5AB84BDC0BE7850F05423EE8A7FFC0A4D74038`.
- Diagnostic MAT SHA-256: `BCA91FF7A18661F61F84A9969C32BA17BC2FEB171E510D16082B3094FDDCA739`.

## Configured SRS despreading and hopping: bounded design evidence

`diagnose_srs_reference_groups_20260916.m` completed with exit 0. It enumerated **468 configured-reference cases**: ports 1/2/4; comb 2/4/8; every valid base cyclic shift; comb offsets zero and the last valid offset; and the three group/sequence-hopping configuration values, at slot zero with four SRS symbols and `CSRS=BSRS=BHop=0`. It used known `nrSRS` symbols and `nrSRSIndices`, not received samples or an expected SINR, to identify disjoint/co-located port groups and their smallest blockwise orthogonal frequency grouping. Maximum normalized Gram-matrix error was `5.3016055689184683e-15`.

| Configured ports | Comb / cyclic shift | Co-located ports | Derived frequency despreading length |
| --- | --- | --- | --- |
| 1 | All tested | 1 | 1 |
| 2 | All tested | 2 | 2 |
| 4 | Comb 2, shift 0-3 | 4 | 4 |
| 4 | Comb 2, shift 4-7 | 2 | 2 |
| 4 | Comb 4, shift 0-5 | 4 | 4 |
| 4 | Comb 4, shift 6-11 | 2 | 2 |
| 4 | Comb 8, shift 0-5 | 2 | 2 |

The branch structure agrees with the cyclic-shift and comb-offset mapping in [TS 38.211 V18.8.0, 6.4.1.4.2-3, pages 110-112](https://www.etsi.org/deliver/etsi_ts/138200_138299/138211/18.08.00_60/ts_138211v180800p.pdf). Receiver despreading remains a receiver implementation choice to validate; the standard defines the transmitted references, not a simulator-specific noise estimator. The public channel estimator accepts an explicit frequency/time CDM arrangement ([nrChannelEstimate](https://www.mathworks.com/help/5g/ref/nrchannelestimate.html)).

This closes the objection to deriving one universal value from the retained two-port capture. It is **not** exhaustive hopping or noisy-channel qualification: intermediate comb offsets, other slots/bandwidths, partial-frequency sounding, dynamically changing groups, multiuser interference, and receiver statistical bias remain to test. In particular, selecting `sequenceHopping` on these short sequences does not establish coverage of its long-sequence active behavior. Eight-port extensions are outside the current strict validator's accepted 1/2/4-port domain, not silently covered by this matrix.

### Confirmed frequency-hopping branch is unreachable for native configuration

The same diagnostic generated an OFDM SRS component with `CSRS=4`, `BSRS=1`, `BHop=0`, four symbols, repetition one, two ports, comb two, and declared additive sample noise. It passed the samples through the existing `SRS_Rx`, without supplying known noise as receiver input. Actual first occupied subcarriers across the four symbols were **[1,97,1,97]**: two different frequency allocations. Nevertheless, receiver evidence reports **`FrequencyHoppingHandled=false`**.

Root: `SRS_Rx.m::localSRSFrequencyHoppingEnabled` reads `srs.FrequencyHopping`, catches the missing-property exception and returns false. `nrSRSConfig` has no such property. Ordinary frequency hopping is controlled by **`BHop < BSRS`**, and further supported resource movement must be resolved from configured/mapped support. [MathWorks nrSRSConfig](https://www.mathworks.com/help/5g/ref/nrsrsconfig.html) This component establishes incorrect dispatch, not an NMSE error magnitude or an integrated-run failure attribution.

There is a related source-level evidence error in `validateSRSFrequencyHoppingCoverage.m`: `FrequencyHopping ~= "neither" || BHop > 0` is not the native hopping predicate. For example, BHop zero can enable hopping when BSRS is one, whereas a positive BHop greater than or equal to BSRS disables ordinary bandwidth hopping. `buildSRSResourceStrict` configures native BSRS/BHop; the independent string is not a replacement authority. Reconcile the validator with the executed resource configuration and actual cumulative support; retain the difference between hopping configured, movement observed in the selected window, and full-carrier coverage achieved.

### Exact receiver repair boundary

1. In `SRS_Rx`, resolve the configured port groups/despreading **before** estimation using the installed `srs`, carrier, reference indices and reference symbols. The received grid, scoring channel and target SNR cannot select the grouping. Use a bounded local resolver, not a second SRS receiver or another configuration hierarchy.
2. For current supported non-positioning 1/2/4-port layouts, implement the mapped co-location/cyclic-shift rule and verify orthogonality in tests. Resolve per occasion/symbol when support changes; do not assume all four ports are co-located. Keep frequency and time despreading distinct.
3. Replace the nonexistent-property hopping branch with validated native configuration and mapped support. Group observations only where time/frequency estimation assumptions are valid. Do not interpolate over different hops as though they were repeated observations of the same allocation, and do not present zero-initialized unsounded regions as measured channel values.
4. Remove the broad catch-and-retry behavior for strict configuration/CDM errors. Currently the outer `catch` retries `sixgr.phy.rx.channelEstimate`, potentially losing SRS-specific assumptions, then erases a second error into empty estimates. Preserve the original failure/evidence; any intentionally supported alternative must maintain the same resource/noise contract and explicit provenance.
5. Preserve requested and resolved averaging windows separately. The current window resolver also looks for `CombSize`/`KSRS` rather than canonical `KTC`, so confirm and replace that lookup as part of this same contract, not with another implicit comb-two default.
6. Extend the existing SRS tests with the matrix above, real noisy/multipath received grids, hopped/non-hopped dispatch, nonzero frequency starts, active long-sequence hopping, partial sounding, and R2023b-supported API execution. Retain the captured-noise discrepancy and replay all six original captures after repair. A reference-algebra pass alone does not close these receiver tests.

- Diagnostic log SHA-256: `AE110AAF28313D532B4D3E052D3FBB6A743CAB1D07637FD2AEF40BCF43B07BBB`.
- Reference-case CSV SHA-256: `2D0F7BCC45DC143D1954248D4C5DE737895D519756A545E1BFD3BAD8E70CB9D6`.
- Diagnostic MAT SHA-256: `0A767EF20AF339DC04C1361DE67E770C4EB0F6F4CC8F204F6AEBC9B91BBF45D3`.

No production receiver/configuration change was made. This is additional evidence for the existing SRS repair unit; it does not change the first UCI wire/resource implementation priority or declare the analysis gate complete.

## Normalized 12 dB SRS-to-PUSCH energy contract: independently checked

`diagnose_srs_data_energy_20260916.m` completed with exit 0. Inspection of the original retained SRS capture reports:

- `RunMode=FIXED_SNR_SWEEP`, `ConfiguredSNRIsAuthority=true`;
- `FixedSNRNormalizedReference=true`, `AmplitudeScale=1`;
- `PhysicalDevicePowerClaim=false`, `PowerNormalizationPolicy=unit_occupied_re_fixed_esn0`.

This agrees with `applyPowerContext.m`: the explicitly normalized connected sweep retains IFFT samples with no device-power amplitude scaling. Both SRS and PUSCH preparation use that common scaler. The inspected scaler and SRS/PUSCH runner files have no difference between `d05c1441` and `5d20e64d`. The capture metadata is audit evidence; the future receiver must obtain its normalization contract from independently installed configuration, not read a prepared transmitter object to infer power.

### Conversion proof, including unequal amplitudes and native codebooks

Write the estimated SRS port-domain channel as `H_srs = a_srs * H`, where known pilot symbols have already been divided out by the estimator. With unit-mean-energy layer symbols, declared PUSCH amplitude `a_data`, and the native port-by-layer codebook matrix `W`, the effective prediction is:

`H_eff = (a_data / a_srs) * H_srs * W`.

For spatially white received grid noise variance `nVar`, evaluate `C = inv(I + H_eff' * H_eff / nVar)` and `SINR_layer = 1 ./ diag(C) - 1`. This is the prediction model, not a measured future PUSCH SINR. Frequency-selective channels require per-resource evaluation; an output scalar anchor is not part of this calculation. Coloured disturbance requires the appropriate covariance, not a relabelled white-noise scalar.

The diagnostic used actual public SRS symbol/index generation and practical channel estimation on declared flat-channel reference grids, then checked every catalogued non-transform-precoded TPMI/rank for ports 1/2/4, four receive branches, and all nine combinations of SRS/data amplitude 0.5/1/2. It compared the covariance formula against independent public `nrEqualizeMMSE` responses to each desired layer, interfering layer and receive-noise basis. **648 comparisons passed**; maximum channel reconstruction error was `1.2475177973147167e-15`, and maximum SINR discrepancy was `1.0125438398809526e-14 dB`.

The public SRS symbols in these cases have mean per-port symbol energy **1 for all three port counts**. Do not insert an assumed `1/sqrt(ports)` factor into their interpretation or renormalize native PUSCH codebooks to obtain a preferred result. The actual known reference symbols, mapping conventions and explicitly applied amplitude define this calculation. These controlled grids contain no random channel/noise realization; the noise-basis comparison is algebraic verification, not a noise-estimator, RF, fading or link-qualification campaign.

### Implementation decision for the current normalized scenario

1. For the declared fixed-SNR path, bind a receiver-owned normalized-grid contract from the installed integration mode, numerology, SRS/PUSCH port mapping and native precoder convention. The additional scalar amplitude ratio is one in that path; do not infer it from configured **12 dB**, a pilot SINR, a link-budget subtraction, or future transmitted bits. Validate matching port domains/reference planes and resource support before accepting a prediction.
2. Feed the **correctly despread practical channel estimate and received disturbance estimate** into per-resource candidate evaluation. Remove the selected-mean anchoring shift, preserving actual spatial combining and rank/codebook energy effects. Keep finite-noise, age, coverage and epoch validity gates.
3. In `runSRSChannelEstimation`, replace `localResolvePUSCHSchedulingSINRAnchor` and the downstream source-name requirement containing `anchored_selected_ri_tpmi` with this typed reference contract. Preserve the pilot quality diagnostic separately. Update `CoupledTruthRuntime` and CQI consumers to accept a valid **prediction**, not falsely label it a measured future data-channel value. Test missing/mismatched authority and poisoned TX metadata.
4. Keep absolute-power/thermal mode separate. This diagnostic does not establish a receiver-causal SRS/PUSCH amplitude ratio under independent power-control states, clipping, distinct beams or RF changes. Such modes require their own known/estimated reference conversion; missing authority must be unavailable, never a return to `ServingRxPower_dBm - ThermalNoisePower_dBm` as a fabricated post-equalization anchor.
5. Extend the existing SRS estimator tests with the exact equalizer comparison, common-amplitude/noise scaling, unequal pilot/data scaling, supported native rank/TPMI choices and explicit normalized-mode identity. Preserve valid codebook orientation tests. Then replay retained captures and run actual SRS-driven PUSCH to validate prediction versus observed outcome without requiring equality across channel aging or estimation error.

This settles the scalar-energy interpretation for the current normalized path and makes its repair bounded. It does not close its noise estimator, resource aggregation, combined-feedback dependencies or integrated measurements, and does not silently restrict the overall simulator objective to normalized operation.

- Diagnostic log SHA-256: `182DFD2433B115DF63429CA3146B47E5F1CEFEAC0892B6A982ECCDE12C2CCC4A`.
- Comparison CSV SHA-256: `3CC33404DE270E1F7F8D50866EEFE070E4719D8C846772CA8EE2C28E1232CF8E`.
- Diagnostic MAT SHA-256: `216656350B73EF137BBAD22E2C8009E0316C92166DAB17FD1468D789ADAF73DE`.

## Detector root reconciled against all original post-RF samples

`diagnose_retained_pucch_metric_20260916.m` completed with exit 0. It reads every original noise-only post-RF observation, demodulates the OFDM grid, generates the configured public PUCCH reference hypotheses, and independently computes each per-symbol/per-branch normalized correlation magnitude, their average, the winning hypothesis and the unchanged threshold decision. It does **not** call the PUCCH decoder or the simulator's detector helper for those computations.

All **1,024 retained rows** (512 shared IQ occasions, each interpreted with one- and two-bit HARQ schemas) matched. Maximum metric discrepancy was **6.1062266354e-16**. Every detected flag and false-ACK count matched, including the original failure:

| Layout | Occasions | False detections | False ACK bits / opportunities |
| --- | --- | --- | --- |
| One bit | 512 | 8 | 2 / 512 |
| Two bits | 512 | 16 | 12 / 1,024 |

The whole IQ SHA-256 matches the original independent audit. Current configuration/CSV/summary hashes match the archived null-model inputs, and the installed native Format-0 decoder hash is unchanged. No new independent RF episode was generated, no threshold was fitted, and no physical noise or power parameter was changed.

### What is now diagnosed, versus what still needs qualification

The earlier three-day-old mathematical audit was preserved inside `pucch_detector_math_and_noise_evidence_20260913_01.zip`, not missing. Its actual script, receipt and input hashes have now been inspected and reconciled. Under its explicitly idealized white-noise/orthogonal-reference model, four-block magnitude averaging and threshold 0.42 give single-hypothesis exceedance bounds 0.00881483-0.00883532. Its two-million-model-occasion calculation gives approximately **3.5187%** false detections and **1.7594%** false ACK bits for four hypotheses. These are mathematical model results, not RF measurements. The observed 16 detections fall inside that model's 99% prediction interval of 8-30 per 512 occasions.

Together with the new exact raw-IQ correlation replay, this establishes a concrete **threshold/search-space policy failure**, not evidence that counting, FFT scaling, a missing noise injection, or the valid finite-metric correlation formula needs to be rewritten. The two-symbol 0.42 value is a toolbox default, not a universal performance guarantee ([MathWorks nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html)). Nonwhite noise, time-varying AGC and acquired-timing effects still require physical qualification; the ideal model does not explain each RF contribution exactly.

The separate invalid-metric fail-open bug in `PUCCHDetector.decide` remains a code repair. It is not the cause of the retained finite-valued 12/1,024 result. Correctly distinguish these two tasks rather than repeatedly calling the entire detector issue undiagnosed.

### Bounded changes and acceptance sequence

1. Repair invalid/non-scalar/nonfinite metric/threshold handling without decoded-bit fallback. Retain rejection tests and the original finite-input behavior for legitimate component calls.
2. Preserve the finite correlation calculation unless new evidence contradicts it. Reuse the already implemented YAML policy and analytically derived **0.77 development candidate**; do not introduce another threshold-fitting framework or count replayed evidence as independent episodes. Its retained paired pilot passed eight cases on an older revision; that is development evidence only.
3. Freeze receiver semantics **after SR-format repairs**, because SR can change the reference hypothesis set. The existing HARQ-only Format-0 candidate/model does not qualify SR-containing resources, Format 1 or the Format-2 combined reports used by the normal scenario. Keep the hypothesis-count and resource applicability explicit.
4. Reuse `runPUCCHDetectorEpisodes`, `runPUCCHDetectorCampaign` and their raw evidence/clock/source accounting. Final-source signal-present and noise-only execution, development-history/seed review, original family confidence/error gates, and independence checks remain required. Do not simply set `development_history_complete=true` or promote 0.77 to production because old retained metrics happen to pass it.
5. Keep physical qualification separate from implementation time. The recorded paired candidate episode took 624.49 seconds. Multiplying that observed development runtime by the configured 600 episodes is roughly **104 serial execution-hours**, an order-of-magnitude planning observation, not a promised campaign duration. Final runtime may differ; server capacity and validated parallel partitioning matter. Reducing episodes, discarding interrupted/failed cases, or changing confidence gates to fit a 2-3 hour deadline is not allowed.

This closes the finite-metric arithmetic/counting diagnosis for the retained failure. The repair and qualification tasks are now explicit; detector qualification and integrated 12 dB acceptance are still incomplete.

- Original IQ SHA-256: `09B4484532064268154E0669C5E348EC2917AAB753573284258DBDC139D74D9D`.
- Diagnostic log SHA-256: `2E395A40CB1B8423A2E5F15950AAE003B27B3B3D5D2A06653FF9E19D5485973A`.
- Independent row CSV SHA-256: `DC115998C8BC6DE10BC2C44258F6BE76B8CC4538B2E5CF070778D938B55DF6CA`.
- Diagnostic MAT SHA-256: `0B1A3FD995E2A92A526E0EBE40BA570B693FA82BE4056EF5711A774DD13E5A43`.

## Unique-delivery goodput: counterexample and export trace

`logs/diagnose_duplicate_tb_goodput_20260916.m` completed with exit 0. It first ran the unchanged `testCausalKPIEventAccounting` (already registered in `testAll`) and then exercised the existing public KPI reconstructor on an explicitly declared accounting fixture. These are not fabricated PHY observations or additions to primary run tables.

For each of DL and UL, three CRC-passing attempts carry 1,000 bits each. The first two have the same TB identity/NDI epoch and represent initial success followed by successful retransmission after lost feedback; the third is a new TB. Over the declared four-millisecond measurement window:

| Quantity | Result |
| --- | --- |
| Successful attempt bits | 3,000 |
| Distinct successfully delivered TBs | 2 |
| Existing reconstructor's first-success delivered bits | 2,000 |
| Successful-attempt rate | 0.75 Mbps |
| Unique-TB goodput | 0.50 Mbps |

The existing reconstructor produces the correct 2,000-bit result for both directions. The private coupled-runtime accumulator was **not invoked** by this diagnostic; the production discrepancy is established by its source/export chain:

1. `CoupledTruthRuntime.completeSlotImpl` calls `updateUserStats` for every completed trial at line 3830 and rebuilds `UserPerformanceTable` at line 3836.
2. `updateUserStats` adds each row's `GoodBits` to `GoodBitsSum` at line 4695, without TB-identity or first-success filtering. The waveform runners legitimately report per-attempt successful bits; those rows must not be rewritten to hide retransmissions.
3. `buildUserPerformanceTable` labels this sum divided by the observed time as `DL_Goodput_Mbps` / `UL_Goodput_Mbps` at lines 4746-4747.
4. `writeTablesImpl` writes that table directly to `live_user_performance_snapshot.csv` at line 3249. The inspected export route does not replace its counter with the independently reconstructed first-success ledger.

The actual failed 12 dB run has 19 DL and 5 UL completed rows, all successful and with distinct TB identities. **There is no claim that its observed goodput was double-counted.** Those rows simply cannot expose the repeat-success defect.

### Repair boundary

- Reuse the existing canonical TB-identity/NDI-epoch and first-success accounting from `reconstructLLSKPISummaryFromRaw`, and the existing runtime delivery transition where appropriate. Do not add an unrelated deduplication ledger. `updatePacketDeliveryFromHARQ` already protects packet delivery with `firstMask`; preserve that protection.
- Keep successful-attempt bits, scheduled bits, unique PHY TB bits, and delivered application/SDU payload distinct. Packet first-success state is not permission to substitute application payload size for PHY TB size. Preserve direction, UE/RNTI, epoch and reset scope.
- Replace only the user-goodput numerator with correctly identified first-success TB bits; preserve attempt-level CRC/BLER and scheduled-airtime throughput. Missing identity must not silently become a new successful delivery. Retain explicit measurement-window units.
- Extend existing accounting/runtime tests with success/lost ACK/retransmission success, failure/retransmission success, NDI reuse, UE/direction separation, duplicate completion and epoch reset. Exercise the actual coupled-runtime completion/export path in addition to the existing pure reconstructor. Verify live and final CSV agree for the same interval.
- Do not change PHY power, decoding, TB outcomes, or original assertions for this accounting repair.

Evidence hashes: log `99C240D305640BFF5650CDB443E28D1EDCDD005F0F71D798D470233BED074041`; MAT `285B64C4F1F6D00EAE9976BEC352D640312586A2A49A9EE17B682661A15FD3A0`.

## 09:57 IST checkpoint: implementation handoff, not qualification

Ahead of the 10:01 two-hour diagnosis/design checkpoint, the audit has produced reproducible counterexamples and bounded repair locations. It has **not** proved that every simulator defect is known. The analysis-first pause remains in force for production code at this checkpoint; no repair below is represented as already integrated.

### Ordered work packages

| Order | Deliverable and existing files | Remove/replace | Required exit test |
| --- | --- | --- | --- |
| 1 | Complete the UCI wire/resource contract in `PUCCHConfigBuilder`, `PUCCHRRCContext`, `PUCCHResourcePlan`, `UCIReportSerializer`, short-format TX/RX helpers, existing config catalog/scenario and SR state coordinator | Permanently empty SR, flat short-format SR treatment, interim global permission in place of per-format authority, capacity calculations omitting CRC/rate/minimum allocation | Public-reference positive/negative SR semantics; permission validation; 11/12- and 19/20-bit boundaries; resource reservation/TX/RX/power bandwidth agreement. Complete this task before combined-receiver integration. |
| 2 | Independent combined feedback through existing `buildScheduledHARQTransportReception`, configured receive contexts, `CoupledTruthRuntime`, common commit and CSI consumer | Strict-runtime TX-context fallback and producer-presence acceptance authority, only once replacement passes | Fixed-IQ TX-metadata poisoning; first/middle/last/all missed DCI and wrap; absent CSI; both transports; overlap/late/stale/duplicate/no-producer cases. Ambiguous fields remain unresolved, never successful by default. |
| 3 | Detector input correctness in `PUCCHDetector` / `PUCCHReceiver`, then existing frozen-policy pilot/campaign | Nonempty decoded-word fallback for invalid metrics; no change to finite correlation arithmetic without new evidence | Malformed metric/threshold entry tests; unchanged baseline evidence; independent signal/noise episodes for the actual supported formats/hypotheses after SR semantics freeze. |
| 4 | SRS receiver/prediction in `SRS_Rx`, `estimateSRSRITPMI`, `runSRSChannelEstimation`, native hopping validator and identified consumers | Implicit CDM-one, wrong hopping property, swallowed strict errors, singleton axis inference, complex averaging before SINR, output anchoring and measured-future-data label | Reference matrix, acquired/noisy/hopped captures, per-RE MMSE and combining/phase invariants, native codebook energy checks, actual predicted-versus-observed PUSCH with declared age/reference planes. |
| 5 | Existing finalization/reporting in `CoupledWaveformStream`, `runWaveformLinkBundle`, `exportLLSLiveDerivedTables`, `lls_csv_semantics.py`, `CoupledTruthRuntime` user summary | Do not replace the focused-passing tail repair; replace divergent FER populations, missing reference identity and attempt-sum goodput labels | Final scheduled TB completes; same population in MATLAB/Python; unique-delivery counterexample through real runtime; all enabled measurement CSV/PNG identity, units and numerical checks. |
| 6 | Only proved TDD fixture corrections, then one frozen source and preserved-content consolidation | Contradictory fixture clocks/resources/authority, not negative guards; no wholesale historical-test rewrite | Final-source focused tests, mandatory NR/config/strict/scheduler/export/E2E guards and unfiltered `testAll`; diagnose remaining failures. Report deferred FDD failures explicitly; never call a TDD subset a full-suite pass. |

The integration contract is deliberately conservative: gNB-owned configuration/schedules and actual received observations select legal interpretations; UE-produced presence, expected bits, or TX-selected lengths cannot select a winner. Exact waveform ambiguity is retained in field/identity validity. On PUSCH, resource-invariant HARQ can be evaluated separately from ambiguous CSI/UL-SCH, but only after checking invariance for that allocation. A high conditional decoder confidence is not signal-presence evidence. These are implementation boundaries requiring receiver tests, not a claim that 3GPP mandates this particular receiver algorithm.

### What will not be rewritten

Preserve the existing Type-2 layout engine, valid finite-correlation detector math, common physical feedback clock/commit, practical per-resource channel estimation, corrected CSI completion/calendar fixtures, candidate tail repair, normalized-power authority, original failed captures, and correct KPI reconstruction. No second receiver framework, scenario-specific SINR injection, forced ACK, zero-padded receive-tail rescue, test deletion, or proxy result rows belong in this plan.

### Timing and current execution

- The earlier **1-2 working-day implementation estimate is withdrawn** because it was not derived from this dependency map. A universal **2-3-hour fix-and-qualification promise is also unsupported**.
- The **10:01 diagnosis checkpoint** has its documented, evidence-backed repair map ready at 09:57. Exhaustive root-cause/qualification closure is not met. The **11:01 outer review** should report the first work package's design/patch/test state, including any remaining blocker, not silently move the deadline or mark unrelated tests as closure.
- Use a maximum **60-minute implementation checkpoint** per active work package; report exact diff and targeted results before moving to another package. This is progress discipline, not a claim that each package must finish within one hour. No total code-completion estimate is established yet.
- The recorded eight-case detector pilot took 624.49 seconds; the configured 600 episodes extrapolate to roughly 104 serial hours. Preserve its gates and measure second-server capacity before promising a parallel finish time. This is separate from a diagnostic 12 dB run.
- At the latest process check, MATLAB engine 8316 (launcher 24104) is still executing the old `d05c1441` full suite. Candidate `5d20e64d` reports `waiting_for_prior_pipeline`, not a running/passed 12 dB scenario. The focused diagnostics are terminal; no new full suite was launched.
- Keep FDD/400 MHz deferred, R2023b explicitly unverified, and sweep `[-30,-20,-10,0,10,12,20,30,40]` intact. Commit/merge/push only the reconciled source with accurate validation labels; a clean tree is not a qualification certificate.

## First UCI work package: implemented corrections and retained limits

Source: `C:/Users/anup0/AppData/Local/Temp/sixgr_tdd_combined_receiver_20260916`, base `5d20e64d` plus uncommitted edits. The IDE checkout still holds this audit, not the production edits. No commit, merge, push, log deletion or change to either frozen validation checkout was made during this implementation checkpoint.

### What changed

- `PUCCHTransmitter` now passes Format-0 HARQ and SR as separate public-API inputs. `PUCCHReceiver` supplies independent HARQ/SR lengths and retains both decoded cells. SR is no longer a third HARQ modulation bit. `PUCCHFormatValidator`, `PUCCHResourceSetResolver`, `PUCCHResourcePlan` and `PUCCHReceptionAssignment` preserve that distinction while continuing to reject three HARQ bits or CSI on short formats.
- Format-1 SR-only positive transmission uses the public reference's fixed zero-bit BPSK symbol, and the receiver interprets detected presence as positive SR. Mixed Format-1 HARQ/SR is now explicitly rejected until its SR-dependent resource arbitration is implemented; concatenating SR into HARQ modulation is not a replacement for that procedure. This guard is not a claim that the mixed procedure is complete.
- Negative SR with no HARQ produces no transmitted REs. `PUCCHGridMapper` only accepts an explicitly suppressed, empty short-format mapping; ordinary missing symbols still fail. Its primary transmitted ownership table is empty, the actual waveform is zero, and applied-power/error claims are unavailable. The higher-level coordinator must suppress the transmit event; `preparePUCCHTransmitWaveform` is not yet integrated with this no-transmission disposition. Do not count this component fix as the normal MAC/SR loop.
- `PUCCHRRCContext` now stores format-owned permissions. `PUCCHConfigBuilder` maps YAML `format2`/`format3`/`format4` configuration, and TX planning and RX assignment check the selected resource's format. Absent/false permission denies combined HARQ/CSI. Global and duplicate authorities are rejected. The TDD scenario explicitly permits its Format 2; it does not grant permission to Formats 3 or 4. The schema and declared component fixtures were updated accordingly. No maximum coding rate has been silently chosen.
- `UCIReportSerializer` rejects malformed scalar SR `Value` inputs instead of converting nonbinary values to true. The original `testPUCCHFormat0SRSemantics` is now registered, together with `testPUCCHShortSRContract` and the per-format permission guard. Original reference assertions and detector thresholds were retained.

The short-format API contract is independently documented by [nrPUCCH](https://www.mathworks.com/help/5g/ref/nrpucch.html) and [nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html). The implementation uses APIs available by R2023b, but actual execution on R2023b remains unverified.

### Test receipts and scope

1. `logs/pucch_sr_wire_v1_20260916.log`: exit 0. All 14 original Format-0 reference cases pass; receiver-only retained-noise equivalence, CRC rejection, and two mixed HARQ/SR/CSI component waveforms also pass. SHA-256 `89925BC100C2B0A76B148F270AE38BAC308F0FB0F87BB32C1C3073E822B145C8`.
2. `logs/pucch_sr_wire_v2_20260916.log`: retained failed launcher attempt. The new short-SR guard passed, then the command incorrectly applied MATLAB `assert` to a function-based test suite object. This was a command/harness usage error, not a failed PHY assertion; no test assertion was changed to repair it.
3. `logs/pucch_sr_wire_v3_20260916.log`: exit 0 using the repository's focused-test dispatcher. Nine tests pass: short-SR contract, strict format matrix, fixed-format trial, active-power accounting, normalized transmit reference, resource-set selection, power-independent planning, receive-assignment equivalence across Formats 0-4, and nine power-resource/numerology vectors. SHA-256 `DE977E2CD918157FAABC8CE3139A972ADDFB35C365B85A895DA385FACF962602`.
4. `logs/pucch_format_policy_v2_20260916.log`: exit 0, six tests pass. Covers malformed/absent/false/global/duplicate permission rejection, mixed Format-2/3/4 isolation on TX and RX, unchanged combined component reception, short-SR contract, all 14 original reference cases, multi-user PRI authority and parameter catalog. SHA-256 `E1FBD1B4768E12D8C6F7B4988645CCEF0402FA6E42A9F1069E0C27CE074483FD`.
5. `logs/uci_wire_first_guards_20260916.log`: completed, exit 0, all 18 selected guards passed. Includes scenario/config, DL/UL/reference points, strict/proxy, scheduler, export/artifact checks and both required E2E guards. `testE2E_FastVsTruth` took 480.16 seconds; the three-seed `testE2E_TruthPacketSemanticCampaign` took 775.03 seconds. SHA-256 `3F4EF2D2B9A28296547C48560CCA663834C5B8712CF5DF5635F33F055AE00CFE`. All 19 recorded changed/new source hashes remained unchanged at completion. This receipt precedes the capacity patch.
6. `logs/uci_capacity_v1_20260916.log`: exit 1. The 15-vector coding-overhead/native-codec test, resource-allocation test, native CRC regression and parameter catalog passed. `testPUCCHPhase05/testPUCCHArtifactGeneration` failed on `UnverifiedPhaseEvidence`; both the test and `runPUCCHPhaseValidation.m` are unchanged from base `5d20e64d`. The publisher deliberately quarantines unverified independent-vector/DMRS/hopping/spatial artifacts, while the test expects 23 CSVs and 15 PNGs. Preserve the guard and failed log; replacement evidence producers and an aggregate gate are required, not a deleted assertion or manufactured artifacts. SHA-256 `F42E16308378A07AD15ECE9E452D344E1A71E6E70F2A593FE03CE3ED7E9F0A0F`.
7. `logs/uci_capacity_integration_v2_20260916.log`: exit 0, all ten selected tests passed: overhead, rate allocation with normal TX/independent RX/power binding, permission, combined component reception, Formats 0-4 RX equivalence, power-resource authority, planning without power, multi-user PRI, receiver hypotheses and catalog. SHA-256 `A1844B99E16BAE67559DB4A66AE13A1AABC32D7B02D000D5E7F19CC9B414A785`.
8. `logs/uci_capacity_edge_v3_20260916.log`: exit 0, six selected tests passed. Extends allocation coverage to actual waveform PRB/RE/coded capacity, configured-pool bounds, CSI+SR routing independent of PRI, over-capacity CSI rejection and explicit separate-Part-2 rejection. Also reruns short-SR contract, unchanged 14-case Format-0 reference, scenario config validation, active-power accounting and normalized transmit reference. SHA-256 `89D8F75114678267A3C18E1293FADF3FAC875ED25B24DCB6931B5CC922280C52`. Production source is unchanged from v2; only the allocation test was extended.

`git diff --check` passes. Mandatory unfiltered final-source `testAll`, remaining framework runner/matrix tests, detector qualification, integrated measurement/export acceptance and the 12 dB run remain due. The old suite's results cannot qualify this edited source. No additional full-suite queue was created while the old suite and candidate queue remain active.

### Next within the same work package

Finish whole-report CSI omission with its runtime consumer/disposition binding, then connect typed SR occasions/state to normal preparation. The single-sequence allocation primitive and TX/RX/power/carrier binding below are now implemented and under focused regression. Keep configured capacity distinct from selected allocation. The scheduler's configured reservation pool is a separate authority; it has not been changed. Do not count capacity-overflow rejection as implemented CSI omission or begin combined-runtime receiver integration against an unfinished report contract.

### Allocation design refinement before implementation (10:28 IST)

The existing planner always retains the configured resource width. Replacing this with unconditional minimum-PRB selection would be another error. The applicable procedure must be explicit:

| Payload/procedure | Required allocation behavior | Existing-code repair boundary |
| --- | --- | --- |
| HARQ, with or without SR, Formats 2/3 | Minimum legal PRBs when the rate criterion fits; retain the specified maximum-resource branch when it does not. Format 3 requires a legal transform width. | Extend `PUCCHResource` selection and share it between `PUCCHResourcePlan` and independent `PUCCHReceptionAssignment`; do not universally reject every nominal-rate overflow. |
| Single configured CSI report, optionally SR but no dynamic HARQ | Use its configured CSI resource; do not apply the dynamic-HARQ minimum-width rule indiscriminately. | `PUCCHResourcePlan` currently routes CSI+SR to decoded PRI because `csiOnly` excludes SR. Correct that procedure selection when normal SR is wired. Preserve CSI-only power/resource tests. |
| Dynamic HARQ plus wideband CSI, optionally SR | Apply the capacity/minimum-width procedure; on overflow select whole CSI reports by prescribed priority, recomputing CRC for each retained subset. | Selection must precede serialization/materialization. Never truncate serialized bits, silently enlarge resources, or increase power to preserve an over-capacity report. |
| CSI Part 2 | Part-2 coding/CRC and omission rules are separate. | Current transmitter flattens both sequences into one codeword. A combined-length CRC check cannot qualify this path. Keep the current normal wideband/no-Part-2 boundary explicit pending a separate repair. |

These distinctions follow TS 38.213 sections 9.2.3, 9.2.5.1 and 9.2.5.2 ([Release 18.8 specification](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf)).

Concrete implementation/test decisions:

1. Add explicit `max_code_rate` to format-owned YAML/catalog configuration and typed installed RRC; no hidden rate inferred from a passing capture. Bind carrier/grid configuration from resolved configuration, not a fabricated default carrier or transmitter payload.
2. Obtain candidate coded capacity from public `nrPUCCHIndices(...).G`, with actual modulation, DM-RS and spreading applicability. `UCIEncodingPlan` must expose total CRC/segmentation overhead rather than treating per-block `CRCBits` as the total. Check 11/12 and 19/20 payload transitions and segmentation boundaries independently.
3. Keep configured resource identity/maximum width and selected physical width separately traceable. `PUCCHConfigBuilder.materialize` already derives power bandwidth from `planned.Plan.Resource`; preserve its wrong-power-state rejection. The fixture/direct-assignment callers need planning before bandwidth binding, not silent overwriting of an inconsistent supplied power state.
4. Preserve `CoupledTruthRuntime`'s explicitly configured `reserveConfiguredPRBsFromPUSCH` pool (around lines 10756-10819). It reserves the union of configured PRBs/second hops and labels that provenance. Do not substitute UE-payload-dependent selected PRBs into gNB scheduling. Actual waveform/ownership and overlap checks still require the selected allocation.
5. Test TX/RX allocation equality from independent length hypotheses, configured CSI width preservation, CRC-driven width changes, legal Format-3 widths, maximum-resource HARQ behavior, whole-report CSI omission, and unchanged power/identity tamper guards. Do not start combined-runtime receiver integration while these contracts remain open.

At this checkpoint only the IDE audit was edited during the live guard batch. No production source, tests, queued revision, process authority, detector gate, or acceptance assertion was changed.

The development checkout's `logs/uci_wire_first_guards_20260916_source_binding.json` records SHA-256 hashes for all 17 then-changed tracked files and both then-new tests over base `5d20e64d`, captured at 05:00:47 UTC during the frozen-source batch. It is a changed-source binding, not a prelaunch or full-repository snapshot. Its terminal receipt records exit 0 and unchanged source, explicitly not full-suite qualification. The later capacity edits require their own evidence.

### Implemented allocation details (10:54 IST)

- `UCIEncodingPlan` retains per-block `CRCBits` and separately exposes total CRC, segmentation filler, information-plus-CRC numerator, and total code-block input bits. Fifteen declared boundary cases passed native encoding/decoding and CRC attachment checks, including 11/12, 19/20, 359/360, E=1087/1088 and 1012/1013 transitions. See [TS 38.212 sections 5.2.1 and 6.3.1.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf).
- `PUCCHResource.selectPRBAllocation` uses public `nrPUCCHIndices(...).G`, legal Format-3 transform widths and explicit procedure selection. HARQ's maximum-resource branch retains a visible failed nominal-rate criterion; CSI overflow returns no accepted allocation. It does not claim arbitrary A/E encoder feasibility or implement report omission.
- `PUCCHRRCContext` and `PUCCHConfigBuilder` bind installed rate and carrier geometry. `PUCCHResourcePlan` and `PUCCHReceptionAssignment` share the allocator; a mixed RX hypothesis must explicitly declare its gNB-owned procedure. TX/RX validate the actual carrier against the allocation. The static scheduler reservation pool is unchanged.
- The TDD rate 0.35 is an explicit allowed configuration choice, not a universal 3GPP rate or a fitted detector threshold. Its two-PRB/two-symbol resource has E=64; the diagnosed 12-bit combined payload plus six CRC bits uses 18/64. At this rate an 11-bit HARQ payload uses one PRB, while 12 bits need two. The power-bandwidth term follows that selected width.
- The generic Format-4 component fixture now declares six symbols instead of four so its existing 20-bit payload fits its declared 0.80 rate. The unchanged payload-recovery assertion passes; this is a corrected component allocation, not RF qualification. The mixed component test binds power after planning rather than silently repairing a stale supplied power state in production.
- No CSI report is silently removed. Normal omission/disposition, separate Part-2 coding and the previously listed runtime integration remain required. The historical impact helper's flattened Part-2 path is therefore not qualified by these tests.

The 11:01 checkpoint was reached at 10:59 with a concrete rate/CRC/allocation patch and terminal focused receipts, not complete UCI integration. `logs/uci_capacity_checkpoint_20260916_source_binding.json` binds all 20 changed tracked files and four new tests to base `5d20e64d` and the retained receipts. No commit, merge, push, deletion or assertion relaxation occurred. Required final-source full-suite/NR/E2E/framework validation remains outstanding; the quarantined artifact-generation failure must not be called a pass. Next work stays on report omission/disposition and normal SR wiring before combined-runtime reception.
