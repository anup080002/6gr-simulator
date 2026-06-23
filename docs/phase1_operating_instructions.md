# Phase 1 Operating Instructions

Use Phase 1 instrumentation to diagnose infrastructure and reporting failures only.

Do not use it to claim that SSB, PBCH, SIB1, PRACH, RACH, PDCCH, PUCCH, PDSCH, PUSCH, HARQ, SRS, TRS, channel/RF, rank adaptation, or MU-MIMO are implemented. Those blocks require later live PHY/MAC evidence.

Focused validation command:

```matlab
setup6GRSimToolkit('Verbose',false);
testRuntimeEvidenceBus;
testBlockScope;
testArtifactTransaction;
testRuntimeMessageTracker;
testTruthEvaluator;
```

For a reporting run, inspect:

- `runtime/journal/*.jsonl`
- `runtime/csv/progress_heartbeat.csv`
- `runtime/csv/stage_timing_events.csv`
- `runtime/csv/artifact_transactions.csv`
- `runtime/csv/block_call_trace.csv`
- `runtime/csv/message_flow.csv`

If a run completes with missing mandatory PHY evidence, the correct root result remains `ResultOk=false`.
