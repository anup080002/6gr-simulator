# Honest Unavailable Policy

Browser-owned LLS outputs must never imply that unavailable telemetry was measured.

Rules:

- If a runtime source exists, persist it as a canonical CSV/JSON artifact and add it to the DB-backed artifact manifest.
- If a source does not exist, add an `honest_unavailable_registry` row with `classification_code`, `unavailable_reason`, `required_backend_sources`, `required_capture_point`, `required_runtime_condition`, `next_implementation_step`, and `owner_tag`.
- Do not write fake rows to primary output tables to preserve shape.
- Do not write fake plot PNG/SVG files for unavailable plots.
- Do not substitute configured inputs into measured or outcome columns without `value_source`, `value_role`, and `value_status`.
- Do not silently select stale mirror artifacts as browser truth.

The browser renders unavailable outputs as status cards using the registry and manifest metadata. The unavailable registry is a contract for future instrumentation, not a simulation result.
