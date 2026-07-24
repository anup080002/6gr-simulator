# Codex implementation prompt 01 — Frame, grid, numerology, duplexing, BWP/CC timing

You are working directly in the root of the **6GR MATLAB simulator** repository. This is an **implementation task**, not an audit, review, design memo, or standards-claim exercise.

Your job is to **modify the MATLAB source, migrate affected configuration, add executable tests, run them, generate the required CSV and PNG artifacts, verify those artifacts, and keep fixing until all mandatory checks pass**.

## Scope

Fix only the frame/grid/numerology/duplexing layer and the minimum interfaces it requires:

1. NR numerology and cyclic-prefix support.
2. Frequency-range and transmission-bandwidth configuration.
3. OFDM FFT/sample-rate/CP resolution.
4. TDD common and dedicated symbol ownership.
5. FDD DL/UL frame separation.
6. Independent PDCCH/PDSCH/PUSCH time/frequency allocations.
7. SSB case/timing resolution shared by all users.
8. PRACH occasion timing resolution shared by all users.
9. K0/K1/K2 and processing-time legality.
10. Multi-BWP frame/grid state and switching.
11. Multi-component-carrier state and cross-carrier timing.
12. Deterministic CSV/PNG diagnostics and tests for all of the above.

Do **not** spend time on truth contracts, publication wording, security, WebGUI, documentation marketing, channel models, RF impairments, LDPC/polar internals, CSI quantization, or upper-layer protocol breadth. Only touch another domain where a clean frame/timing interface is technically necessary.

## Normative baseline

Pin this phase to these versions unless the repository already pins a later Release-18 maintenance version, in which case use the repository version consistently and state it in the test report:

- 3GPP TS 38.211 V18.8.0: clauses 4.1–4.5 and the SSB/PRACH resource clauses used by the resolvers.
- 3GPP TS 38.213 V18.8.0: clause 11.1 and the K1/processing-time/channel-availability clauses used by timing validation.
- 3GPP TS 38.214 V18.8.0: PDSCH/PUSCH time-domain resource allocation and K0/K2 procedures.
- 3GPP TS 38.104 V18.8.0: tables 5.3.2-1, 5.3.2-2 and 5.3.2-3 for gNB transmission-bandwidth configuration, plus tables 5.3.3-1, 5.3.3-2 and 5.3.3-2a for minimum guardband.
- 3GPP TS 38.101-1/-2 V18.x: UE-side supported bandwidth/SCS constraints where the simulator models UE RF bandwidth capability.
- 3GPP TS 38.331 V18.x: `tdd-UL-DL-ConfigurationCommon`, `tdd-UL-DL-ConfigurationDedicated`, BWP and serving-cell configuration structures.

The generic 38.211 numerology set and the carrier/BWP transmission capability matrix are different concepts. Do not accept a carrier configuration merely because its SCS is a valid generic numerology.

## Input vector files supplied with this prompt

Copy these files into `tests/vectors/frame_grid/` and use them as executable test inputs rather than rewriting their values in test code:

- `frame_numerology_test_vectors.csv`
- `frame_carrier_grid_test_vectors.csv`
- `frame_tdd_test_vectors.csv`
- `frame_allocation_test_vectors.csv`
- `desired_frame_csv_contract.csv`
- `desired_frame_image_contract.csv`
- `verify_frame_artifacts.py`

The vector files are mandatory. Extend them only when a specification case is missing; do not weaken or delete rows to make the implementation pass.

The pack also contains four table-derived **golden expected-output examples** for the supplied limited vectors:

- `expected_frame_numerology_matrix.csv`
- `expected_carrier_grid_matrix.csv`
- `expected_slot_symbol_ownership.csv`
- `expected_allocation_legality.csv`

Use these as deterministic expected results for the supplied rows. Do not copy them into the simulator output and call the test complete: the MATLAB tests must invoke the production resolvers, serialize their actual results, and compare field by field against these files. A mismatch must fail the test.

## Current code defects that must be removed

The following source locations currently encode non-normative shortcuts or conflicting resolution paths:

- `+sixgr/+phy/FrameStructureEngine.m`
  - `SCSKHzSanity` accepts any positive `15*2^mu` value.
  - `lookupNRB` is incomplete and merges all FR2 behavior.
  - a failed table lookup accepts configured `NSizeGrid`.
  - `defaultFFTSize` uses `nextpow2(12*NRB)`.
  - `expandTDDPattern` converts `F` to `D`.
  - a missing special-slot split becomes 12/1/1.
  - CORESET duration is clamped and PDSCH is placed over the slot remainder.
  - SSB cases are approximate and incomplete.
  - PRACH configuration-index handling is sparse and defaults to A1-like behavior.
  - FDD is represented by a token `F`, colliding with the meaning of a flexible TDD symbol.
- `+sixgr/+util/resolveTDDSlotPartition.m`
  - catches all frame-engine failures and silently executes a second legacy resolver.
  - strips `F` and uses `S` as a synthetic special-slot token.
- `+sixgr/+phy/+grid/nrNumerologyTable.m`
  - includes only mu 0–4 with normal CP.
- `+sixgr/+config/normalizeConfig.m`
  - independently re-derives numerology and applies a next-power-of-two FFT fallback.
- `+sixgr/+config/validateConfig.m`
  - validates only a D/U/S compact pattern and does not validate the complete configuration matrix.
- `+sixgr/+lls6g/buildInternalConfig.m`
  - performs an early numerology derivation with 14 symbols per slot.
  - installs a conflicting 7/0/7 special-slot default.
  - later calls `FrameStructureEngine` and overwrites explicit PDSCH/PUSCH allocations.
  - represents BWP as a copied surface rather than canonical per-BWP state.
- `+sixgr/+phy/+waveform/resolveOFDMWindowing.m`
  - applies a 2.5%-of-NFFT default when windowing is not configured.
- `+sixgr/+phy/+dl/SSB_Tx.m`
  - coerces invalid `Lmax` and catches waveform errors to clamp `NSizeGrid` and retry.
- `tests/testFrameStructureEngine.m`
  - currently asserts that PDSCH must be automatically moved after CORESET, which is the behavior to remove.

Do not preserve these behaviors in the strict frame path. A narrowly isolated compatibility adapter may remain under `+sixgr/+compat/`, but none of the new tests or normal simulator scenarios may use it.

---

# Required implementation architecture

Keep `sixgr.phy.FrameStructureEngine` as a public facade if existing callers depend on it, but make it delegate to one canonical implementation under a new package such as:

```text
+sixgr/+phy/+frame/
    NumerologyCatalog.m
    FrequencyRangeResolver.m
    TransmissionBandwidthCatalog.m
    CarrierGridConfig.m
    OFDMSamplingResolver.m
    TDDCommonConfig.m
    TDDDedicatedConfig.m
    SlotFormatResolver.m
    FlexibleSymbolAllocator.m
    ResourceAllocationValidator.m
    SSBTimingResolver.m
    PRACHOccasionResolver.m
    TimingRelationEngine.m
    BWPConfig.m
    BWPStateMachine.m
    ComponentCarrierConfig.m
    AbsoluteTime.m
    exportFrameGridArtifacts.m
```

The exact file names may follow repository conventions, but the following separation is mandatory:

- **Configured values** are parsed once.
- **Resolved frame/grid state** is created once and is immutable for a configuration epoch.
- **Runtime flexible-symbol decisions** are separate from the common/dedicated TDD map.
- **Channel allocations** are separate from symbol availability.
- **Per-BWP and per-CC state** is explicit; no global scalar silently represents every BWP/carrier.
- **All timing procedures** use one absolute-time representation and one timing engine.

Use typed MATLAB value classes, validated structs, or a combination consistent with the repository. Avoid loose nested structs for state that has invariants.

Use zero-based NR symbol and slot indices in all PHY-facing objects. Convert to one-based MATLAB indices only at array access boundaries. Include the index convention in every exported CSV.

---

# Work item 1 — Complete numerology and cyclic-prefix implementation

## Current problem

`FrameStructureEngine.SCSKHzSanity` accepts any mathematically valid `15*2^mu`, while `nrNumerologyTable` stops at mu 4 and represents only normal CP. This permits unsupported role/frequency-range combinations and omits valid mu 5/6 timing.

## Implement

Create a canonical numerology catalog with, at minimum:

```text
mu   SCS kHz   normal CP symbols/slot   slots/subframe   slots/frame
0       15              14                    1              10
1       30              14                    2              20
2       60              14                    4              40
3      120              14                    8              80
4      240              14                   16             160
5      480              14                   32             320
6      960              14                   64             640
```

Extended CP is valid only for mu 2 / 60 kHz and has 12 symbols per slot, 4 slots per subframe, and 40 slots per frame.

Expose a method similar to:

```matlab
num = NumerologyCatalog.resolve(scsKHz, cyclicPrefix, role, frequencyRange)
```

where `role` distinguishes at least:

- carrier transmission grid;
- DL/UL BWP;
- SSB;
- PRACH;
- generic waveform test.

A valid generic 38.211 numerology is not automatically a valid carrier transmission SCS. Apply the role/frequency-range capability matrix after resolving mu.

Reject:

- non-finite, zero or negative SCS;
- SCS values not present in the pinned 38.211 table;
- extended CP for any value except 60 kHz;
- a carrier/BWP SCS that is not valid for the selected frequency range and channel bandwidth;
- a configuration that depends on rounding `log2(SCS/15)`.

## Replace duplicated logic

Delete or delegate all independent numerology calculations in:

- `normalizeConfig.m`;
- `buildInternalConfig.m`;
- `nrNumerologyTable.m`;
- timing helpers that infer slots per frame locally.

Every caller must receive the same resolved object.

## Tests

Add `tests/testFrameNumerologyCatalog.m` and execute every row of `frame_numerology_test_vectors.csv`.

For each valid row, assert exact mu, SCS, CP, symbols per slot, slots per subframe, slots per frame, and slot duration. For each invalid row, assert the exact error identifier.

Also assert that the following existing code paths return identical values:

- direct catalog resolution;
- `FrameStructureEngine` facade;
- `normalizeConfig`;
- `buildInternalConfig`;
- `sixgr.time.slotDurationSec`.

No path may silently substitute mu 0 or normal CP.

---

# Work item 2 — Complete frequency-range and transmission-bandwidth configuration

## Current problem

The current code has one `FR2` bucket, calls 52.6–71 GHz `FR3`, omits valid table entries, includes inappropriate 240 kHz carrier rows, and accepts configured `NSizeGrid` after lookup failure.

## Implement

Use explicit values:

```text
FR1
FR2-1
FR2-2
```

For the Release-18 NR baseline, do not return `FR3` from the NR carrier resolver. A research frequency outside the supported NR ranges must use a separate custom-carrier path and must not enter the standard NR resolver.

Build the complete gNB transmission-bandwidth and minimum-guardband catalog from TS 38.104 tables 5.3.2-1, 5.3.2-2, 5.3.2-3, 5.3.3-1, 5.3.3-2 and 5.3.3-2a. The supplied `frame_carrier_grid_test_vectors.csv` contains every transmission-bandwidth table cell, including N/A combinations, and the corresponding minimum guardband for every valid cell. Resolve all 71 rows exactly.

Create a role-aware API similar to:

```matlab
result = TransmissionBandwidthCatalog.resolve( ...
    "Role", "gNB", ...
    "FrequencyRange", "FR1", ...
    "ChannelBandwidthMHz", 100, ...
    "SubcarrierSpacingKHz", 30)
```

Return at least:

- expected `N_RB`;
- valid/invalid status;
- frequency-range subtype;
- occupied subcarrier count;
- occupied bandwidth;
- exact minimum low/high guardband from the pinned table;
- source table and row key.

Distinguish:

- channel bandwidth;
- transmission bandwidth configuration `N_RB`;
- active BWP size;
- `NStartGrid` relative to Point A;
- `NStartBWP` and `NSizeBWP`.

Do not force a BWP to consume the full transmission bandwidth configuration.

In the standard NR path:

- a configured `NSizeGrid` must equal the table result when it is supplied as a consistency assertion;
- a mismatch throws `sixgr:phy:frame:ConfiguredGridMismatch`;
- an N/A bandwidth/SCS pair throws `sixgr:phy:frame:UnsupportedBandwidthSCSCombination`;
- missing center frequency and missing explicit frequency range is an error;
- no table failure may be repaired by using the requested grid size.

An explicit custom-grid research mode may accept arbitrary grids, but it must use a separate constructor/API and must not be selected automatically.

## Tests

Add `tests/testTransmissionBandwidthCatalog.m`.

Execute every row of `frame_carrier_grid_test_vectors.csv`. For valid rows, assert exact `N_RB` and exact minimum guardband from the corresponding 38.104 table. For invalid rows, assert the exact error ID and absence of a fabricated guardband. Add explicit tests for:

- 3 MHz / 15 kHz / FR1 = 15 RB;
- 35 MHz / 30 kHz / FR1 = 92 RB;
- 45 MHz / 60 kHz / FR1 = 58 RB;
- 100 MHz / 30 kHz / FR1 = 273 RB;
- 400 MHz / 120 kHz / FR2-1 = 264 RB;
- 400 MHz / 480 kHz / FR2-2 = 66 RB;
- 2000 MHz / 960 kHz / FR2-2 = 148 RB;
- 400 MHz / 60 kHz / FR2-1 is invalid;
- 100 MHz / 480 kHz / FR2-2 is invalid;
- 60 GHz resolves to FR2-2, never FR3;
- configured `NSizeGrid` mismatch fails rather than changing the carrier.

---

# Work item 3 — Replace heuristic FFT/sample-rate selection with one validated OFDM policy

## Current problem

`defaultFFTSize` and `normalizeConfig` choose the next power of two above occupied subcarriers. This is an implementation heuristic and diverges from MATLAB 5G Toolbox waveform configuration and CP lengths.

## Implement

Create one `OFDMSamplingResolver` used by all DL, UL, SSB and reference-signal waveform paths.

For standard NR waveform operation:

1. Construct the canonical `nrCarrierConfig` or equivalent carrier object from the resolved carrier/BWP configuration.
2. Obtain NFFT, sample rate, CP lengths, symbol lengths, and samples per slot from `nrOFDMInfo` using the installed MATLAB 5G Toolbox release.
3. Allow an explicit sample rate or NFFT only when MATLAB's OFDM API accepts it and all invariants below pass.
4. If 5G Toolbox functionality required by this simulator is unavailable, throw a clear dependency error; do not synthesize a next-power-of-two fallback in the strict waveform path.

Validate:

- `Nfft >= 12*NSizeGrid`;
- sample rate equals `Nfft*SCS` for the selected waveform convention;
- CP length vector has the expected number of symbols;
- the generated waveform contains the exact expected number of samples per slot;
- occupied bandwidth plus guardbands fits the channel bandwidth;
- no active subcarrier aliases at the selected sample rate;
- OFDM modulation followed by demodulation with no channel recovers the resource grid.

The resolved object must include the source `nrOFDMInfo` or `explicit_validated`, not `nextpow2`.

## Tests

Add `tests/testOFDMSamplingResolver.m`.

For every valid carrier vector supported by the installed toolbox:

- generate a deterministic complex resource grid with at least one nonzero RE at each occupied band edge and several interior REs;
- OFDM-modulate and demodulate with no channel, CFO, phase noise or timing offset;
- assert dimensions and CP lengths against `nrOFDMInfo`;
- assert NMSE <= `1e-12` in double precision;
- assert EVM <= `1e-4` percent;
- assert no nonzero sample/windowing is applied unless explicitly requested;
- export one row per case to `ofdm_roundtrip.csv`.

If a valid specification vector is not supported by the installed MATLAB release, mark the MATLAB/toolbox version as a blocking dependency and do not silently omit the row.

---

# Work item 4 — Implement true symbol-level TDD common configuration

## Current problem

The simulator uses a compact slot token pattern, converts `F` to `D`, and models a synthetic `S` slot with one global DL/guard/UL split. This is not the 38.213 common slot-format procedure.

## Implement

Represent the TDD common configuration using RRC-equivalent fields:

```text
referenceSubcarrierSpacing
pattern1:
    dl-UL-TransmissionPeriodicity
    nrofDownlinkSlots
    nrofDownlinkSymbols
    nrofUplinkSlots
    nrofUplinkSymbols
optional pattern2 with the same fields
```

Resolve a **per-symbol common direction array** with exactly these values:

```text
D = fixed downlink
U = fixed uplink
F = flexible
```

Do not introduce `S` as a direction. A guard interval is a runtime use of flexible symbols, not a fourth common slot-format symbol.

For each pattern:

- compute the number of reference-SCS slots from periodicity;
- place full DL slots first;
- place the configured DL symbols immediately after the full DL slots;
- place full UL slots last;
- place the configured UL symbols immediately before the full UL slots;
- leave every remaining symbol flexible;
- require configured counts to fit the period;
- require pattern1 plus pattern2 period to divide 20 ms when both exist;
- align the first period to the first symbol of an even frame as required by the procedure;
- map the reference-SCS format to every active BWP SCS without rounding time.

Keep two arrays:

```text
CommonDirection[absoluteSymbol]
ResolvedDirection[absoluteSymbol]
```

Initially, `ResolvedDirection` for a common flexible symbol is `UNRESOLVED_FLEX`. The scheduler/allocator may later resolve it to DL, UL, GUARD or UNUSED. It must never overwrite `CommonDirection`.

## Configuration migration

Add canonical YAML fields equivalent to the RRC structure. Migrate the simulator scenarios used by tests.

For old compact patterns:

- `D`, `U`, and `F` may be accepted by an explicit compatibility parser;
- a compact `S` token is not accepted in the new standard path;
- there is no default `DDDSU` pattern;
- a TDD configuration without a common pattern is an error.

Delete `strrep(tokens,"F","D")` and any equivalent transformation.

## Tests

Add:

- `tests/testTDDCommonPattern.m`
- `tests/testTDDMultiNumerologyExpansion.m`

Execute all rows of `frame_tdd_test_vectors.csv` that do not contain a dedicated override. Compare every slot and every symbol to `ExpectedSlotSymbolMap`.

Also test period continuity across:

- a 10 ms frame boundary;
- an even-to-odd and odd-to-even frame transition;
- pattern1+pattern2 repetition;
- reference SCS lower than active BWP SCS;
- normal and extended CP.

The test must fail if any flexible symbol becomes DL before an explicit runtime decision.

---

# Work item 5 — Implement true TDD dedicated overrides and flexible-symbol allocation

## Current problem

There is no exact dedicated-configuration procedure. The current global special-slot split can change fixed common symbols and cannot represent per-slot overrides.

## Implement

Represent `tdd-UL-DL-ConfigurationDedicated` with:

- slot index in the common period;
- `allDownlink`, `allUplink`, or `explicit`;
- for `explicit`, first downlink symbol count and last uplink symbol count.

Apply dedicated configuration **only to symbols that are flexible in the common map**. Reject a dedicated configuration that would indicate a common fixed-D symbol as UL or a common fixed-U symbol as DL.

Then implement `FlexibleSymbolAllocator` that receives requested runtime allocations and resolves remaining flexible symbols to:

```text
DL
UL
GUARD
UNUSED
```

Rules:

- fixed D and fixed U symbols cannot be changed;
- two conflicting allocations cannot resolve the same flexible symbol in opposite directions;
- DL-to-UL and UL-to-DL transitions must have the configured/derived switching guard when the UE capability and RF model require it;
- unresolved flexible symbols are unavailable to a strict channel allocation;
- every resolution records the allocating channel and decision source.

Remove the single global `SpecialSlotDLSymbols`, `SpecialSlotGuardSymbols`, `SpecialSlotULSymbols` state from the canonical path. It may be derived for a report only when a particular slot happens to have a contiguous D/G/U runtime resolution.

## Tests

Add:

- `tests/testTDDDedicatedOverride.m`
- `tests/testFlexibleSymbolAllocator.m`

Execute all dedicated rows in `frame_tdd_test_vectors.csv` and all rows in `frame_allocation_test_vectors.csv`.

Required negative tests:

- dedicated configuration contradicts a common fixed symbol;
- PDSCH and PUSCH request the same flexible symbols;
- PDSCH uses a fixed UL symbol;
- PUSCH/PUCCH/PRACH uses a fixed DL symbol;
- a channel uses unresolved flexible symbols;
- a direction transition has insufficient guard.

Required positive tests:

- PDSCH resolves a flexible range to DL;
- PUSCH resolves a different flexible range to UL;
- guard symbols remain unoccupied;
- PRACH may use a flexible prefix/tail only when resolved to UL;
- fixed common symbols remain unchanged in the exported map.

---

# Work item 6 — Correct FDD representation

## Current problem

`TDDToken` returns `F` for FDD and `SlotPartition` gives the same slot full DL and full UL ownership. This confuses FDD with TDD flexible symbols and encourages one shared grid.

## Implement

For FDD:

- do not generate a D/U/F TDD map;
- maintain separate DL and UL carrier/grid contexts with paired frequencies or explicit unpaired simulation frequencies;
- permit simultaneous DL and UL only because they are on separate frequency resources and separate waveform grids;
- keep DL and UL frame/slot numbering time-aligned;
- apply timing advance to UL waveform timing where required;
- expose `DuplexMode="FDD"`, never a slot token `F`.

APIs that ask whether a symbol is available must include direction and carrier/grid context:

```matlab
isAvailable(time, "DL", dlBWP)
isAvailable(time, "UL", ulBWP)
```

A directionless `IsDLSlot/IsULSlot` call on an FDD carrier should be deprecated or require an explicit link context.

## Tests

Add `tests/testFDDSeparateFrameGrids.m`.

Generate simultaneous DL and UL allocations at the same time index and prove:

- they use different carrier/grid identities;
- their resource keys do not collide;
- the DL waveform does not contain UL REs and vice versa;
- `F` is never emitted as an FDD slot token;
- a TDD flexible-symbol resolver is never called for FDD.

---

# Work item 7 — Separate CORESET/PDCCH and PDSCH/PUSCH allocations

## Current problem

The frame engine clamps CORESET duration and automatically places PDSCH after it over the slot remainder. `buildInternalConfig` overwrites explicit PDSCH and PUSCH allocations.

## Implement

The frame engine must resolve only frame/grid/timing availability. It must not create a PDSCH or PUSCH grant.

Create canonical allocation objects for:

- CORESET/search-space monitoring occasion;
- PDCCH candidate;
- PDSCH TDRA and frequency allocation;
- PUSCH TDRA and frequency allocation;
- PUCCH/PRACH/reference-signal reservations.

PDSCH/PUSCH start symbol and length must come from an explicit TDRA row or an explicit test grant. Decode SLIV and mapping type according to the selected 38.214 table. Never set PDSCH start to CORESET duration and never default PUSCH to a full slot.

CORESET/PDSCH may overlap in time symbols while occupying different REs. Therefore:

- preserve the requested PDSCH time allocation;
- build exact RE sets for CORESET/PDCCH, PDSCH DM-RS/PTRS/data, and reserved resources;
- perform collision/rate-matching legality at RE level;
- reject an actual unhandled RE collision;
- accept a legal PDSCH allocation that begins at symbol 0 when its mapping/rate matching is valid.

Do not clamp invalid CORESET duration or frequency-domain resources. Throw an explicit validation error.

## Refactor

Remove these overwrites from `buildInternalConfig`:

- `phy.pdsch.startSymbol` and `numSymbols` assigned from the frame engine;
- `pdsch6gr.StartSymbol = max(frameStart, configuredStart)`;
- global `phy.pusch.symbolAllocation = [0 SymbolsPerSlot]`.

Update `tests/testFrameStructureEngine.m` so it verifies that explicit allocations are preserved and independently validated. Delete the old assertion that PDSCH must start after CORESET.

## Tests

Add:

- `tests/testControlDataAllocationIndependence.m`
- `tests/testResourceAllocationValidator.m`

Include:

- PDSCH symbol 0–13 preserved with a two-symbol CORESET;
- legal RE-level rate matching around a CORESET;
- illegal unreserved RE collision;
- multiple supported TDRA rows and mapping types A/B;
- invalid SLIV;
- missing TDRA in the strict path;
- no mutation of input grant/configuration objects.

Export `allocation_legality.csv` and `resource_grid_occupancy.csv`.

---

# Work item 8 — Create one exact SSB timing resolver and remove waveform clamping

## Current problem

`FrameStructureEngine.resolveSSBCase` and `SSB_Tx` use inconsistent case support. The transmitter coerces `Lmax` and clamps the carrier grid after `nrWaveformGenerator` rejects it.

## Implement

Create one `SSBTimingResolver` used by:

- `FrameStructureEngine` facade;
- SSB transmitter;
- SSB receiver/search;
- Type-0 CSS/SIB1 scheduling;
- artifact export and validation.

Resolve from the pinned 38.211/38.213 tables:

- SSB case A–G where applicable;
- SSB subcarrier spacing;
- candidate start symbols within the half-frame;
- candidate indices and `Lmax`;
- half-frame and periodicity;
- carrier-frequency/band constraints;
- relationship to the carrier/BWP grid and Point A.

Do not infer the case from only `fc > 24.25 GHz` and carrier SCS. Do not maintain independent symbol lists in multiple files.

In `SSB_Tx.m`:

- remove `localWavegenWithClamp`;
- remove parsing of MATLAB error text to discover a maximum RB count;
- remove invalid-`Lmax` coercion;
- validate all inputs before waveform generation;
- call `nrWaveformGenerator` once;
- propagate any configuration error without modifying the requested carrier.

## Tests

Add `tests/testSSBTimingResolver.m`.

Build table-driven positive and negative tests for every SSB case supported by the installed Release-18 toolbox. For each positive case, assert that TX, RX, frame facade and Type-0 CSS code receive identical candidate symbols and indices.

Add a regression test using an invalid bandwidth/SCS/grid combination and assert:

- waveform generation fails before calling the generator or with the original validation error;
- `NSizeGrid` is unchanged;
- no warning indicates clamping;
- no retry occurs.

---

# Work item 9 — Create one complete PRACH occasion resolver and remove sparse defaults

## Current problem

The frame engine hard-codes a few PRACH configuration indices, defaults unknown indices to A1-like behavior, scans an arbitrary number of slots, and catches all Toolbox errors.

## Implement

Create one `PRACHOccasionResolver` used by the frame engine, PRACH transmitter, receiver and random-access scheduler.

The resolver must consume at least:

- frequency range subtype;
- paired/unpaired spectrum or duplex mode;
- PRACH configuration index;
- carrier/BWP SCS;
- PRACH SCS;
- sequence length/format;
- restricted set;
- zero-correlation zone;
- `msg1-FDM` and `msg1-FrequencyStart`;
- association-period/occasion information required by the selected release.

Use the exact Release-18 configuration tables or a direct, validated `nrPRACHConfig`/`nrPRACHIndices`-based implementation. Do not retain a partial hand-written switch.

For each configuration index:

- determine whether it is valid for the selected FR/duplex context;
- resolve format, periodicity, frame/subframe/slot occasions, start symbol, time duration and frequency occasion;
- map occasions onto the common/dedicated/runtime TDD symbol map;
- reject any occasion that is not UL-available;
- scan exactly the least common repetition interval needed to prove the occasion sequence, not `max(80, slotsPerFrame*4)`.

Any Toolbox exception must be propagated with context. Do not convert it to an empty result and then use all slots.

## Tests

Add `tests/testPRACHOccasionResolver.m`.

Enumerate all configuration-index values supported by the selected release for each applicable FR/duplex context. For every index:

- compare the resolver output to the pinned table or Toolbox object fields;
- compare format, periodicity, slot, symbol and frequency occasions;
- assert no PRACH occasion occupies a fixed DL symbol;
- assert flexible symbols must be resolved UL before use;
- assert unknown/invalid index fails, never becomes A1;
- assert TX, RX and scheduler use the same resolver object.

This phase owns PRACH timing/occasion correctness; preamble sequence/detection performance remains in the initial-access phase.

---

# Work item 10 — Disable implicit OFDM windowing

## Current problem

`resolveOFDMWindowing` applies `round(0.025*Nfft)` when no value is configured.

## Implement

For the standard PHY waveform path:

- default `WindowingSamples = 0`;
- use no implicit percentage;
- accept a nonzero value only from an explicit waveform/RF implementation setting;
- validate it against the OFDM API and record the exact sample count;
- never let a nonzero default change a reference waveform.

Update every PDSCH/PUSCH/SSB/reference-signal modulator to use the same resolved OFDM configuration.

## Tests

In `testOFDMSamplingResolver.m` and channel-specific waveform tests:

- omitted setting produces zero windowing;
- explicit zero produces identical samples to omitted setting;
- no-windowing waveform matches direct `nrOFDMModulate` output within numerical tolerance;
- explicit nonzero value is applied exactly and does not alter frame length unexpectedly;
- invalid value fails rather than being clipped.

Delete the 2.5% fallback and any test that expects it.

---

# Work item 11 — Implement canonical multi-BWP frame/grid operation

## Current problem

`buildInternalConfig.localApplyBWPSurface` copies one DL and one UL BWP surface. Timing, allocations and numerology are effectively global, so mixed-numerology BWP switching is not end-to-end.

## Implement

Represent each component carrier with arrays of configured DL and UL BWP objects. Each BWP must contain at least:

- `BWPID`;
- direction;
- carrier/serving-cell identity;
- SCS and cyclic prefix;
- `NStartBWP` and `NSizeBWP` relative to the carrier grid/Point A;
- symbols/slot and timing conversion;
- PDCCH/PDSCH or PUSCH/PUCCH configuration references;
- active/inactive state;
- switch activation time;
- state version/epoch.

Validate:

- BWP lies fully inside the carrier transmission bandwidth configuration;
- BWP numerology is supported for the selected FR and role;
- common TDD reference SCS is not greater than any configured active BWP SCS to which it applies;
- resource keys include BWP and carrier identity;
- a grant cannot use an inactive BWP;
- control and data BWP relationships are explicit;
- mixed numerologies align using absolute time, not by reusing slot numbers.

Create a `BWPStateMachine` that applies RRC/DCI switch commands at the correct activation time. It must preserve separate active DL and UL BWPs and expose history for tests.

Do not overwrite a global `phy.carrier.NSizeGrid` or `phy.numerology.scs_kHz` when switching BWP.

## Tests

Add `tests/testMultiBWPFrameGrid.m` with at least:

- one carrier with a 30 kHz full-size BWP and a smaller 60 kHz BWP;
- separate active DL and UL BWP IDs;
- a switch command and a delayed activation;
- control received on the configured control BWP and data scheduled on the selected data BWP;
- grants before activation use the old BWP;
- grants after activation use the new BWP;
- invalid grant on inactive BWP fails;
- BWP offset/size outside the carrier fails;
- resource-grid dimensions and symbol timing are correct before and after switch;
- no HARQ/timing state is lost merely because the BWP changes.

Export `bwp_switch_trace.csv` and `bwp_switch_timeline.png`.

---

# Work item 12 — Implement component-carrier identity and one absolute K0/K1/K2 timing engine

## Current problem

Carrier aggregation/cross-carrier state is not explicit end-to-end, and K0/K1/K2/processing-time logic is distributed across helpers and focused tests.

## Implement component-carrier state

Represent every component carrier with:

- `CCID` and serving-cell ID;
- scheduling-cell and scheduled-cell relationships;
- center frequency, band/frequency range, channel bandwidth and duplex mode;
- DL/UL carrier grids;
- BWP arrays and active BWP state;
- frame/slot timing;
- independent resource grid and waveform;
- independent HARQ process namespace and measurement namespace.

A decoded or injected scheduling grant must carry both scheduling and scheduled carrier identities. Implement carrier-indicator mapping needed by the frame/timing layer. Do not use one global carrier object for all grants.

## Implement absolute time

Create one `AbsoluteTime` representation that is exact across numerologies. Use integer base time units, rational symbol boundaries, or another representation that never accumulates floating-point slot-rounding errors.

Provide conversion APIs:

```matlab
absoluteTime = AbsoluteTime.fromFrameSlotSymbol(frame, slot, symbol, numerology)
[frame, slot, symbol] = absoluteTime.toNumerology(targetNumerology)
```

## Implement one timing engine

Create `TimingRelationEngine` and route all PDCCH/PDSCH/PUSCH/PUCCH/HARQ/RA timing calls through it.

It must resolve and validate:

- PDSCH target from PDCCH plus K0/TDRA;
- PUSCH target from PDCCH plus K2/TDRA;
- HARQ-ACK target PUCCH/PUSCH from PDSCH plus K1;
- source and target BWP numerologies;
- scheduling and scheduled component carriers;
- TDD/FDD symbol availability;
- N1/N2 processing-time capability;
- BWP-switch timing;
- UL timing advance where relevant to waveform placement;
- impossible or past target times;
- no-slot/no-symbol availability cases.

Return an explicit reason code for every rejected grant. Do not repair an impossible K value by choosing a later slot.

Replace or delegate duplicated logic such as:

- `+sixgr/+l2/+mac/resolveHARQFeedbackK1.m`;
- local K0/K1/K2 calculations in scheduler/runtime classes;
- ad hoc slot-duration conversions.

## Tests

Add:

- `tests/testTimingRelationEngine.m`
- `tests/testCarrierAggregationFrameTiming.m`

Build an exhaustive matrix over every selected numerology, representative TDD patterns, supported K0/K1/K2 table rows, and processing capability. Include positive and negative cases.

At minimum, prove:

- same-numerology and mixed-numerology target times;
- target DL/UL symbols are available;
- a target in a fixed opposite-direction symbol is rejected;
- unresolved flex is rejected until allocated;
- insufficient N1/N2 processing time is rejected;
- BWP switch activation is respected;
- two component carriers can run independently at the same absolute time;
- a cross-carrier grant targets the correct CC/BWP;
- HARQ process IDs do not leak between CCs;
- no floating-point drift after at least 10,000 frames.

Export `timing_matrix.csv`, `component_carrier_trace.csv`, `k0_k1_k2_timeline.png`, and `component_carrier_resource_map.png`.

---

# Configuration and caller migration

After the canonical objects exist, migrate every active caller. Use repository search to find all local derivations of:

```text
mu
SCS/15
slotsPerFrame
symbolsPerSlot
slotDuration
NSizeGrid
NStartGrid
NStartBWP
special slot
TDD pattern
K0 K1 K2
PDSCH StartSymbol/NumSymbols
PUSCH StartSymbol/NumSymbols
```

Every active caller must obtain these values from the canonical carrier/BWP/frame/timing objects.

`normalizeConfig` should normalize names/types only. It must not perform a second physical resolution.

`validateConfig` should construct/validate the canonical objects and return structured errors. It must not sanitize invalid strings into valid patterns.

`buildInternalConfig` should attach the already resolved objects/snapshots without re-deriving or overwriting them.

Do not catch a canonical resolver error and fall back to legacy calculations.

---

# Required test artifact generation

Create a deterministic runner, for example:

```text
tests/runFrameGridPhaseTests.m
```

It must:

1. create/clean an output directory passed by the caller;
2. run every mandatory frame/grid test;
3. execute all supplied CSV vector rows;
4. write the following CSV files with the schemas in `desired_frame_csv_contract.csv`:

```text
frame_numerology_matrix.csv
carrier_grid_matrix.csv
slot_symbol_ownership.csv
resource_grid_occupancy.csv
allocation_legality.csv
ofdm_roundtrip.csv
timing_matrix.csv
bwp_switch_trace.csv
component_carrier_trace.csv
frame_fix_test_summary.csv
frame_image_audit.csv
```

5. generate these PNG files using headless MATLAB figures:

```text
frame_slot_symbol_map.png
resource_grid_occupancy.png
numerology_timing_matrix.png
carrier_guardband_map.png
k0_k1_k2_timeline.png
bwp_switch_timeline.png
component_carrier_resource_map.png
```

Use `figure('Visible','off')` and `exportgraphics`. Use at least 1200×650 pixels. Every plot must have a nonempty title, x label, y label, readable ticks/legend where applicable, and deterministic ordering.

## Semantic image verification before export

Do not merely test that a PNG exists. In the MATLAB test, inspect the figure object before export:

- expected axes count;
- title/xlabel/ylabel strings;
- plotted matrix dimensions or line/bar series count;
- XData/YData/CData equal the source table values within tolerance;
- no empty axes;
- no NaN-only series;
- expected slot/symbol/RB extents;
- expected categorical labels.

Write the observed axes/series counts and source CSV SHA-256 into `frame_image_audit.csv`.

## Binary image verification after export

Run the supplied verifier:

```bash
python tests/vectors/frame_grid/verify_frame_artifacts.py <output-directory>
```

The verifier must return exit code 0. It checks PNG decoding, dimensions, nonblank content, hashes, CSV presence, schemas and PASS rows.

Do not use OCR as an image test.

---

# Mandatory MATLAB tests

Create or update at least these test files:

```text
tests/testFrameNumerologyCatalog.m
tests/testTransmissionBandwidthCatalog.m
tests/testOFDMSamplingResolver.m
tests/testTDDCommonPattern.m
tests/testTDDDedicatedOverride.m
tests/testTDDMultiNumerologyExpansion.m
tests/testFlexibleSymbolAllocator.m
tests/testFDDSeparateFrameGrids.m
tests/testControlDataAllocationIndependence.m
tests/testResourceAllocationValidator.m
tests/testSSBTimingResolver.m
tests/testPRACHOccasionResolver.m
tests/testTimingRelationEngine.m
tests/testMultiBWPFrameGrid.m
tests/testCarrierAggregationFrameTiming.m
tests/testFrameGridArtifacts.m
```

Use the repository's test convention, but make failures visible to `matlab -batch` and produce JUnit output when the existing harness supports it.

Run the new tests plus every existing test that references any changed source file. Then run the complete MATLAB test suite.

Suggested command shape:

```bash
matlab -batch "setup6GRSimToolkit('Verbose',false); out=fullfile(pwd,'artifacts','frame_grid_phase'); results=runtests({'tests/testFrameNumerologyCatalog.m','tests/testTransmissionBandwidthCatalog.m','tests/testOFDMSamplingResolver.m','tests/testTDDCommonPattern.m','tests/testTDDDedicatedOverride.m','tests/testTDDMultiNumerologyExpansion.m','tests/testFlexibleSymbolAllocator.m','tests/testFDDSeparateFrameGrids.m','tests/testControlDataAllocationIndependence.m','tests/testResourceAllocationValidator.m','tests/testSSBTimingResolver.m','tests/testPRACHOccasionResolver.m','tests/testTimingRelationEngine.m','tests/testMultiBWPFrameGrid.m','tests/testCarrierAggregationFrameTiming.m','tests/testFrameGridArtifacts.m'}); assertSuccess(results); runFrameGridPhaseTests(out);"
python tests/vectors/frame_grid/verify_frame_artifacts.py artifacts/frame_grid_phase
```

Use the correct repository setup syntax if it differs. Record the exact MATLAB release, 5G Toolbox version, commands, test counts and verifier result.

---

# Static shortcut-removal checks

Before declaring completion, search the active standard PHY path. The following behaviors must have no active hit:

```text
F converted to D
configured grid used after standard table miss
FR2-2 classified as FR3
nextpow2 used as the implicit standard OFDM resolver
12/1/1 or 7/0/7 special-slot fallback
default DDDSU pattern in the standard path
PDSCH start derived from CORESET duration
PUSCH full-slot allocation injected by frame resolution
2.5%-of-NFFT default windowing
SSB NSizeGrid clamp/retry
unknown PRACH index defaulted to A1
catch-all fallback from canonical resolver to legacy resolver
```

A compatibility-only implementation is permitted only under `+sixgr/+compat/`, requires an explicit caller opt-in, and must be absent from all mandatory phase tests.

---

# Required completion criteria

Do not stop after producing a plan or partial patch. The phase is complete only when all of these are true:

1. All 12 work items above are implemented in executable MATLAB code.
2. One canonical resolved carrier/BWP/frame/timing state replaces duplicate calculations.
3. Every row in the supplied numerology, carrier, TDD and allocation vector files executes.
4. Valid rows match exactly; invalid rows fail with the expected identifier/reason.
5. Flexible symbols remain flexible until a runtime allocation resolves them.
6. FDD uses separate DL and UL carrier/grid contexts.
7. PDSCH/PUSCH allocations are never auto-shifted or invented by frame resolution.
8. SSB configuration is never clamped/retried.
9. Unknown PRACH configuration never defaults to A1 or all slots.
10. Standard OFDM windowing defaults to zero.
11. Multi-BWP and two-CC tests pass without state leakage.
12. K0/K1/K2 tests use one exact absolute-time engine.
13. Every mandatory MATLAB test runs and passes; required tests are not skipped.
14. All required CSV files exist, are nonempty, have the required schema and contain only PASS rows.
15. All seven required images pass semantic MATLAB checks and the Python binary/nonblank verifier.
16. The complete existing MATLAB test suite passes after the changes.

If a dependency in the installed MATLAB/5G Toolbox version blocks a valid Release-18 case, do not fake support. Report the exact unsupported API/case and keep the phase open until the toolchain is upgraded or the missing algorithm is implemented directly.

---

# Codex response format after implementation

Return a technical implementation report containing exactly these sections:

1. **Files changed** — added, modified and deleted files.
2. **Canonical architecture** — concrete classes/functions and ownership of each resolved value.
3. **Work items 1–12** — for each, describe the code change and test that proves it.
4. **Commands executed** — exact MATLAB and Python commands.
5. **Test results** — test count, passed, failed, skipped and blocked.
6. **CSV results** — row counts and PASS/FAIL count for every required CSV.
7. **Image results** — file size, dimensions, semantic axes/series checks, SHA-256 and verifier status for every PNG.
8. **Shortcut-removal search** — command and remaining hits, if any.
9. **Residual technical limitations** — only real unresolved PHY limitations, with file/function and failing test.
10. **Final status** — `COMPLETE` only when every completion criterion is met; otherwise `INCOMPLETE` with the exact failing criteria.

Begin editing the repository now. Do not return a review-only response.
