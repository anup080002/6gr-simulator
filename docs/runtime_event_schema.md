# Runtime Event Schema

Phase 1 runtime evidence is append-only. The authoritative files live under:

- `runtime/journal/runtime_events.jsonl`
- `runtime/journal/message_events.jsonl`
- `runtime/journal/value_events.jsonl`
- `runtime/journal/artifact_events.jsonl`
- `runtime/journal/warning_exception_events.jsonl`

Derived CSV views live under `runtime/csv/` and must not be treated as the authoritative source.

Every event carries run identity, event identity, global and worker sequence numbers, UTC timestamp, monotonic time, simulation context, block/call identifiers, status, reason code, message, and evidence class.

Allowed evidence classes are:

- `LIVE_RUNTIME`
- `LIVE_RUNTIME_BOUNDARY`
- `RUNTIME_DERIVED`
- `CONFIGURATION_ONLY`
- `STATIC_SOURCE_INFERENCE`
- `DIAGNOSTIC_PROBE`
- `PLACEHOLDER`
- `UNAVAILABLE`

Configuration-only, static-source, diagnostic, placeholder, and unavailable evidence must not satisfy mandatory live-runtime gates.
