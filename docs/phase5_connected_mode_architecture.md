# Phase 5 Connected-Mode Architecture

Status: scaffold and baseline audit. This document does not claim Phase 5 is
complete.

The current codebase has live pieces for abstract RRC, SRB1 helper stacks,
PDCCH/PDSCH/PUSCH/PUCCH waveform blocks, MAC scheduling, HARQ state and trace
writing. The connected-mode truth gap is ownership: the UE must consume
dedicated configuration from decoded RRC, then derive DL and UL grants only from
blindly decoded C-RNTI PDCCH DCI.

## Current Boundary

`Phase5Ok` is false until every Phase 5 gate is backed by live runtime evidence.
The baseline maps under `phase5_baseline/` identify whether each surface is
live production, standalone diagnostic, configuration-only, incomplete, or
unsupported.

```mermaid
flowchart LR
    RRC[RRCSetupComplete] --> SRB1[SRB1 PDCP/RLC]
    SRB1 --> MAC[MAC SDU/PDU]
    MAC --> SCH[PF/RR Scheduler]
    SCH --> PDCCH[C-RNTI PDCCH]
    PDCCH --> PDSCH[PDSCH grant]
    PDCCH --> PUSCH[PUSCH grant]
    PDSCH --> PUCCH[PUCCH HARQ feedback]
    PUCCH --> HARQ[HARQ state]
    PUSCH --> HARQ
    HARQ --> SCH
```

## Sequence A: RRCSetupComplete

```mermaid
sequenceDiagram
    participant UE
    participant SRB1
    participant PDCCH
    participant PUSCH
    participant GNB
    UE->>SRB1: RRCSetupComplete ASN.1 bytes
    SRB1->>PUSCH: MAC SDU on dynamic UL grant
    GNB->>PDCCH: C-RNTI UL DCI
    PDCCH-->>UE: Blind decoded grant
    UE->>PUSCH: Live UL waveform
    PUSCH-->>GNB: TB CRC and MAC parse
    GNB->>GNB: ASN.1 decode and activate context
```

Current status: pending. The existing RRC path uses simulator JSON bytes.

## Sequence B: DL New Transmission And ACK

```mermaid
sequenceDiagram
    participant GNB
    participant PDCCH
    participant UE
    participant PDSCH
    participant PUCCH
    GNB->>PDCCH: C-RNTI DCI 1_0 or required connected DCI
    PDCCH-->>UE: Blind decode
    GNB->>PDSCH: DL-SCH/PDSCH waveform
    PDSCH-->>UE: TB CRC pass
    UE->>PUCCH: ACK UCI
    PUCCH-->>GNB: decoded ACK
    GNB->>GNB: HARQ process completes
```

Current status: partial. Focused PDCCH, PDSCH and PUCCH evidence exists; full
connected grant lineage is pending.

## Sequence C: DL NACK And Retransmission

```mermaid
sequenceDiagram
    participant UE
    participant GNB
    participant PUCCH
    participant HARQ
    participant PDSCH
    UE->>PUCCH: NACK or DTX evidence
    PUCCH-->>GNB: decoded feedback with DTX distinguished
    GNB->>HARQ: update process and RV
    HARQ->>PDSCH: same TB retransmission
    PDSCH-->>UE: rate recovery and soft combining
```

Current status: partial in focused HARQ paths, pending connected packet
delivery.

## Sequence D: UL SR, BSR, Grant And New Transmission

```mermaid
sequenceDiagram
    participant UE
    participant PUCCH
    participant GNB
    participant PDCCH
    participant PUSCH
    UE->>PUCCH: SR
    PUCCH-->>GNB: decoded SR
    GNB->>PDCCH: UL grant
    PDCCH-->>UE: blind decoded DCI
    UE->>PUSCH: MAC PDU with BSR
    PUSCH-->>GNB: decoded BSR and TB CRC
```

Current status: helpers exist, connected source guard pending.

## Sequence E: UL Retransmission And Soft Combining

```mermaid
sequenceDiagram
    participant GNB
    participant PDCCH
    participant UE
    participant PUSCH
    participant HARQ
    GNB->>HARQ: UL TB CRC fail
    GNB->>PDCCH: retransmission DCI with RV
    PDCCH-->>UE: blind decoded retransmission grant
    UE->>PUSCH: same TB and RV
    PUSCH-->>GNB: rate recovery and soft combining
```

Current status: focused soft-combining helper exists, connected UL loop
pending.

## Sequence F: Packet Queue To Delivery

```mermaid
sequenceDiagram
    participant App
    participant Queue
    participant MAC
    participant PHY
    participant HARQ
    participant Sink
    App->>Queue: packet_id
    Queue->>MAC: MAC SDU
    MAC->>PHY: TB mapping
    PHY-->>HARQ: CRC and feedback
    HARQ-->>PHY: retx if required
    PHY->>Sink: deliver once
```

Current status: pending canonical Phase 5 packet lineage.
