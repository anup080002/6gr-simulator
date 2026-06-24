# Phase 5 UL HARQ

Status: focused HARQ surfaces exist; connected UL retransmission evidence
pending.

```mermaid
sequenceDiagram
    participant UE
    participant GNB
    participant PDCCH
    participant PUSCH
    participant HARQ
    UE->>PUSCH: new UL TB
    PUSCH-->>GNB: CRC fail
    GNB->>HARQ: preserve soft buffer and process state
    GNB->>PDCCH: retransmission DCI with NDI and RV
    PDCCH-->>UE: blind decoded grant
    UE->>PUSCH: same TB retransmission
    PUSCH-->>GNB: rate recovery and soft combining
```

The scheduler must not inspect the UE UL queue directly for Phase 5 truth. UL
buffer knowledge must come from decoded SR, BSR, PHR when enabled, and permitted
protocol state.
