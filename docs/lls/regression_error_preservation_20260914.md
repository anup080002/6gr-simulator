# Preserve original regression failure diagnostics

This diagnostic repair is **not MATLAB-runtime-validated**. It does not establish
a testAll pass, fix memory exhaustion, or qualify the integrated 12 dB scenario.

The retained checkpoint log recorded `MATLAB:nomem` in scenario execution and
artifact recovery, followed by another exception from `getReport` inside the
test runner's catch block. The extended diagnostic call preceded recording the
suite failure and terminal test marker. Main's separate native crash is not
explained by this observation.

Full and focused runners now set failed state before optional extended error
rendering. `sixgr.util.formatExceptionDiagnostic` retains the original identifier
and message if rendering fails or returns invalid text, and records the renderer
error separately. The server wrapper also preserves the original exception when
writing the failed summary raises a secondary error. No failed assertion is
weakened, no test is omitted and no physical result is synthesized.

The new regression exercises successful formatting and declared diagnostic-only
failures. It does not deliberately exhaust memory. Total memory exhaustion,
allocation failure in the minimal diagnostic itself, failed stderr I/O and native
crashes can still prevent diagnostics; this is not a guarantee of recovery.

Five changed MATLAB files passed native static checks; the intentionally malformed
control was detected. The first control attempt produced EOLPAR instead of SYNER
and failed packaging; that attempt is preserved. Current syntax rejection checks
both IDs. Read-only patch checks passed against integrated main, and reverse
application passed against the candidate. The older running development checkout
does not have main's new test registrations, so its apply check correctly failed.

The first post-application byte check detected Git's configured CRLF conversion
on new source files. It stopped before committing. Comparison of every applied
file against its retained candidate therefore records both the actual byte hash
and equality after CRLF-to-LF normalization; no source content is substituted.

Before applying this patch, the queued check of `03f6d6c7` exhausted 20 resource
checks and exited without launching MATLAB. Its minimum remained 2097152 KB free
memory; the last observation was 1158776 KB. Both original MATLAB workers were
left running. This is a resource-deferred test, not a failed PHY test.

Local evidence: `logs/pending_integration_evidence_20260913/` contains the
`regression_error_reporting_candidate_01` source/static receipts and immutable
archive, plus `main_consolidation_20260914_01/focused_preflight_terminal_01.json`.
The patch and archive hashes before application are respectively:

- `4B1C5B646E687ADC5820AA3799C5B69C0B08A3990515BFE5C37CCE06A1B5A663`
- `2D37D5C0E0D2EE8396C69EB2B0E2ABC06E4A2C625F1F20A9232553241631CC2E`

Still required: actual diagnostic/runner failure tests, integrated receiver tests,
final-source testAll and NR/config/strict/export/E2E/scenario guards. Detector
qualification, normal mixed feedback, all-measurement/CSV/PNG validation and the
12 dB/sweep/long-study objectives remain open.
