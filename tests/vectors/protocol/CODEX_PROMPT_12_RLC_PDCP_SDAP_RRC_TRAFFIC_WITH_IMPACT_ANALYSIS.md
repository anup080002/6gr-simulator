# CODEX IMPLEMENTATION PROMPT — RLC, PDCP, SDAP, RRC, BEARERS, HANDOVER AND TRAFFIC

You are the lead 3GPP RAN2 protocol-stack engineer, MATLAB implementation owner and test owner for this repository.

## Mission

Modify the production MATLAB repository. Do not return a review or a plan-only response.

Build a bounded, executable Release-18 connected-mode protocol profile whose live data path is:

```text
Traffic packet/session/PDU-set event
  → SDAP exact QFI/DRB mapping and SDAP PDU
  → PDCP exact header, COUNT/HFN, security, reordering and duplicate control
  → RLC TM/UM/AM exact PDU, segmentation/reassembly/status/retransmission
  → MAC SDU/PDU/TB/HARQ chain
  → receiver RLC → PDCP → SDAP → traffic/session delivery
```

The control path is:

```text
Decoded RRC ASN.1 UPER message
  → event-sourced RRC procedure and transaction
  → validated RadioBearerConfig / CellGroupConfig / MeasConfig
  → atomic lower-layer commit with one configuration epoch
  → decoded peer completion message
  → converged UE and gNB state
```

The selected strict profiles are:

```text
nr_rel18_connected_mode_bounded_strict
nr_rel18_handover_bounded_strict
protocol_system_study
unsupported_extension
```

Do not describe the output as full-stack 3GPP conformance. This is a bounded protocol implementation validated against the enabled tuples.

## Pinned specifications

Use these exact baselines unless the repository owner explicitly changes the profile in one atomic commit:

```text
3GPP TS 38.322 V18.2.0 — NR RLC
3GPP TS 38.323 V18.5.0 — NR PDCP
3GPP TS 37.324 V18.0.0 — SDAP
3GPP TS 38.331 V18.9.0 — NR RRC
3GPP TS 38.321 V18.9.0 — NR MAC interfaces and logical-channel ownership
3GPP TS 38.300 V18.9.0 — NR architecture and RRC states
3GPP TS 24.501 Release 18 — optional external NAS boundary only
```

Record clause/table/figure references in source comments and vector metadata. Never invent a field width or timer rule.

## Non-negotiable technical rules

1. Connected strict RRC messages are ASN.1 UPER bytes, not JSON and not custom anchor bit layouts.
2. A successful decode must come from the received PDU and installed context, not from an expected tree/hash/message supplied by the transmitter.
3. RLC, PDCP and SDAP PDUs are bit-exact for every enabled tuple.
4. No SN, QFI, timer, field, state, payload or length may be clamped, wrapped, defaulted or silently omitted.
5. RLC AM supports enabled 12- and 18-bit SN profiles and exact STATUS PDUs.
6. RLC UM supports enabled 6- and 12-bit SN profiles and exact t-Reassembly behavior.
7. PDCP COUNT is 32 bits composed from HFN and PDCP SN; COUNT does not wrap.
8. PDCP security uses exact COUNT, BEARER, DIRECTION, key and activation state.
9. Simulator XOR, SHA-256 integrity and custom 0xF0 ROHC are forbidden in strict paths.
10. Missing QFI mapping must not become an arbitrary DefaultLCID.
11. Every RRC procedure is event-sourced and transaction/timer owned.
12. Radio-bearer configuration is validated completely before any layer changes; commit is atomic.
13. Dynamic handover decisions use received and filtered measurement reports, not geometry truth.
14. A synthetic NAS RegistrationRequest cannot mark registration or session establishment successful.
15. Traffic uses immutable packets/sessions/PDU sets and named random streams; global rand/randn is forbidden in strict traffic generators.
16. A retransmission or duplicate must not increase first-delivery goodput.
17. Every packet, SDU, PDU, TB and delivery has immutable lineage.
18. Unsupported tuples fail during planning before PDU generation or state mutation.
19. A MATLAB test that is skipped, blocked or unavailable is not a pass.
20. Do not copy supplied expected CSVs into result folders. Execute production code and compare fields.

## Current source anchors

Inspect and migrate these production files before adding new code:

```text
+sixgr/+l2/+rlc/RLC_AM.m
+sixgr/+l2/+rlc/RLC_UM.m
+sixgr/+l2/+rlc/RLC_TM.m
+sixgr/+l2/+pdcp/PDCP.m
+sixgr/+l2/+sdap/SDAP.m
+sixgr/+l3/+rrc/RRC.m
+sixgr/+l3/+rrc/AttachProcedure.m
+sixgr/+l3/+rrc/SystemInformation.m
+sixgr/+rrc/+asn1/encodeSIB1UPER.m
+sixgr/+rrc/+asn1/decodeSIB1UPER.m
+sixgr/+system/TrafficFactory.m
+sixgr/+system/Traffic_XR.m
+sixgr/+system/Traffic_GenAI.m
+sixgr/+system/Traffic_mMTC.m
```

Use `current_protocol_stack_static_audit.csv` as a source-navigation aid, not as the definition of done.

## Fifteen findings to close

| ID | Finding | Current defect | Required implementation | Mandatory acceptance |
|---|---|---|---|---|
| **PROTO-001** | RLC AM PDU and sequence-number fidelity | RLC AM is explicitly a simplified non-bit-exact 12-bit-SN implementation with a custom AMD header. | Implement exact TS 38.322 AMD PDU formats for 12- and 18-bit SN, SI/SO rules, window variables, segmentation and re-segmentation. | Bit-exact 12/18-bit AMD vectors; wrap/window boundaries; no padding/clamping; no waveform/state change for invalid tuples. |
| **PROTO-002** | RLC AM polling, STATUS and timers | Polling uses PollEveryNPDU and STATUS contains only ACK_SN plus a simplified NACK list; t-PollRetransmit, t-StatusProhibit, pollPDU/pollByte and complete E1/E2/E3/NACK-range behavior are missing. | Implement event-sourced AM polling, exact STATUS PDU, segment NACKs, NACK ranges, t-PollRetransmit, t-Reassembly and t-StatusProhibit. | Independent STATUS vectors; loss/reordering/resegmentation campaigns; exact timer transitions; maxRetxThreshold and re-establishment tests. |
| **PROTO-003** | RLC UM formats, reassembly and window | UM is abstract; although 6/12-bit SN exists, header/reassembly and timer behavior are not proven bit-exact across all SI/SO and wrap cases. | Implement exact UMD PDU formats, RX_Next_Reassembly/RX_Next_Highest/RX_Timer_Trigger state, t-Reassembly and delivery/discard rules. | Complete-SDU, first/middle/last, SO, wrap, duplicate and out-of-window vectors for 6/12-bit SN. |
| **PROTO-004** | RLC entity lifecycle and bearer ownership | RLC mode/state is not fully owned by an RRC-installed bearer configuration and re-establishment/release procedures are incomplete. | Create immutable bearer/entity identities, configuration epochs, TM/UM/AM lifecycle, re-establishment, reset, release and statistics isolation. | SRB0/SRB1/SRB2/DRB entity creation, reconfiguration, release and handover continuity tests with no cross-bearer leakage. |
| **PROTO-005** | PDCP COUNT, PDU formats and state variables | PDCP is simplified; SN is used directly without complete HFN/COUNT, RX_DELIV/RX_NEXT/RX_REORD/TX_NEXT and exact SRB/DRB PDU/control-PDU behavior. | Implement exact 12/18-bit PDCP headers, 32-bit COUNT, HFN progression, reordering/discard/status/data-recovery and control PDUs. | COUNT wrap boundary, header, reordering, discard timer, status report, data recovery and duplicate-delivery vectors. |
| **PROTO-006** | PDCP security | Security supports NEA0/NIA0 plus simulator XOR/SHA-256 hooks; exact algorithm inputs, key ownership and activation timing are incomplete. | Implement bounded 128-NEA2/128-NIA2 alongside NEA0/NIA0 using COUNT, BEARER, DIRECTION and RRC-installed keys; activate only after SecurityModeCommand/Complete. | Independent AES-CTR/CMAC vectors; wrong COUNT/bearer/direction/key failures; integrity-before-decompression and decipher-before-delivery ordering. |
| **PROTO-007** | PDCP duplication, split paths and header compression | ROHC is a custom 0xF0 marker; duplication, status, data recovery, split bearer, DAPS, ROHC/EHC/UDC procedures are incomplete. | Implement only explicitly selected bounded features. Add exact PDCP duplication/path state first; keep ROHC/EHC/UDC/DAPS unsupported until independent vectors exist. | Duplicate suppression and path selection tests; unsupported features reject during planning; no custom marker in strict path. |
| **PROTO-008** | SDAP PDU and QoS-flow mapping | SDAP uses one custom header, silently ignores malformed mapping and falls back to DefaultLCID. Exact UL/DL headers, end-marker and reflective mapping are incomplete. | Implement exact DL and UL SDAP data headers, end-marker control PDU, QFI-to-DRB mapping, default-DRB and reflective QoS state from RRC. | All QFI 0..63 headers, UL/DL difference, end-marker, remapping, RDI/RQI, missing-QFI and stale-epoch tests. |
| **PROTO-009** | RRC ASN.1 encoding | RRC messages use JSON, while the existing SIB1 encoder is a custom anchor bit layout labelled UPER. | Introduce a Release-18 ASN.1 module set and unaligned PER codec for the bounded message profile; JSON remains diagnostics only. | Frozen independent UPER vectors and decode/re-encode equality for every enabled message; unknown extensions and constraint violations fail closed. |
| **PROTO-010** | RRC state and procedure engine | RRC is essentially IDLE/CONNECTED with synthetic attach structs and local hooks; exact transactions, timers and procedure failures are incomplete. | Implement event-sourced RRC_IDLE/RRC_INACTIVE/RRC_CONNECTED state, transaction IDs, timers and bounded setup, security, capability, reconfiguration, release, re-establishment and resume. | Message-sequence, timer-expiry, duplicate, wrong-transaction, rollback and state-convergence tests at both UE and gNB. |
| **PROTO-011** | Radio bearer configuration | RRCSetup contains a tiny srb1 struct rather than complete RadioBearerConfig ownership and atomic lower-layer application. | Implement typed SRB/DRB/PDCP/RLC/SDAP/LC/CellGroup configuration and two-phase validate/commit with configuration epochs. | Atomic add/modify/release; rejected config changes no layer; successful config produces matching RRC/RLC/PDCP/SDAP/MAC state. |
| **PROTO-012** | Handover and mobility coupling | Handover methods are stubs and A3 is a local counter; target context, reconfigurationWithSync, RA, bearer re-establishment and failure recovery are incomplete. | Implement bounded intra-frequency handover driven by filtered MeasurementReport, source/target contexts, target RA, path switch abstraction, PDCP/RLC handling and completion/failure. | No-oracle measurement-to-HO sequence, target-access, interruption, packet continuity, T304 expiry, rollback and wrong-target tests. |
| **PROTO-013** | NAS and 5GC boundary | RRCSetupComplete embeds a synthetic RegistrationRequest; exact N1/N2, NGAP and 5GC state are not implemented. | Define a typed RAN-to-NAS/N2 boundary. Keep full NAS/5GC outside the mandatory RAN profile unless a separately versioned exact profile is implemented. | Synthetic NAS cannot mark registration successful; missing external NAS result leaves state pending; optional exact profile requires independent TS 24.501/NGAP vectors. |
| **PROTO-014** | Traffic, session and QoS models | Traffic is primarily bits-per-TTI, global RNG and simple TCP/FTP proxies; packet/session/PDU-set/5QI and transport feedback are incomplete. | Create immutable packet, session, flow and PDU-set events with named random streams; implement bounded CBR, Poisson, periodic, burst, XR/PDU-set, mMTC and trace replay. Keep TCP/QUIC as study profiles unless packet-accurate. | Seed reproducibility, arrival distributions, session transitions, 5QI/PDB/PER/PDU-set deadlines and queue/drop tests. |
| **PROTO-015** | End-to-end lineage and connected-mode validation | Packet-to-SDAP-to-PDCP-to-RLC-to-MAC-to-HARQ-to-delivery conservation and independent protocol vectors are incomplete. | Add immutable lineage, first-delivery de-duplication, byte/bit conservation, full-stack event logs, negative tests and multi-seed campaigns. | Zero orphan/unowned/duplicate bytes; exact PDU hashes; latency/goodput/drop accounting; all mandatory artifacts and tests complete. |

## Required production architecture

| Task | Component | Production files | Findings | Exit condition |
|---|---|---|---|---|
| P01 | Specification and capability profiles | `+sixgr/+protocol/ProtocolSpecificationProfile.m|ProtocolCapabilityProfile.m|ProtocolPlanningResult.m` | PROTO-001..015 | Pin releases, profiles, feature tuples and planning-time rejection. |
| P02 | Event store and identities | `+sixgr/+protocol/ProtocolEvent.m|ProtocolEventStore.m|ProtocolIdentity.m|ConfigurationEpoch.m` | PROTO-004,010,011,015 | Provide append-only cross-layer causal state. |
| P03 | RLC common/entity factory | `+sixgr/+l2/+rlc18/RLCEntityFactory.m|RLCBearerIdentity.m|RLCEntityLifecycle.m` | PROTO-001..004 | Create exact TM/UM/AM entities from RRC config. |
| P04 | RLC UM | `+sixgr/+l2/+rlc18/RLCUMEntity.m|UMDPDUCodec.m|RLCUMState.m` | PROTO-003 | Exact 6/12-bit UMD, t-Reassembly and window. |
| P05 | RLC AM | `+sixgr/+l2/+rlc18/RLCAMEntity.m|AMDPDUCodec.m|STATUSPDUCodec.m|RLCAMState.m` | PROTO-001,002 | Exact 12/18-bit AMD, poll/status/timers/resegmentation. |
| P06 | PDCP common/state | `+sixgr/+l2/+pdcp18/PDCPState.m|PDCPCount.m|PDCPPDUCodec.m` | PROTO-005 | Exact PDU/control PDU, COUNT/HFN/reordering/discard. |
| P07 | PDCP security | `+sixgr/+l2/+pdcp18/PDCPSecurityContext.m|NEA2.m|NIA2.m` | PROTO-006 | Exact bounded AS security and activation. |
| P08 | PDCP path features | `+sixgr/+l2/+pdcp18/PDCPDuplicationState.m|PDCPPathSelector.m` | PROTO-007 | Bounded duplication; unsupported compression/features rejected. |
| P09 | SDAP | `+sixgr/+l2/+sdap18/SDAPEntity.m|SDAPPDUCodec.m|QoSFlowMappingState.m` | PROTO-008 | Exact UL/DL headers, end-marker and reflective mapping. |
| P10 | ASN.1 runtime | `+sixgr/+l3/+rrc18/+asn1/RRCASN1Registry.m|UPERCodec.m|RRCMessageValidator.m` | PROTO-009 | Schema-derived Release-18 UPER. |
| P11 | RRC procedure engine | `+sixgr/+l3/+rrc18/RRCUE.m|RRCGNB.m|RRCTransaction.m|RRCTimerService.m` | PROTO-010 | Event-sourced RRC procedures/states. |
| P12 | Bearer configuration | `+sixgr/+l3/+rrc18/RadioBearerConfigState.m|BearerConfigTransaction.m` | PROTO-011 | Atomic validate/commit to all layers. |
| P13 | Handover | `+sixgr/+l3/+rrc18/HandoverContext.m|HandoverStateMachine.m` | PROTO-012 | Bounded intra-frequency source-target procedure. |
| P14 | NAS boundary | `+sixgr/+l3/+rrc18/NASBoundary.m|N1N2Event.m` | PROTO-013 | Typed boundary without synthetic success. |
| P15 | Traffic engine | `+sixgr/+traffic18/TrafficSession.m|TrafficPacket.m|PDUSet.m|TrafficGenerator.m` | PROTO-014 | Packet/session/PDU-set and named streams. |
| P16 | Lineage and artifacts | `+sixgr/+protocol/ProtocolLineageGraph.m|ProtocolConservationLedger.m|ProtocolArtifactExporter.m` | PROTO-015 | Cross-layer identity, conservation and outputs. |

Compatibility façades may remain at old class names only when they delegate to the canonical implementation. There must be one codec, one state machine and one timer owner for each procedure.

# Part A — Protocol event store and identity

Create immutable identities:

```matlab
ProtocolIdentity = struct( ...
    UEID, Endpoint, PduSessionID, QFI, DRBID, SRBID, LCID, ...
    RLCEntityID, PDCPBearerID, ConfigurationEpoch);
```

Create append-only events:

```matlab
ProtocolEvent = struct( ...
    EventID, ParentEventIDs, AbsoluteRadioTime, WallClockTime, ...
    UEID, Endpoint, Layer, BearerID, EventType, ...
    ConfigurationEpoch, PayloadSHA256, Metadata);
```

State projections are deterministic folds over the event stream. No class may mutate a peer or another layer directly. A procedure emits an event; the owning projection consumes it.

Required causal examples:

```text
RRCReconfiguration decoded
  → bearer-config validation event
  → RLC/PDCP/SDAP/MAC prepare events
  → one atomic commit event
  → RRCReconfigurationComplete encoded/transmitted

PDCP PDU received
  → decipher event
  → integrity verification event
  → duplicate/reordering event
  → decompression event if an enabled exact profile exists
  → SDAP delivery event
```

# Part B — Exact RLC implementation

## RLC TM

Implement TMD PDU as data only. Bind SRB0/CCCH ownership to the RRC-created entity. Do not add a synthetic header.

## RLC UM

Implement exact UMD PDU formats:

```text
complete RLC SDU: SI + reserved bits; no SN
6-bit SN, first segment: SI + SN
12-bit SN, first segment: SI + R + R + SN
last/middle segment: add 16-bit SO
```

SI values:

```text
00 complete SDU
01 first segment
10 last segment
11 neither first nor last
```

Implement at least these state variables using the terminology and modular comparisons from TS 38.322:

```text
TX_Next
RX_Next_Reassembly
RX_Timer_Trigger
RX_Next_Highest
UM_Window_Size
```

`t-Reassembly` must start, stop and expire only under the specified receive-state conditions. Test wraparound at 2^6 and 2^12, duplicates, stale PDUs, out-of-window PDUs, first/middle/last segments, missing segment and timer expiry.

## RLC AM

Implement exact AMD headers:

```text
D/C | P | SI | SN
optional SO only for a segment that is not the first segment
12-bit and 18-bit SN
```

Implement transmitting and receiving variables, including the applicable:

```text
TX_Next
TX_Next_Ack
POLL_SN
RX_Next
RX_Next_Highest
RX_Highest_Status
RX_Next_Status_Trigger
AM_Window_Size
```

Implement:

```text
pollPDU
pollByte
t-PollRetransmit
maxRetxThreshold
t-Reassembly
t-StatusProhibit
```

STATUS PDU must support:

```text
ACK_SN
E1
NACK_SN
E2
SOstart
SOend
E3
NACK range
```

The STATUS encoder must trim only according to the protocol rules and available grant. It must never discard a NACK silently or replace segment NACKs with whole-SDU NACKs unless that exact behavior is permitted and logged.

Implement re-segmentation using the original RLC SDU and exact SO ownership. A retransmitted segment must carry the same SDU/SN lineage and its actual byte range.

# Part C — Exact PDCP implementation

## PDU formats and COUNT

Implement:

```text
SRB data PDU: 12-bit PDCP SN and 4-byte MAC-I field
DRB data PDU: 12-bit or 18-bit PDCP SN, D/C and reserved bits
PDCP control PDUs for enabled status/data-recovery profiles
```

Maintain:

```text
TX_NEXT
RX_NEXT
RX_DELIV
RX_REORD
HFN
COUNT = HFN || PDCP_SN
```

COUNT cannot wrap. Exhaustion is a typed error and blocks PDU generation.

Implement `t-Reordering`, `discardTimer`, duplicate detection, in-order delivery, out-of-order delivery only when configured, status reporting and data recovery for the enabled profiles.

## Security

Implement bounded security profiles:

```text
128-NEA0 / 128-NIA0
128-NEA2 / 128-NIA2
```

Inputs are exactly:

```text
KEY
COUNT
BEARER
DIRECTION
MESSAGE bit length
```

Security activation is owned by decoded `SecurityModeCommand` and `SecurityModeComplete` state. The TX and RX activation COUNT/direction must be explicit. Wrong key, COUNT, bearer, direction, algorithm, activation epoch or MAC-I fails closed.

Use `protocol_pdcp_security_vectors.csv`, generated independently with AES-CTR and AES-CMAC, as the minimum oracle. Add official/frozen 3GPP algorithm vectors as well.

## Duplication and compression

Implement a bounded duplication profile with exact path identities, first-delivery de-duplication and reordering. Keep these `UNSUPPORTED` until independently implemented:

```text
full ROHC
EHC
UDC
DAPS
MR-DC split bearer
```

Delete the custom 0xF0 ROHC marker from the strict path.

# Part D — Exact SDAP

Implement direction-specific headers:

```text
DL data PDU: RDI | RQI | QFI
UL data PDU: D/C=1 | R=0 | QFI
End-marker control PDU: D/C=0 | R=0 | QFI/PQFI
```

Implement RRC-owned:

```text
PDU session
QFI
5QI
QFI-to-DRB mapping
mappedQoS-FlowsToAdd / mappedQoS-FlowsToRelease
default DRB
SDAP header presence per direction
reflective QoS mapping state
end-marker state
```

A QFI outside 0..63 is rejected. A missing mapping is rejected unless an exact active default-DRB rule resolves it. Never clamp or choose a default LCID locally.

# Part E — ASN.1 RRC and procedure state

## ASN.1

Import or generate the exact Release-18 ASN.1 module set needed by the bounded profile. Build one UPER codec. The codec must:

```text
preserve CHOICE and extension semantics
validate ranges and optional-field presence
retain unknown extension information where the chosen runtime supports it
reject malformed or trailing non-padding bits
round-trip against independent frozen vectors
```

JSON is allowed only as a human-readable rendering of a decoded ASN.1 tree. `encodeSIB1UPER.m` and `decodeSIB1UPER.m` currently implement a custom anchor format; they cannot be used as strict ASN.1 evidence.

Enable only messages with frozen independent vectors. The target bounded set is:

```text
RRCSetupRequest
RRCSetup
RRCSetupComplete
SecurityModeCommand
SecurityModeComplete / Failure
UECapabilityEnquiry
UECapabilityInformation
RRCReconfiguration
RRCReconfigurationComplete
MeasurementReport
RRCRelease
RRCReestablishmentRequest / RRCReestablishment / Complete
RRCResumeRequest / RRCResume / Complete
```

## State and transactions

Implement UE and network states:

```text
RRC_IDLE
RRC_INACTIVE
RRC_CONNECTED
```

Use explicit intermediate procedure states and timers. Each transaction records:

```text
procedure
transaction ID
initiating decoded message/event
expected response
start/expiry time
configuration epoch
completion/failure cause
rollback action
```

Implement at least T300, T301, T304, T310, T311, T319 and the selected procedure timers needed by the enabled profile. Do not emulate them with one generic slot timeout.

# Part F — Radio-bearer configuration

Create typed objects for:

```text
SRB-ToAddMod
DRB-ToAddMod
DRB-ToReleaseList
PDCP-Config
RLC-Config
SDAP-Config
LogicalChannelConfig
RadioBearerConfig
CellGroupConfig subset used by the profile
```

Two-phase behavior:

```text
1. Validate all ASN.1 semantics and cross-layer constraints without mutation.
2. Prepare every affected entity.
3. Commit every layer with one ConfigurationEpoch.
4. If any preparation/commit fails, roll back all layers.
5. Send RRCReconfigurationComplete only after successful commit.
```

Test add, modify and release for SRB0, SRB1, SRB2, UM DRB and AM DRB.

# Part G — Bounded handover

Implement intra-frequency handover first:

```text
filtered measurement state
A3 entry/leave, hysteresis and TTT
MeasurementReport ASN.1
source decision and target preparation
RRCReconfiguration with reconfigurationWithSync
target synchronization and random access
T304
RLC/PDCP handling per configured bearer
RRCReconfigurationComplete at target
source release / target serving state
failure and rollback
```

No source or target cell may be selected from an instantaneous geometry-oracle RSRP in the strict procedure. The target cell must be derived from decoded filtered measurement reports.

The handover trial exports interruption time, first lost packet, first target-delivered packet, duplicate deliveries, RLC retransmissions, PDCP recovery actions, target RA result and final UE/gNB states.

# Part H — NAS boundary

Do not implement a fake successful core network inside RRC.

Create:

```text
NASBoundary.request()
NASBoundary.indication()
N1N2Event
ExternalNASTransactionID
ExternalResult = PENDING | SUCCESS | FAILURE
```

`RRCSetupComplete` may carry dedicated NAS bytes, but the simulator must not claim registration, PDU-session establishment or 5GC success until an external exact module returns a decoded result.

# Part I — Packet/session/PDU-set traffic

Create immutable objects:

```text
TrafficSession
TrafficFlow
TrafficPacket
PDUSet
PacketArrivalEvent
PacketDeadlineEvent
PacketDropEvent
```

Every flow owns a named random stream derived from the master seed and flow identity. No strict generator may call global `rand` or `randn`.

Implement bounded profiles:

```text
periodic CBR packets
Poisson packet arrivals
bounded on/off burst packets
XR packet/PDU-set traffic
mMTC periodic/event packets
trace replay with exact packet times/sizes
```

Every packet carries:

```text
PacketID, SessionID, FlowID, arrival time, bytes,
PDU session, QFI, 5QI, PDB/deadline, PDU-set identity,
random-stream identity and payload hash
```

Keep full TCP/FTP/QUIC interoperability under a separate study/unsupported profile until actual transport ACK, retransmission, RTT, connection and application-session behavior is implemented.

# Part J — Lineage and conservation

Track:

```text
Traffic packet
 → SDAP SDU/PDU
 → PDCP SDU/PDU and COUNT
 → RLC SDU/PDU/segment and SN/SO
 → MAC SDU/PDU
 → TB/codeword/HARQ attempts
 → receiver RLC/PDCP/SDAP
 → first packet/PDU-set delivery or drop
```

Mandatory equations:

```text
ArrivedBytes = QueuedBytes + InFlightBytes + DeliveredBytes + DroppedBytes
UnownedBytes = 0
DuplicateDeliveredBytes = 0
EquationErrorBytes = 0
```

Header, security, control, retransmission and coding bytes are tracked separately from payload goodput.

# Part K — Independent vectors

Install this pack under `tests/vectors/protocol/` and execute:

```text
protocol_rlc_um_header_vectors.csv
protocol_rlc_am_header_vectors.csv
protocol_rlc_status_vectors.csv
protocol_rlc_timer_state_vectors.csv
protocol_pdcp_header_vectors.csv
protocol_pdcp_count_vectors.csv
protocol_pdcp_security_vectors.csv
protocol_pdcp_reordering_vectors.csv
protocol_sdap_header_vectors.csv
protocol_sdap_mapping_vectors.csv
protocol_rrc_message_vectors.csv
protocol_rrc_state_transition_vectors.csv
protocol_radio_bearer_vectors.csv
protocol_handover_state_vectors.csv
protocol_traffic_arrival_vectors.csv
protocol_lineage_vectors.csv
protocol_negative_test_vectors.csv
protocol_capability_profile_matrix.csv
```

The supplied RLC, PDCP header/COUNT/security, SDAP, traffic and lineage vectors are independent bounded floors. RRC rows marked `REQUIRED_BEFORE_ENABLE` are not fabricated UPER outputs. Add real frozen vectors produced by an independent Release-18 ASN.1 implementation before enabling each message.

# Part L — Impact analysis

Execute all 64 families and 768 experiments. Baseline/treatment members of a pair use identical seed, packet payloads, channel/noise realization and initial protocol state. Only the declared factor differs.

| Family | Analysis | Wave | Controlled factor | Metrics |
|---|---|---|---|---|
| F01 | RLC AM 12 versus 18-bit SN | A | SNBits: `12` → `18` | header overhead|wrap frequency|goodput |
| F02 | RLC UM 6 versus 12-bit SN | A | SNBits: `6` → `12` | header overhead|reordering range |
| F03 | RLC segmentation size | A | SegmentBytes: `300` → `900` | PDU count|latency |
| F04 | RLC re-segmentation | A | Resegmentation: `off` → `on` | retransmitted bytes|latency |
| F05 | RLC pollPDU | A | PollPDU: `p64` → `p8` | status overhead|recovery |
| F06 | RLC pollByte | A | PollByte: `kB500` → `kB25` | status overhead|recovery |
| F07 | RLC t-PollRetransmit | A | tPollRetransmit_ms: `45` → `10` | retransmission timing |
| F08 | RLC t-Reassembly | A | tReassembly_ms: `35` → `5` | latency|discard |
| F09 | RLC t-StatusProhibit | A | tStatusProhibit_ms: `10` → `0` | STATUS rate|recovery |
| F10 | RLC segment NACK | A | SegmentNACK: `off` → `on` | retransmitted bytes |
| F11 | RLC NACK range | A | NACKRange: `off` → `on` | STATUS size |
| F12 | RLC loss burst | A | LossPattern: `iid` → `burst` | recovery latency |
| F13 | PDCP 12 versus 18-bit SN | A | SNBits: `12` → `18` | header overhead|wrap |
| F14 | PDCP t-Reordering | A | tReordering_ms: `100` → `10` | latency|out-of-order |
| F15 | PDCP discard timer | A | DiscardTimer_ms: `infinity` → `50` | stale packet drop |
| F16 | PDCP status report | B | StatusReport: `off` → `on` | recovery overhead |
| F17 | PDCP data recovery | B | DataRecovery: `off` → `on` | handover loss |
| F18 | PDCP integrity | A | Integrity: `NIA0` → `NIA2` | CPU|detection |
| F19 | PDCP ciphering | A | Ciphering: `NEA0` → `NEA2` | CPU|confidentiality |
| F20 | PDCP wrong COUNT | A | CountState: `correct` → `wrong` | integrity failure |
| F21 | PDCP duplication | B | Duplication: `off` → `dual_path` | reliability|overhead |
| F22 | PDCP path asymmetry | B | PathDelay: `equal` → `asymmetric` | reordering|duplicate |
| F23 | SDAP header | A | HeaderPresent: `false` → `true` | overhead|QFI recovery |
| F24 | SDAP default DRB | A | Mapping: `explicit` → `default` | mapping behavior |
| F25 | SDAP reflective QoS | B | ReflectiveQoS: `off` → `on` | mapping convergence |
| F26 | SDAP end marker | A | EndMarker: `absent` → `present` | path switch completion |
| F27 | RRC JSON versus UPER rejection | A | Codec: `JSON` → `UPER` | bit accuracy|size |
| F28 | RRC setup timer T300 | A | T300_ms: `1000` → `200` | failure latency |
| F29 | Security activation timing | A | SecurityActivation: `late` → `exact` | unprotected PDUs |
| F30 | UE capability procedure | A | CapabilityExchange: `off` → `on` | configuration legality |
| F31 | Radio bearer atomic commit | A | CommitMode: `partial` → `atomic` | cross-layer consistency |
| F32 | RRC transaction collision | A | ConcurrentTransactions: `1` → `2` | failure detection |
| F33 | RRC release | A | ReleaseCause: `normal` → `radio_failure` | state cleanup |
| F34 | RRC re-establishment | B | Reestablishment: `off` → `on` | service recovery |
| F35 | RRC resume | B | Resume: `setup_new` → `resume` | latency|signaling |
| F36 | A3 hysteresis | B | Hysteresis_dB: `1` → `4` | ping-pong|delay |
| F37 | A3 time-to-trigger | B | TTT_ms: `40` → `320` | handover timing |
| F38 | Handover target RA | B | TargetRA: `success` → `failure` | interruption |
| F39 | Handover RLC AM handling | B | RLCHandling: `reset` → `reestablish` | loss|duplicates |
| F40 | Handover PDCP recovery | B | PDCPRecovery: `off` → `on` | packet loss |
| F41 | T304 expiry | B | T304: `not_expired` → `expired` | rollback |
| F42 | NAS external result | C | NASResult: `synthetic` → `external` | registration state |
| F43 | CBR period | A | Period_ms: `10` → `1` | load|queue |
| F44 | Poisson arrival rate | A | Lambda_pps: `10` → `100` | queue|delay |
| F45 | Burst duty cycle | A | DutyCycle: `0.1` → `0.7` | burst queue |
| F46 | Packet size distribution | A | PacketSize: `64` → `1500` | segmentation|overhead |
| F47 | XR PDU-set size | A | PDUSetPackets: `2` → `8` | PDU-set delay |
| F48 | XR PDU-set deadline | A | PDUSetDeadline_ms: `50` → `10` | deadline miss |
| F49 | mMTC device count | C | DeviceCount: `100` → `10000` | access/load |
| F50 | Trace replay versus generated | A | Source: `generated` → `trace` | reproducibility |
| F51 | Named versus global RNG | A | RNG: `global` → `named_stream` | reproducibility |
| F52 | TCP proxy rejection | A | TransportProfile: `proxy` → `packet_study` | claim correctness |
| F53 | 5QI mix | B | FiveQISet: `single` → `mixed` | PDB/fairness |
| F54 | QFI remapping | B | MappingEpoch: `static` → `changed` | routing continuity |
| F55 | PDCP-RLC backpressure | B | Backpressure: `off` → `on` | buffer occupancy |
| F56 | RLC-MAC grant fragmentation | B | GrantBytes: `1500` → `200` | segmentation delay |
| F57 | Packet lineage | A | Lineage: `disabled` → `enabled` | orphan detection |
| F58 | First delivery de-duplication | A | Deduplication: `off` → `on` | goodput accounting |
| F59 | Byte conservation | A | Fault: `none` → `drop_one_byte` | fault detection |
| F60 | Multi-bearer isolation | B | BearerCount: `1` → `8` | state leakage |
| F61 | Runtime scaling | A | Flows: `10` → `1000` | runtime|memory |
| F62 | Serial versus parallel | A | Execution: `serial` → `parallel` | determinism |
| F63 | End-to-end connected-mode | C | Profile: `PHY_only` → `connected_stack` | latency|goodput |
| F64 | Handover under traffic | C | Mobility: `static` → `handover` | interruption|loss |

Statistical requirements:

```text
Wilson intervals for ordinary rates
one-sided exact Clopper–Pearson bounds for zero false delivery/state leakage
McNemar for paired binary delivery/drop outcomes
paired bootstrap intervals for latency, goodput, bytes, runtime and memory
Holm correction within related families
predefined practical engineering margins
INCOMPLETE or INCONCLUSIVE when evidence is insufficient
```

A performance improvement cannot override a malformed PDU, wrong state transition, integrity failure, duplicate first delivery or conservation error.

# Part M — Required CSVs

Generate every base CSV from the live production execution:

- `protocol_run_manifest.csv`
- `protocol_capability_resolution.csv`
- `protocol_event_log.csv`
- `rlc_entity_config.csv`
- `rlc_pdu_encoding.csv`
- `rlc_am_state_events.csv`
- `rlc_status_pdus.csv`
- `rlc_um_reassembly.csv`
- `protocol_timer_state.csv`
- `pdcp_count_state.csv`
- `pdcp_pdu_encoding.csv`
- `pdcp_security_results.csv`
- `pdcp_reordering_discard.csv`
- `pdcp_duplication_routing.csv`
- `sdap_qfi_drb_mapping.csv`
- `sdap_pdu_encoding.csv`
- `sdap_end_marker_events.csv`
- `rrc_asn1_messages.csv`
- `rrc_transaction_events.csv`
- `rrc_state_transitions.csv`
- `radio_bearer_config.csv`
- `security_mode_events.csv`
- `handover_events.csv`
- `nas_n1n2_bridge.csv`
- `traffic_packet_arrivals.csv`
- `traffic_sessions.csv`
- `traffic_pdu_sets.csv`
- `protocol_lineage.csv`
- `protocol_conservation.csv`
- `protocol_receiver_metrics.csv`
- `protocol_negative_tests.csv`
- `protocol_independent_vector_results.csv`
- `protocol_test_summary.csv`
- `protocol_image_semantic_audit.csv`

Also generate all 16 impact CSVs listed in `desired_protocol_impact_csv_contract.csv`.

# Part N — Required figures

Generate the 22 base figures:

- `rlc_am_window_timeline.png` ← `rlc_am_state_events.csv`
- `rlc_status_nack_map.png` ← `rlc_status_pdus.csv`
- `rlc_um_reassembly_timeline.png` ← `rlc_um_reassembly.csv`
- `rlc_segmentation_resegmentation.png` ← `rlc_pdu_encoding.csv`
- `pdcp_count_hfn_timeline.png` ← `pdcp_count_state.csv`
- `pdcp_reordering_window.png` ← `pdcp_reordering_discard.csv`
- `pdcp_security_flow.png` ← `pdcp_security_results.csv`
- `pdcp_duplication_paths.png` ← `pdcp_duplication_routing.csv`
- `sdap_qfi_drb_map.png` ← `sdap_qfi_drb_mapping.csv`
- `sdap_end_marker_timeline.png` ← `sdap_end_marker_events.csv`
- `rrc_message_sequence.png` ← `rrc_transaction_events.csv`
- `rrc_state_machine.png` ← `rrc_state_transitions.csv`
- `rrc_transaction_timeline.png` ← `rrc_transaction_events.csv`
- `radio_bearer_stack.png` ← `radio_bearer_config.csv`
- `security_activation_timeline.png` ← `security_mode_events.csv`
- `handover_sequence.png` ← `handover_events.csv`
- `traffic_packet_arrivals.png` ← `traffic_packet_arrivals.csv`
- `traffic_pdu_set_latency.png` ← `traffic_pdu_sets.csv`
- `protocol_lineage_graph.png` ← `protocol_lineage.csv`
- `protocol_conservation_balance.png` ← `protocol_conservation.csv`
- `protocol_latency_cdf.png` ← `protocol_receiver_metrics.csv`
- `protocol_end_to_end_goodput.png` ← `protocol_receiver_metrics.csv`

Generate the 30 impact figures:

- `protocol_impact_rlc_sn_overhead.png` ← `protocol_impact_rlc.csv`
- `protocol_impact_rlc_polling.png` ← `protocol_impact_rlc.csv`
- `protocol_impact_rlc_timers.png` ← `protocol_impact_rlc.csv`
- `protocol_impact_rlc_status.png` ← `protocol_impact_rlc.csv`
- `protocol_impact_pdcp_sn_count.png` ← `protocol_impact_pdcp.csv`
- `protocol_impact_pdcp_reordering.png` ← `protocol_impact_pdcp.csv`
- `protocol_impact_pdcp_security.png` ← `protocol_impact_pdcp.csv`
- `protocol_impact_pdcp_duplication.png` ← `protocol_impact_pdcp.csv`
- `protocol_impact_sdap_mapping.png` ← `protocol_impact_sdap.csv`
- `protocol_impact_sdap_end_marker.png` ← `protocol_impact_sdap.csv`
- `protocol_impact_rrc_codec.png` ← `protocol_impact_rrc.csv`
- `protocol_impact_rrc_setup.png` ← `protocol_impact_rrc.csv`
- `protocol_impact_rrc_security.png` ← `protocol_impact_rrc.csv`
- `protocol_impact_bearer_commit.png` ← `protocol_impact_rrc.csv`
- `protocol_impact_rrc_resume.png` ← `protocol_impact_rrc.csv`
- `protocol_impact_handover_ttt.png` ← `protocol_impact_handover.csv`
- `protocol_impact_handover_continuity.png` ← `protocol_impact_handover.csv`
- `protocol_impact_t304.png` ← `protocol_impact_handover.csv`
- `protocol_impact_traffic_arrivals.png` ← `protocol_impact_traffic.csv`
- `protocol_impact_packet_size.png` ← `protocol_impact_traffic.csv`
- `protocol_impact_pdu_set_deadline.png` ← `protocol_impact_traffic.csv`
- `protocol_impact_qos_mix.png` ← `protocol_impact_traffic.csv`
- `protocol_impact_lineage_faults.png` ← `protocol_impact_lineage.csv`
- `protocol_impact_conservation.png` ← `protocol_impact_lineage.csv`
- `protocol_impact_runtime_scaling.png` ← `protocol_impact_runtime.csv`
- `protocol_impact_memory_scaling.png` ← `protocol_impact_runtime.csv`
- `protocol_impact_reproducibility.png` ← `protocol_impact_runtime.csv`
- `protocol_impact_interactions.png` ← `protocol_impact_interactions.csv`
- `protocol_impact_effect_forest.png` ← `protocol_impact_pairwise_effects.csv`
- `protocol_impact_end_to_end.png` ← `protocol_impact_summary.csv`

Every figure is generated from its declared CSV. Record source CSV SHA-256, PNG SHA-256, dimensions, title, axes, plotted-series count and finite-point count in the semantic-audit CSV.

# Part O — Typed errors

| Error ID | Meaning |
|---|---|
| `sixgr:protocol:UnsupportedCapability` | Unsupported feature tuple requested. |
| `sixgr:rlc:InvalidSNLength` | RLC SN length is not permitted for the mode/bearer. |
| `sixgr:rlc:MalformedPDU` | RLC PDU header/length/reserved fields are invalid. |
| `sixgr:rlc:WindowViolation` | SN is outside the applicable receiving/transmitting window. |
| `sixgr:rlc:TimerStateViolation` | RLC timer transition is illegal. |
| `sixgr:rlc:StatusEncodingFailed` | STATUS PDU cannot represent the requested report. |
| `sixgr:pdcp:CountExhausted` | PDCP COUNT would wrap or exceed its valid range. |
| `sixgr:pdcp:MalformedPDU` | PDCP PDU/control PDU is invalid. |
| `sixgr:pdcp:SecurityContextMissing` | Required security context is absent or inactive. |
| `sixgr:pdcp:IntegrityFailure` | PDCP integrity verification failed. |
| `sixgr:pdcp:ReorderingStateViolation` | PDCP reordering state/context is inconsistent. |
| `sixgr:sdap:MissingQFIMap` | QFI has no valid DRB/default mapping. |
| `sixgr:sdap:MalformedPDU` | SDAP header/control PDU is invalid. |
| `sixgr:rrc:ASN1ConstraintViolation` | RRC message violates ASN.1 constraints. |
| `sixgr:rrc:UPERDecodeFailed` | RRC UPER decoding failed. |
| `sixgr:rrc:TransactionMismatch` | RRC transaction ID/source/state mismatch. |
| `sixgr:rrc:ProcedureTimerExpired` | RRC procedure timer expired. |
| `sixgr:rrc:BearerCommitFailed` | Atomic bearer configuration commit failed. |
| `sixgr:rrc:HandoverStateViolation` | Handover event is illegal in current state. |
| `sixgr:rrc:ExternalNASRequired` | An external NAS/5GC result is required. |
| `sixgr:traffic:InvalidTrafficProfile` | Traffic profile/session parameters are invalid. |
| `sixgr:traffic:NonDeterministicStream` | Traffic source did not use its declared named stream. |
| `sixgr:protocol:LineageViolation` | A protocol object has missing/duplicate/invalid lineage. |
| `sixgr:protocol:ConservationFailure` | Cross-layer byte/bit conservation failed. |

Every negative case must prove:

```text
ActualError == ExpectedError
StateChanged == false
PDUProduced == false
DeliveryCounted == false
```

# Part P — Tests to add

Implement every test in `protocol_matlab_test_plan.csv`. Also run all existing repository tests that exercise RLC, PDCP, SDAP, RRC, traffic, handover, MAC and PHY integration.

Minimum commands:

```bash
python tests/vectors/protocol/verify_protocol_vector_pack.py

matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*RLC*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PDCP*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*SDAP*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*RRC*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Traffic*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Handover*'); assertSuccess(r);"

matlab -batch "addpath(pwd); s=sixgr.protocol.runProtocolStackPhaseValidation( ...
 'VectorRoot',fullfile(pwd,'tests','vectors','protocol'), ...
 'OutputDir',fullfile(pwd,'artifacts','protocol_stack_phase'), ...
 'SeedList',[11 23 47 89], ...
 'ConfidenceLevel',0.95, ...
 'Strict',true); assert(s.Passed);"

python tests/vectors/protocol/verify_protocol_artifacts.py artifacts/protocol_stack_phase

matlab -batch "addpath(pwd); s=sixgr.protocol.runProtocolStackImpactAnalysis( ...
 'ExperimentMatrix',fullfile(pwd,'tests','vectors','protocol','protocol_impact_experiment_matrix.csv'), ...
 'OutputDir',fullfile(pwd,'artifacts','protocol_stack_impact'), ...
 'SeedList',[11 23 47 89 131 197], ...
 'ConfidenceLevel',0.95, ...
 'Strict',true); assert(s.Passed);"

python tests/vectors/protocol/verify_protocol_impact_artifacts.py artifacts/protocol_stack_impact

matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

# Part Q — Execution order

Implement in this dependency order:

```text
1. Protocol identities, event store, capability planner
2. RLC exact codecs and state machines
3. PDCP exact codecs, COUNT and security
4. SDAP exact codecs and mapping state
5. ASN.1 module registry and independent vectors
6. RRC setup/security/capability/reconfiguration/release
7. Atomic bearer configuration
8. Traffic packet/session/PDU-set engine
9. Cross-layer lineage and conservation
10. Handover/re-establishment/resume
11. Impact campaigns and artifacts
12. Complete repository regression
```

Do not attempt a one-file patch. Make phase-sized commits with tests.

# Part R — Codex response contract

At the end of every response report:

```text
phase/task IDs
findings addressed
files changed
production integration path
algorithms and spec clauses implemented
tests added
exact commands executed
pass/fail/skip/block counts
vector mismatches
CSV row counts and hashes
PNG dimensions and hashes
remaining unsupported tuples
next dependency-ordered task
```

Do not say `COMPLETE` while any of these remain:

```text
RLC custom simplified header or STATUS PDU
AM restricted to 12-bit SN
PollEveryNPDU as strict polling authority
slot-heuristic RLC timers
PDCP SN used without HFN/COUNT
PDCP XOR or SHA-256 security in strict path
custom 0xF0 ROHC
missing exact PDCP control PDU for an enabled profile
SDAP custom/common header for both directions
missing QFI mapping replaced by DefaultLCID
RRC JSON on the strict wire
custom SIB1 anchor format labelled Release-18 UPER
enabled RRC message without independent frozen vector
local state set to CONNECTED without decoded peer completion
partial bearer configuration commit
handover selected from geometry truth
synthetic NAS success
traffic bits-per-TTI as the strict packet model
global rand/randn in strict traffic code
proxy TCP/FTP labelled packet-accurate
orphan lineage nodes
unowned bytes
duplicate first delivery
non-zero conservation error
mandatory test skipped or blocked
mandatory impact point incomplete
any of the 48 CSVs or 52 PNGs missing
artifact verifier nonzero
complete repository regression failing
```

Final completion requires:

```text
all 15 findings closed for enabled tuples
all capability rows resolve EXECUTE or REJECT correctly
all mandatory MATLAB tests execute and pass
all enabled ASN.1 messages have independent frozen UPER vectors
all RLC/PDCP/SDAP mismatch counts are zero
all security vectors pass
all bearer commits are atomic
UE and gNB RRC states converge
bounded handover passes success and failure cases
all traffic sources are deterministic by named stream
zero lineage/conservation errors
all 768 impact experiments execute
all 96 rules have valid evidence
all 48 CSVs pass
all 52 PNGs pass
both artifact verifiers exit 0
complete repository regression passes
```
