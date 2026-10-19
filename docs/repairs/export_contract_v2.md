# Main-codebase LLS evidence contract, version 2

This contract is **integrated into the main working tree** and applies to new exports, not to historical CSVs. It does not claim full NR, hardware, statistical, or end-to-end scenario qualification. The original dirty checkout is the baseline; `logs/lls_repair_consolidation_20261016/source_freeze.json` retains its revision and file hashes. The preserved `patch_receipt.json` describes the isolated patch before consolidation; it is historical evidence, not a current deployment flag.

## Coding

`CodingAccountingVersion=LDPCSelectionAccounting/v2`. All counts come from actual per-codeword layouts and rate-matching selection indices.

| Field | Definition |
|---|---|
| EncodedBits | Sum of post-inherent-puncturing encoder positions, N × C, across codewords; includes filler positions |
| InherentLDPCPuncturedBits | Sum of 2 × Zc × C; separate from circular-buffer exclusions |
| CodeBlockInputBits | Sum K × C |
| CBCRCBits | Applicable CB-CRC length × C, summed per codeword |
| SegmentationPaddingBits | Actual filler count; excludes TB CRC and CB CRC |
| SegmentationOverheadBits | CBCRCBits + SegmentationPaddingBits |
| RateMatchEligibleBits | Non-filler positions in each configured circular buffer |
| RateMatchUniqueSelectedBits | Distinct eligible positions actually selected, summed per CB/codeword |
| RateMatchRepetitionBits | Actual selected count minus unique-selected count |
| RateMatchPunctureBits | Legacy name: eligible buffer positions not selected; does NOT include inherent 2Z puncturing |
| RateMatchAccountingJSON | Compact per-CB accounting, not payload/sample vectors |

The rate-matching map now excludes encoder filler positions. The codeword itself is unchanged, but a position-aware HARQ consumer can change behavior because its old map was wrong. This is a production-behavior correction, not merely relabelling. `RateMatchedBits` retains the transmitter's G contract; on UCI-multiplexed PUSCH do not assume this equals UL-SCH-only selected bits. Use the per-codeword accounting and UCI allocation together. Full UCI/coding reconciliation remains an acceptance item.

## Scheduler candidates

`CandidateAccountingVersion=SchedulerCandidate/v2`: `ProbeTBSBits` and `ProbeRate_bps` describe the allocation used for PF comparison. `FinalPRBCount`, `FinalTBSBits`, and `FinalRate_bps` describe the finalized allocation only. `PFMetricBasis` and `RateNormalizationDuration_s` retain the metric's meaning and denominator. Unselected candidates have no invented final allocation. Legacy `InstantRate` now has the same final-allocation scope as legacy `EstimatedTBS`; PF ranking is unchanged.

## Receiver availability and packet timing

`CoupledTruthRuntime` now carries validated receive timing into the HARQ attempt
timeline and into first-success SDU delivery. `DeliveryTime_s` uses
`DataDecodeAvailableAtSample / DataReceiveSampleRateHz`, not the nominal slot end.
`DeliveryAvailableAtSample`, `DeliverySampleRateHz`, and
`DataReceiveTimingEvidenceJSON` retain the source. `DeliveryCanonicalSlot` remains
the data-attempt attribution; `DeliveryAvailableCanonicalSlot` identifies the
one-based availability slot on the zero-origin physical sample clock.

`NominalDataSlotEndTime_s` and `NominalHARQFeedbackSlotStartTime_s` are explicitly
nominal. The legacy `HARQFeedbackTime_s` is a slot-start compatibility field, not
measured ACK availability. Actual UCI completion remains separately receiver-owned.
The receive contract's `ProcessingBudgetIncluded=false` is retained: these fields
do not assert a calibrated hardware decoder latency or include CPU elapsed time.
Shared-waveform packet delivery rejects missing receive timing. Nonshared legacy
fixtures retain slot-end attribution only with
`nominal_data_slot_end_legacy_nonshared_not_measured` authority.

## Exact resource-set denominators

`ResourceSets/v2` counts unique carrier-plane RE, never antenna-port multiplicity. `GrossAllocationRE=12*PRBCount*allocated_symbol_count`; `PilotOccupiedBaseRE` is the union of DMRS and PTRS locations. `MappedDataBaseRE` excludes PT-RS puncture locations even when a transform-precoded port map includes them. `NonDataOverGrossFraction=(gross-data)/gross`; `PilotOverGrossFraction=pilots/gross`; `PilotOverDataPlusPilotFraction=pilots/union(data,pilots)`. `UnoccupiedByThisChannelRE` is gross minus this channel's data/pilot union. It is **not evidence that another signal or transmitter is absent**. The legacy RSOverheadFraction remains the data-plus-pilot definition; TBS estimation inputs remain separate.

## Receiver diagnostic definitions

`DecisionResidualSymbolPower_dB=10log10(mean(abs(eq-hardDecision(eq)).^2))` on the retained equalized-symbol plane. It includes decision errors, channel-estimation error, noise and RF effects. It is **not measured external interference, dBm, or independent inter-layer leakage**. The exported error/reference energies and compared-sample count identify its population. A zero residual legitimately gives negative infinity; do not convert that into a missing or arbitrary finite measurement.

`HestCoarseReconstructionErrorRatio_dB` is the error-energy/reference-energy ratio between Hest and its coarse-grid linear reconstruction (the existing stride-6 subcarrier/stride-2 symbol diagnostic). `HestMagnitudeStd_dB` is the standard deviation of the existing floored channel-magnitude dB diagnostic. Neither is a measured throughput loss or a calibrated sensitivity. The original names remain compatibility aliases; updated primary plot consumers use the precise names. Clean reference symbols are scoring-only and do not replace receiver hard decisions.

## Availability

Sentinels such as `not_recorded_*`, `not_emitted_*`, `unavailable_*`, missing strings, and NaN do not establish availability. A valid numeric zero does. Descriptive PMI type/codebook fields are not scalar PMI evidence.

The scalar PMI and matrix identities are separate: a valid `AppliedPrecoderMatrixSHA256` with no scalar PMI gives `AppliedPrecoderScalarPMIStatus=not_applicable_explicit_matrix`; it does not fabricate PMI zero. `AppliedPrecoderMatrixStatus` describes hash availability, not a new proof of matrix application. SINR availability needs its numeric value and, when the definition column is present, its actual definition. This patch repairs known contradictions, not every possible measurement schema.

## RF coverage

TX and RX configured, executed and applied counts have separate owners. Compact metadata-only publication now retains the same counts as full RF publication. A missing/time-varying count is NaN, not zero. `StageCountIntervals` and `AppliedFlagCoverage` identify clipped execution intervals and any/all segment coverage. These flags describe operator execution on segments, not proof that every sample changed. They cannot qualify a whole receive window by themselves.

## Mobility and power

The physical mobility state has an independent monotonic clock; scheduling cursors do not own trajectory evolution. `PositionValidAtTime_s`, `PositionValidAtSample`, `PositionSnapshotAtSample`, `PositionSampleRateHz`, `MobilityStateVersion`, `PositionSource`, and `VelocityReferenceFrame` distinguish geometry validity from a delayed receiver event. Sample values require an actual shared waveform clock. Late measurements enrich an existing row without overwriting its retained geometry and associated model-power snapshot.

`ServingPower/v2` separates `ModelPredictedRxPower_dBm` from waveform measurements. In normalized/fixed-reference mode the legacy `RxPower_dBm` is unavailable. In explicitly thermal-noise/pathloss mode its compatibility value is labelled **model link budget**, not measured RX IQ. The energy exporter no longer promotes normalized CSI-RSRP or per-RE RSRP into total RX dBm. Full absolute calibration and endpoint-time energy integration remain unqualified.

## Identities and populations

`TransportIdentity/v2`: `LogicalTBID`/`TBId` are strings copied from the existing HARQ TB context; `TransmissionAttemptID` is the frozen grant context ID. Retransmissions retain logical TB identity and have distinct attempt identity. The constellation's old numeric TBId is now `TrialOrdinal`, which must not be used as a cross-table TB join. `tb_id` is the same string alias. Missing context stays missing. Session/configuration epochs and all packet joins are not yet comprehensively repaired.

New-data preparation now originates an explicitly namespaced `logical_tb:` ID
before payload generation when no logical ID was already supplied. Existing
logical IDs remain unchanged. Reservation and received delivery cannot originate
an ID or substitute a MAC SDU, MAC PDU, or current grant ID. All populated logical
aliases, including the retained HARQ TB context, must agree.

SDU reception joins direction, logical UE index and logical TB, and validates
the retained radio identity, cell, HARQ process and available NDI epoch against
the frozen received grant. The shared TX/RX validator also compares the logical
TB and retained epoch. Two legacy inputs both lacking an epoch do not establish
epoch qualification; this is not a default epoch of zero.

`DeliveryEvidenceMode` distinguishes `CRC_CONFIRMED_PACKET_MAPPING` from
`SAME_WAVEFORM_PAYLOAD_VERIFIED`. It names the configured evidence contract,
not a success flag. Only actual reception sets `DeliverySuccess`, and only
verified protocol bytes may set application delivery/reassembly. Metadata-only
packet association cannot become application goodput. First-success sample
timing is retained independently of the HARQ feedback delivery clock.

First-success protocol proof (`ProtocolDecoded*`, `ProtocolReceiverEvidenceSource`,
`ProtocolDeliveryStatus`) and delivery timestamps are not overwritten by later
duplicate or failed attempts. `LastAttemptProtocolDeliveryStatus` and the five
`LastAttemptProtocolDecoded*`/`LastAttemptProtocolReceiverEvidenceSource` fields
describe the latest callback instead. Duplicate rejection does not constitute a
fresh byte comparison: its latest-attempt count/hash/source remain empty and
its exact-match flag is false. `TBCrcPass`, `LastRV` and `LastAttemptSlot` retain
latest-attempt semantics; they are not first-success fields.

Application completion joins packet/application ID, logical UE and direction.
Protocol mode requires gap-free byte-aligned fragment coverage, distinct fragment
identities, retained decoder MAC/RLC hashes matching the encoded binding, and
causal first-success timestamps. CRC-only metadata mode remains insufficient.
The two-TB noiseless PDSCH regression verifies this reducer boundary; it is not
a complete shared-radio loss/reordering campaign or statistical qualification.

`HARQAttemptCountDefinition=unique_receiver_completed_TB_attempts_not_feedback_or_fragment_count`
defines the reconciled application and SDU counters. Production refresh counts
distinct received attempt IDs through their UE/direction/TB/process/NDI-epoch
binding, independently of application completion and protocol enablement. One
TB carrying multiple segments contributes once to its application's count.
Exact duplicate timeline observations do not add attempts; conflicting evidence
or orphan segments reject. `HARQAttemptCountStatus` identifies reconciliation
versus missing source evidence. A known empty current timeline has zero completed
receiver attempts; a missing timeline yields NaN, not a manufactured zero.
Started transmissions awaiting RX, feedback events and application-delivered bits
are separate populations. No bit counters or first-success proof are changed.

Public live and final exports now use `publishPacketDeliveryLedgers` for the
canonical attempt journal and packet views. The actual current HARQ timeline
is written before the derived counters, even when no packet table exists.
A known-empty timeline publishes its typed empty table; a missing timeline is
not fabricated. `CoupledTruthRuntime` no longer has a separate competing final
writer. Original retained run files are not overwritten by this repair.

The separate `packet_bit_ranges/v1` contract now partitions offered bits into:

- `UnscheduledBits` (the explicitly named alias of legacy `RemainingBits`);
- `ReservedInFlightBits`;
- `CRCConfirmedMappedBits` (not application delivery);
- `BitVerifiedPendingReassemblyBits`;
- `CompletedApplicationBits`;
- `HARQReleasedUndeliveredBits`;
- `UnresolvedReservedBits` (insufficient receiver/lifecycle evidence).

These disjoint counters sum to `OfferedBits`; `BitConservationErrorBits` must
be zero. `HARQRetryLimitDroppedBits` and `HARQObservedACKWithoutDecodeBits`
are subsets of released-undelivered bits, not extra contributions to the sum.
A transmitter release does not establish a final application-layer drop.
Every committed segment has an exclusive `[ApplicationRangeStartBit,
ApplicationRangeEndBitExclusive)` range. Metadata-mode ranges come from the
committed packet mapping, not decoded application bytes. Same-waveform ranges
must match the frozen protocol offsets and exact decoder MAC/RLC proof.
Retransmissions reuse the range; first successful delivery survives a later
failed attempt. A missing completed receiver outcome cannot become a measured
drop just because the transmitter observed ACK/NACK/DTX.

This reducer is called after data reception and by both public runtime live and
final writers through `publishPacketDeliveryLedgers`. Late feedback-only release
therefore refreshes the packet snapshot even if no later data decode occurs.
The public-writer before test reproduces omitted live ledgers; the repaired test
checks both DL/UL and live/final CSVs. Declared-MAC tests and independent CSV
arithmetic audits pass. Full shared-radio cancellation/drop/reassembly qualification
and historical-file correction are not implied.

The separate runtime HARQ process summary now also distinguishes
`TransportAttemptsObserved` from `FramesObserved`: four attempts within one frame
are four attempts and one frame. Available run/execution/sweep identities scope
frame uniqueness; missing frame evidence remains NaN. This does not change CRC
or logical UCI association rates, and CRC success is not an observed ACK.

`HARQObservationPopulation/v2`: `FramesObserved` counts distinct frame keys including available sweep/run scope; `TransportAttemptsObserved` counts trial rows. `HARQPhysicalPopulations/v2` separately reports logical feedback associations/ACK rate and unique prepared physical PUCCH occasions/information bits. Receiver-only observations do not count as transmissions. Duplicate physical identities with conflicting widths are rejected. This is not a count of coded UCI bits or PUSCH-UCI physical transmissions.

## Timing and bootstrap

### Unique transport goodput

`TransportGoodput/v1` is a receiver-completion contract, separate from
application delivery and transmitter ACK state. `creditTransportGoodput`
credits each logical TB's actual payload at its first CRC success. Later CRC
successes of that same TB contribute zero new payload, even after lost ACK.
Logical UE/direction and declared run/sweep/session/NDI-generation keys scope
identity; an attempt ID, mutable RNTI or row index is not a TB generation.
Missing identity/CRC/size remains unknown rather than reconstructed from a rate.

Shared runtime `GoodBits` and `Goodput_Mbps` now use that unique credit;
`DecodedAttemptBits` and `DecodedAttemptGoodput_Mbps` preserve the original
per-attempt quantities. `UniqueDeliveredTBBits`, `FirstSuccessfulTBDelivery`,
`TransportGoodputKey`, status and definition retain the attribution evidence.
`transportGoodputBits` verifies stored credit against the original CRC, TBS and
scope without re-crediting a duplicate in a sliced table. Conflicting TBS aliases,
contradictory CRC/identity, altered credit and duplicate first-credit rows reject.

The symbol export keeps both real allocations as scheduled bits. Its legacy
`GoodDLBits`/`GoodULBits` are explicitly decoded-attempt bits;
`UniqueDeliveredDLTBBits`/`UniqueDeliveredULTBBits` supply the goodput rates.
They are uniformly apportioned over the actual grant symbols, not symbol-level
CRC observations. Independent directions and UEs do not share credit. No
application payload is inferred from the TB's CRC success. Standalone link
runners and older artifacts retain their original semantics unless explicitly
bound to this contract; this is not a blanket historical-data migration.

The energy exporter now also consumes `TransportGoodput/v1` for its delivered
bit denominator. `energy_timeline_trace.SuccessfulBits` is unique receiver
delivery credit, not the TB size of every row whose generic `Status` is PASS.
The two endpoint rows retain `TransportGoodputKey` and `TransportGoodputStatus`;
the summary counts one transmitting endpoint only. Control bits contribute
zero. An unknown CRC/TB identity propagates unknown, not fabricated delivery.
The independent fixed-link Monte Carlo producer has a separate explicit
no-HARQ execution hierarchy: point, drop, trial and seed. That hierarchy can
identify an independently generated TB even without a scheduler UE ID; an
ordinary connected attempt ordinal cannot do so.

This denominator repair does **not** qualify the current energy numerator.
Per-channel whole-slot model energies must not be interpreted as a completed
physical-endpoint integral: overlapping observations still require a single
endpoint-owned state/resource journal and consistent TX-power authority.
Configuration-derived circuit watts remain an engineering model, not
measured hardware power or a 3GPP-mandated power value.

`SlotSymbolRoles/v2` preserves the authoritative resolved symbol calendar. `SymbolRolesJSON` is a zero-based array of DL, UL, GUARD, FLEXIBLE, UNUSED or RESERVED. Flexible symbols are not automatically guard or available scheduling resources. Explicit counts reconcile all symbols; unknown roles reject. These fields describe calendar ownership, not measured occupancy.

Bootstrap is recomputed only from the **same frozen row's** adaptive/scheduled/applied evidence after reconciliation. Newer CSI state does not rewrite old grants. Missing bootstrap feedback does not remove a real failed PHY attempt from BLER.

`AdaptationDeliveryStatus` identifies acceptance of a new CSI/SRS adaptation
event versus duplicate, older-source or backward-delivery rejection. A received
report may be physically decoded yet ineligible to update current scheduler
state. Rejected callbacks do not increment rank confirmation, refresh feedback
age, change ILLA, or update HARQ-owned OLLA. Distinct report identities remain
distinct; the source/occasion key is used when a report ID is not supplied.
The two-report rank-increase confirmation is configured simulator policy, not
a universal NR requirement.

`AccessTiming/v2` preserves the legacy inclusive-slot extent in `ProcedureDelay_ms`/`AccessDelay_ms`, with explicit `ProcedureIntervalStart_s` and `ProcedureIntervalEndExclusive_s`. `EventElapsed_ms` is separately the difference of `ProcedureStartTime_s` and `ProcedureEndTime_s`. Neither is relabelled decoder-availability latency. The actual decoder-availability handoff is verified in bounded physical DL/UL packet fixtures; multi-TB protocol-reassembly qualification remains open.

## Migration and execution

`control_evm_pairs/v1`: new shared CSI-RS trials retain complete paired samples
in `air_interface/mat/control_evm/<content-sha256>.mat`. The trial holds the
relative path, file/content checksums, contract and exact sample count; its
legacy `ControlEVMSamplesJSON` column is empty, not a missing-measurement flag.
The MAT payload preserves every original numeric array, shape, class, port,
reference plane and trial identity. Non-persisting components retain the
legacy inline payload explicitly. The sample CSV remains unchanged, including
all configured sweep identities and raw gain-inclusive error definitions.
The exporter verifies detail-file hashes even on cached publications; missing,
altered or cross-trial references fail rather than use a substitute capture.
Legacy inline rows remain readable, but a row cannot declare both authorities.

The 273-PRB/64-port storage fixture retained all 559104 paired values exactly:
90367383 bytes in the old in-memory row versus 5417 in the compact row and
4493922 in its MAT file. This is a storage measurement, not full-run peak RAM
or an end-to-end speedup claim. The eight-point CSV identity test uses repeated
fixture observations to test serialization, not eight measured PHY conditions.

Do not run historical sanitizers against retained user results. Consumers must select a contract/version, keep string IDs, and use precisely named metrics. Old artifacts remain evidence under their original schema. A next-run manifest is configuration resolution, **not permission to run**. The approved 100-slot execution still awaits the remaining repair gates. No full scenario, testAll, broad statistical qualification or Keysight hardware playback has been executed by this repair.
