# CODEX PROMPT 15 — Canonical secure WebGUI, operations, YAML integration, and measured-results dashboard

You are the lead software architect, FastAPI security engineer, React/TypeScript UX engineer, MATLAB orchestration owner, artifact-provenance engineer and operations maintainer for this 6GR simulator repository.

## Mission

Modify the production repository. Do not return a review-only answer or a list of suggestions.

Delete the old single-file WebGUI **only after** all required feature parity has been implemented and tested in the new React/FastAPI stack. The final repository must contain one canonical WebGUI, one public same-origin endpoint and one run/config/artifact data model.

The user requires the public service to bind to `0.0.0.0` so it is reachable using both `localhost` and the machine's LAN address. Keep this requirement. Security must be achieved through a single protected origin, authentication, authorization, TLS profile, host validation, CSRF, quotas, path isolation and auditability—not by changing the bind to loopback.

The WebGUI must consume the real simulator YAML, execute the exact edited/resolved YAML, and display all actual measured/decoded/derived artifacts. Never create a placeholder CSV, zero-filled plot, copied image or synthetic result merely to make the dashboard look complete.

Use these audit inputs copied under `audit/webgui_security_operations/`:

- `webgui_security_operations_12_findings.csv`
- `current_webgui_static_audit.csv`
- `webgui_source_change_map.csv`
- `webgui_implementation_task_graph.csv`
- `webgui_test_plan.csv`
- `webgui_role_permission_matrix.csv`
- `webgui_route_authorization_matrix.csv`
- `webgui_deployment_profiles.yaml`
- `webgui_security_policy.yaml`
- `webgui_yaml_ui_mapping_contract.csv`
- `webgui_parameter_coverage_summary.csv`
- `dashboard_visual_reference_catalog.csv`
- `dashboard_dut_visualization_catalog.csv`
- `dashboard_artifact_registry.csv`
- `dashboard_artifact_manifest_schema.json`
- `webgui_api_contract.json`
- all test-vector CSVs and visual references in this pack.

## Non-negotiable engineering rules

1. Do not keep two live WebGUI backends.
2. Do not delete the old dashboard until parity tests prove that required configuration, run, live, results, plots, tables, compare, artifact and parameter-catalog functions exist in the new stack.
3. Do not copy code blindly from the old dashboard. Port behavior into typed modules and remove insecure semantics.
4. Do not store or compare plaintext passwords. Do not provide default usernames or passwords.
5. Do not put session IDs, access tokens or refresh tokens in `localStorage` or `sessionStorage`.
6. Do not expose a state-changing endpoint without authentication, CSRF protection and an explicit permission.
7. Do not trust a client-supplied run ID, path, filename, YAML path, result directory or artifact path.
8. Do not allow `../`, absolute paths, drive paths, UNC paths, symlink escapes or substring run-directory matching.
9. Do not run a scenario path from the browser directly. Run an immutable server-created `resolved_scenario.yaml` identified by a revision and SHA-256.
10. Do not list or read scenarios from legacy `configs/scenarios/`. The only active scenario root is `simulator/configs/scenarios/`.
11. Do not keep raw YAML as the primary configuration UI. Use schema-generated structured forms; raw YAML is an Advanced tab.
12. Do not hide a catalog parameter. Every catalog path must be mapped to a UI section/widget or explicitly marked unsupported with a reason.
13. Do not store UI-only SNR, slot, MCS, speed or other overrides that MATLAB never receives.
14. Do not use configured values as measured results. Every result card must show provenance.
15. Do not draw a Plotly curve when the required actual source CSV/columns are missing. Show `Unavailable` and the exact reason.
16. Do not copy the attached visual-reference images into a run folder or use them as evidence. They are design archetypes only.
17. Do not hard-code the artifact gallery. Generate it from the run artifact manifest and the registry.
18. Do not use `uvicorn --reload`, `npm install` on every start, or two separately exposed dev servers in deployed mode.
19. Do not silently continue in LAN/shared mode when the persistent database required for identity, ACL, session and job state is unavailable.
20. Do not mark this phase complete when a mandatory backend, frontend, Playwright, security or MATLAB-integration test is skipped or blocked.

## Required final architecture

### One public process/origin

Implement a canonical application factory. In deployed mode, FastAPI serves:

```text
https://<host>:<port>/              React production build
https://<host>:<port>/api/v1/...   REST API
wss://<host>:<port>/ws/runs/...    WebSocket
```

The listening host is always:

```text
0.0.0.0
```

Print both usable browser URLs:

```text
https://localhost:<port>
https://<detected-or-configured-LAN-IP>:<port>
```

Do not tell the user to browse to `0.0.0.0`; it is a bind address.

Development may use Vite through an exact-origin proxy, but deployed acceptance must use the built frontend under the same origin. CORS is unnecessary in same-origin production. If retained for development, list exact origins and methods/headers; never use wildcard credentials.

Profiles:

```text
local_dev
    bind 0.0.0.0
    authentication mandatory
    SQLite permitted only for explicitly single-user development
    TLS development certificate preferred
    HTTP requires explicit acknowledgement and a visible insecure-development banner

lan_secure
    bind 0.0.0.0
    TLS mandatory
    persistent database mandatory
    authentication/RBAC/session/CSRF mandatory
    Secure cookie and HSTS mandatory
    explicit TrustedHost allowlist mandatory
    startup fails on default secrets, default DB credentials or missing dependencies
```

### Backend module boundaries

Create typed packages such as:

```text
webgui/backend/app/
    application.py
    settings.py
    middleware/
        request_id.py
        security_headers.py
        csrf.py
        fetch_metadata.py
    auth/
        models.py
        password.py
        session.py
        dependencies.py
        bootstrap.py
    authorization/
        permissions.py
        policy.py
        run_acl.py
    config/
        catalog.py
        roundtrip_yaml.py
        schema_validation.py
        inheritance.py
        revisions.py
        resolution.py
    runs/
        models.py
        service.py
        queue.py
        worker.py
        process_control.py
        quotas.py
        recovery.py
    artifacts/
        manifest.py
        registry.py
        indexer.py
        preview.py
        plot_recipe.py
    results/
        service.py
        comparison.py
        validation.py
    audit/
        models.py
        service.py
    operations/
        health.py
        metrics.py
        retention.py
        backup.py
```

Maintain clean dependency direction. Routers call services; services call repositories; repositories own persistence. No router may manipulate `Path`, `subprocess`, SQLAlchemy sessions or MATLAB commands directly.

### Persistent entities

Implement migrations for at least:

```text
User
Role / UserRole
PasswordCredential
Session
LoginAttempt
ConfigRevision
ConfigRevisionParent
Run
RunACL
Job
WorkerLease
QuotaPolicy
QuotaUsage
Artifact
ArtifactRelation
ValidationSummary
AuditEvent
```

A run must record:

```text
RunID and RunTag
OwnerUserID
Share ACL
Scenario ID
ConfigRevisionID
source/effective/resolved YAML hashes
resolved YAML path under the run staging area
profile and run class
source commit
MATLAB and Toolbox identity
queue/job/process identity
start/end/status/exit code
artifact manifest hash
```

## Authentication and session implementation

Use Argon2id through a maintained library. Persist only the encoded Argon2id hash. Generate a one-time bootstrap token on first start or require an environment-supplied bootstrap secret. Once the first admin exists, disable bootstrap.

Password policy:

```text
minimum 15 characters for single-factor login
support at least 64 characters
allow spaces and Unicode
no arbitrary composition rule
block common/known-compromised passwords
allow password managers and paste
authentication rate limiting and audit
```

Session design:

```text
256-bit or stronger opaque random session ID
database stores only a hash of the session token
cookie name __Host-sixgr_session under HTTPS
Path=/, no Domain, HttpOnly, SameSite=Strict, Secure in HTTPS
rotate at login and privilege/password changes
idle timeout and absolute timeout
server-side revocation and logout-all-sessions
IP/user-agent metadata for anomaly/audit, not brittle authorization
```

Do not implement SPA JWT storage in localStorage.

## CSRF, browser and transport protections

For all state-changing HTTP operations:

```text
verify authenticated session
verify CSRF token
verify Origin or Referer against configured target origin
apply Fetch Metadata policy
apply permission and resource ownership
log success/failure without secret values
```

Use a synchronizer-token or signed double-submit design. The React axios client must attach the token through a custom header. SameSite is defense in depth, not the only control.

Add:

```text
TrustedHostMiddleware
HTTPS redirect/enforcement in lan_secure
HSTS in lan_secure
Content-Security-Policy
X-Content-Type-Options: nosniff
Referrer-Policy
frame-ancestors 'none'
Permissions-Policy
safe cache controls for auth/config/result pages
```

Authenticate WebSocket upgrade using the same server-side session, validate the Origin, authorize run access and re-check authorization for any control message. Prefer read-only WebSocket traffic. If stop remains available over WS, it requires the same permission and CSRF-equivalent nonce/control token as HTTP.

## RBAC and run ownership

Implement roles:

```text
Admin
Operator
Researcher
Viewer
Auditor
```

Use the exact matrix in `webgui_role_permission_matrix.csv`. The central policy is deny-by-default and applies to every route and WebSocket message.

Core rules:

```text
Researcher can create, read, stop and delete own runs.
Operator can operate shared/assigned runs and workers.
Viewer can read only runs shared with the viewer.
Auditor can read all runs, artifacts, validation and audit records but cannot mutate simulation state.
Admin can manage users, quotas, all runs, retention and system settings.
```

A user cannot discover another user's private run through list/search/autocomplete, timing, artifact ID or WebSocket channel.

## YAML/configuration implementation

### Active source root

Use only:

```text
simulator/configs/scenarios/
```

Explicitly reject the legacy root:

```text
configs/scenarios/
```

The two first-class canonical cards are:

```text
lls_true_snr_sweep_awgn_1ue.yaml
lls_true_geometry_2cell_2ue_200kmh.yaml
```

Keep fixed-link calibration and geometry/system modes visually and semantically separate.

### Round-trip engine

Add `ruamel.yaml` or another proven round-trip parser. Configure duplicate-key rejection. Apply limits for size, aliases, node count and nesting. Resolve inheritance only through allowlisted relative paths under the active config root or approved fragment roots. Reject cycles, absolute paths and symlink escapes.

Create immutable `ConfigRevision` records with:

```text
source YAML text/hash
parent revision
structured patch operations
author and timestamps
validation report
effective merged YAML/hash
resolved canonical YAML/hash
parameter catalog version
schema/constraint versions
```

### Structured UI

Generate the form from:

```text
simulator/configs/schema/core_parameter_catalog.yaml
simulator/configs/schema/scenario_parameter_catalog.yaml
scenario_parameter_catalog_extension_01..07.yaml
scenario_parameter_matrix_catalog.yaml
parameter_constraints.json
ui_parameter_taxonomy.yaml
```

Use `webgui_yaml_ui_mapping_contract.csv` as the minimum coverage contract. Required sections:

```text
Scenario/Profile
Frame, Grid, Numerology and Duplexing
Waveform
PDSCH / DL-SCH
PUSCH / UL-SCH
PDCCH / DCI
PUCCH / UCI
SSB / Initial Access / SIB1 / Random Access
Reference Signals / Measurements / Link Adaptation
MIMO / CSI / Precoding / Beamforming
Channel / Geometry / Mobility / Interference
RF / Front End / Power Control
MAC / HARQ / Scheduler
RLC / PDCP / SDAP / RRC / Traffic
Outputs / Validation
Advanced Research
```

Geometry must include the OSM map and synchronized coordinate/trajectory editor. Raw YAML appears only in `Advanced`. Add tabs:

```text
Source
Effective after inheritance
Resolved canonical configuration
Diff from source/baseline
Validation and dependency messages
```

Unknown or unsupported parameters remain visible in Advanced and block a strict run unless explicitly permitted by the selected study profile.

### Launch contract

The browser sends a `ConfigRevisionID`, not a file path. The backend:

1. authorizes access;
2. validates the revision;
3. resolves inheritance and constraints;
4. writes immutable `resolved_scenario.yaml` in a newly allocated run staging directory;
5. writes a command manifest with the resolved SHA-256;
6. launches MATLAB using that exact resolved path;
7. records the resolved hash in run and artifact manifests.

Prove in a test that changing a UI parameter changes the resolved file and the MATLAB dry-run command. Remove `snr_db` and `slot_steps` as disconnected request fields; they must edit actual catalog paths or disappear.

## Run queue, process control and quotas

Replace `_runs` with persistent jobs. Implement atomic states such as:

```text
DRAFT
VALIDATED
QUEUED
STARTING
RUNNING
STOP_REQUESTED
STOPPING
COMPLETED
FAILED
STOPPED
QUOTA_EXCEEDED
LOST_WORKER
RECOVERING
```

Use one worker/lease model and a process group/job object. Capture stdout/stderr to immutable logs. On stop:

```text
record authorized stop request
graceful terminate
wait configured grace interval
kill process group if required
record every child/process result
finalize artifacts and status
```

Enforce configurable per-user and global:

```text
active/queued run count
CPU and memory reservation
wall-clock limit
disk limit
upload size
artifact preview rows/download policy
WebSocket and API rate limits
```

Reserve quota atomically before queueing. Reconcile running jobs after server restart. A run may not silently continue as `unknown` in memory.

## Artifact manifest and actual-data rule

At run completion and during live indexing, build `artifact_manifest.json` according to `dashboard_artifact_manifest_schema.json`.

Every artifact has an opaque `ArtifactID`, exact run ID, relative path, type, byte count, SHA-256, schema, provenance, validity, generation time and relations.

For a PNG, record:

```text
source CSV artifact IDs and hashes
plot recipe ID/version
required columns
truth/provenance classification
image dimensions
image SHA-256
semantic audit state
```

Allowed evidence badges:

```text
Measured runtime
Decoded runtime
Derived from measured runtime
External independent oracle
Configured
Diagnostic only
Unavailable
Invalid/stale
```

Only the first four may satisfy applicable evidence gates. Configured and diagnostic values remain visible but are never labelled measured.

Do not scan the entire results tree on every request. Do not resolve a run by substring. The database and manifest provide the exact run directory and artifact identities.

Large CSV handling must be bounded and paginated. Never load an unbounded multi-gigabyte file into one API response. Use streaming, indexed Parquet/DuckDB/Arrow or a similarly bounded design where appropriate.

## Dashboard design implementation

Implement the information architecture in `DASHBOARD_INFORMATION_ARCHITECTURE.md`.

### Global run selector

A searchable run dropdown is visible on every authenticated page. It includes:

```text
run ID/tag
scenario
profile/run class
owner/share state
status
start time
source commit
artifact completeness
validation status
```

Selection is reflected in the URL and persisted in application state. Every Results, Validation, Live, Compare and Artifact Explorer request uses the selected run ID and is ACL checked.

### Results and Validation

The UI must consume `dashboard_artifact_registry.csv` and `dashboard_dut_visualization_catalog.csv`, not a six-file hard-coded map.

For every domain/DUT:

- show the high-priority hero plots first;
- show every manifest artifact in the all-artifacts gallery;
- provide filters for direction, UE/cell, base/impact, validity, file type and text;
- show source file, hashes, provenance, generation time, schema and validity;
- permit interactive Plotly reconstruction only when source data and recipe pass;
- display validated PNG otherwise;
- show an explicit unavailable card with reason when missing;
- offer bounded table preview and authorized download;
- support comparison only when operating-point/profile keys are compatible.

Use these visual archetypes from `visual_references/`:

```text
Target-versus-measured tracking with zoom panels
Signal strength along route with linked SER/BLER
Coded/uncoded DUT versus independent BER/BLER reference
Four-panel CIR/PSD/eye/constellation waveform view
EVM per RB and per OFDM symbol
3D antenna radiation pattern
Mobility/channel BER curves
```

Never reuse those files as result images.

### Most important visualization by DUT

Implement all rows in `dashboard_dut_visualization_catalog.csv`. At minimum, the dashboard must provide:

```text
Frame/Grid: slot-symbol map, RE occupancy, K0/K1/K2, BWP/CC map
Waveform: OFDM/CP, PSD, PAPR CCDF, constellation, eye, EVM per RB/symbol
PDSCH: BLER/BER with independent reference, RE/DMRS/PTRS, layers, HARQ
PUSCH: measured-SINR BLER, UCI bits, hopping/DFT/PAPR, SRS/TPMI, power
PDCCH: CORESET/CCE, candidates, detection, false alarm, DCI layout
PUCCH: resource/OCC map, UCI bits, K1/TDD, HARQ codebook, false alarm
Initial Access: SSB/beam, Type-0, PRACH, RA and RRC timeline
RS/LA: RS maps, measurements, CSI Part1/2, MCS/OLLA, tracking
MIMO: array/radiation pattern, codebook beams, RI/PMI, layer SINR, covariance, MU-MIMO/multi-TRP
Channel: trajectory, route power+SER/BLER, CIR/PDP, Doppler, LSPs, interference, ray tracing
RF: target/measurement tracking, CFO/SCO, phase noise, IQ, PA, EVM/ACLR/SEM, blocker, UL power
MAC: HARQ/RV, scheduler, queue/BSR/PHR/TA, delay/fairness, lineage
Protocol: RLC, PDCP, SDAP, RRC/handover, traffic and conservation
Validation: independent comparison, confidence/stopping, provenance, measured SINR and gate waterfall
```

### Validation page

Separate:

```text
Result evidence
Validation gates
Independent reference comparison
Statistical completeness
Artifact/schema/hash audit
Provenance
Test execution
```

A passing plot must never hide an incomplete campaign or failed source schema. Show point status, confidence level, trial/error counts and stop reason.

## Safe file handling

All client-facing APIs use IDs. Never return an absolute filesystem path.

Allowed roots:

```text
active scenario catalog
server-controlled config revision store
server-controlled per-run staging/results root
server-controlled read-only imported-run root
```

Use canonical path resolution with `is_relative_to`, symlink checks and open-file-after-validation semantics. Generate uploaded filenames. Store uploads outside the static web root. Validate extension and content, enforce byte/alias/depth/node limits and never trust `Content-Type` alone.

Downloads use:

```text
GET /api/v1/artifacts/{artifact_id}
```

The server resolves the artifact through the database/manifest, authorizes the run and sends a safe `Content-Disposition` filename.

## Operations, audit and retention

Audit at least:

```text
login success/failure/logout/session revocation
user/role/quota changes
config upload/edit/validate/resolve/publish
run create/start/stop/delete/share
artifact read/download/reindex
validation approval
retention/purge/backup/restore
startup/shutdown/worker lease/recovery
security policy rejection
```

Each record has actor, request ID, run/config/artifact ID, action, result, source IP, timestamp and redacted metadata. Make audit records append-oriented and permission protected.

Provide:

```text
/api/v1/operations/liveness
/api/v1/operations/readiness
/api/v1/operations/metrics
```

Readiness checks identity/session DB, worker lease, results/staging disk, config catalog and required secret/TLS state. In `lan_secure`, DB failure makes readiness false and blocks mutating operations.

Implement explicit retention policies, legal/audit holds, dry-run purge previews, confirmation tokens, backup and restore tests. Never expose a repository-wide unauthenticated clear button.

## Old WebGUI migration and deletion

Use `webgui_decommission_manifest.csv`.

Migration sequence:

1. Capture old feature parity tests.
2. Port required behavior to the canonical stack.
3. Import any persistent run metadata needed from the old database/manifest without importing plaintext credentials or sessions.
4. Run parity, security and E2E acceptance.
5. Delete:

```text
apps/lls_web_dashboard.py
apps/start_lls_web_dashboard.ps1
apps/start_lls_dashboard_edge_stack.ps1
```

6. Rehome or delete old contract helpers after the artifact registry replaces them.
7. Remove docs/tests/imports/launchers referring to the old server.
8. Add CI tests asserting the paths and import references are absent.

Do not leave a disabled copy in the repository that can still be launched.

## Required test implementation

Implement every row in `webgui_test_plan.csv` and all supplied vector files.

### Backend

Use pytest with isolated temporary databases/filesystems. Required test families:

```text
authentication/password/session
CSRF/Origin/Fetch-Metadata
RBAC and run ACL
WebSocket authentication/authorization
path/upload/download isolation
YAML round-trip, inheritance and schema constraints
catalog-to-UI coverage
config revision and resolved launch hash
persistent queue, restart and quotas
artifact manifest, hash, schema and provenance
large CSV pagination
operations/audit/retention/backup
old-stack absence
```

### Frontend

Add Vitest/Testing Library and Playwright. Required checks:

```text
login/session expiry
role-dependent navigation/actions
global run dropdown
mode-first config and all parameter sections
Advanced YAML source/effective/resolved/diff
OSM geometry editor
run queue/live/stop workflow
Results and Validation domain galleries
all-artifact explorer
provenance/validity/unavailable states
run comparison compatibility
large table pagination
responsive layout and keyboard/accessibility basics
```

### Security and dependency gates

Run maintained scanners where available:

```text
pip-audit
npm audit or lockfile scanner
Bandit or equivalent
secret scan
static route/permission coverage
```

Do not mark complete if a required scan cannot execute. Record BLOCKED and leave the relevant gate open.

### MATLAB integration

A dry-run test must prove the exact immutable resolved YAML path/hash enters the MATLAB command. End-to-end tests must run the canonical AWGN and geometry scenarios on the pinned MATLAB/Toolbox release and verify that their generated artifact manifests drive the UI.

## Mandatory commands

Adapt to the repository's environment, but run at least:

```bash
python -m compileall webgui/backend
pytest -q webgui/backend/tests
```

```bash
cd webgui/frontend
npm ci
npm run typecheck
npm run test
npm run build
npm run e2e
```

```bash
python tests/vectors/webgui/verify_webgui_pack.py tests/vectors/webgui
```

```bash
python -m webgui.backend.app.cli serve --profile local_dev --host 0.0.0.0 --port 8443
```

Run an automated smoke against both:

```text
https://localhost:8443
https://<LAN-IP>:8443
```

Then run the two canonical scenarios and verify:

```text
config revision hash equals run resolved-config hash
every run artifact has a manifest entry
every PNG source relationship/hash is valid
Results and Validation pages show all indexed artifacts
no synthetic plot is generated for missing data
```

Run the full repository Python and MATLAB regressions after this phase.

## Completion criteria

Do not return `COMPLETE` until all of the following are true:

```text
All WEB-001 through WEB-012 are closed.
Only one WebGUI stack exists.
The canonical public listener binds to 0.0.0.0.
The same origin serves UI, API and WebSocket in deployment.
No default credential/plaintext password/open access remains.
Every state-changing request has auth, CSRF and authorization.
Every HTTP/WS route is covered by the permission matrix.
Run ownership/share ACL tests pass.
Only simulator/configs/scenarios is active.
Every edited/uploaded config is versioned, resolved, hashed and actually executed.
Parameter catalog coverage is 100 percent or explicitly unsupported.
Persistent queue, quotas, stop and restart recovery pass.
No client path or substring run lookup remains.
Every artifact is manifest-indexed by ID and hash.
Every plot is based on actual validated source data or shown unavailable.
All prior technical-pack artifact contracts are visible in Results/Validation/Artifact Explorer.
Every DUT/domain hero visualization is implemented.
Both canonical scenarios pass end-to-end through the UI.
All backend, frontend, Playwright, security and dependency tests pass.
Old dashboard files/scripts/imports are absent.
A clean deployment smoke passes through localhost and LAN URLs.
```

## Required Codex work sequence

Follow `webgui_implementation_task_graph.csv` in dependency order. Commit after coherent tasks. Do not attempt an unreviewable one-shot rewrite.

For each task:

1. add a failing test first where feasible;
2. implement production code;
3. run focused tests;
4. run all prior WebGUI tests;
5. update the task/finding status only after passing execution;
6. record exact commands, results, generated schemas/manifests and hashes.

## Required final response from Codex

Return:

1. finding IDs and tasks completed;
2. exact files added/changed/deleted;
3. architecture and migration decisions;
4. database migrations;
5. routes and permission coverage;
6. YAML parameter coverage counts;
7. tests added and exact command results;
8. frontend build and Playwright results;
9. localhost and LAN smoke URLs/results;
10. canonical scenario run IDs and resolved config hashes;
11. artifact counts by domain/type/validity;
12. PNG/source-CSV hash reconciliation results;
13. old-stack deletion proof;
14. open/blocked items;
15. final `COMPLETE`, `FAIL` or `BLOCKED` status.

Begin with W00 and W01. Do not delete the old dashboard in the first commit. Delete it only in W13 after parity and security/E2E acceptance.

# Detailed finding contract

### WEB-001 — Duplicated WebGUI stacks and divergent behavior

**Current defect:** The repository contains a 20k-line single-file dashboard and a separate FastAPI/React stack, with different configuration, run, result, authentication and deletion semantics.

**Implement:** Port required feature parity into the React/FastAPI stack, freeze the old stack read-only during migration, then delete old code, start scripts, tests, docs and imports. Add a CI assertion that only the canonical stack remains.

**Acceptance:** One canonical server/frontend, no old import/start route, parity matrix complete.

### WEB-002 — Externally reachable bind without a secure deployment boundary

**Current defect:** Both stacks bind to 0.0.0.0; the new backend is started with --reload and the dev frontend is separately exposed.

**Implement:** Keep the user-required public bind 0.0.0.0, but expose exactly one same-origin gateway for UI/API/WS. Serve the built React app from FastAPI or a pinned reverse proxy. Remove --reload from deployed launch. Print localhost and LAN URLs. Require authentication in every profile and TLS in lan_secure.

**Acceptance:** Only one listening public origin; bind is 0.0.0.0; local and LAN URLs work; lan_secure refuses to start without TLS/auth/secret requirements.

### WEB-003 — No strong authentication or session lifecycle in the new stack; old stack has open/plaintext paths

**Current defect:** The new FastAPI routes have no auth. The old stack defaults to open mode and compares plaintext passwords.

**Implement:** Implement one-time bootstrap admin, Argon2id password hashing, password blocklist/length policy, login throttling, account disable/lock state, server-side opaque sessions, rotation on login/privilege change, idle/absolute expiry and audited logout/revocation.

**Acceptance:** No default credentials; no plaintext password storage/comparison; cookies and session revocation tests pass.

### WEB-004 — No RBAC, run ownership or deny-by-default authorization

**Current defect:** Any caller can list, read, stop or delete any run and unauthenticated WebSocket clients can stop runs.

**Implement:** Implement Admin, Operator, Researcher, Viewer and Auditor roles; centralized permission dependency; owner/share ACL for runs; deny by default; authorize every HTTP and WS message.

**Acceptance:** Route matrix fully covered; cross-user read/stop/delete denied; admin actions audited.

### WEB-005 — Missing CSRF, restrictive CORS, trusted-host, TLS and browser security controls

**Current defect:** State-changing cookie-authenticated operations have no CSRF defense; CORS allows all methods/headers; no TrustedHost, HTTPS redirect/profile, CSP or security headers.

**Implement:** Use same-origin production deployment. Add synchronizer or signed double-submit CSRF, Origin/Referer and Fetch-Metadata checks, exact origins in dev, TrustedHost, HTTPS enforcement in lan_secure, HSTS, CSP, frame-ancestors, nosniff and referrer policy.

**Acceptance:** All state changes reject missing/invalid CSRF and wrong Origin; cookies are HttpOnly/SameSite and Secure in HTTPS profile.

### WEB-006 — YAML editor and GUI fields are not the configuration that MATLAB executes

**Current defect:** The editor text is validated only by safe_load; edited/uploaded text is never persisted as the launched scenario. SNR and slot inputs are stored but not passed to MATLAB. Both active and legacy scenario roots are listed.

**Implement:** Use active root simulator/configs/scenarios only. Implement versioned ConfigRevision objects, round-trip YAML, inheritance resolution, schema/constraint/cross-reference validation, structured form generation from catalogs, source/effective/resolved/diff views and immutable resolved_scenario.yaml. Launch exactly the selected revision hash.

**Acceptance:** Editing any field changes resolved YAML/hash and MATLAB command; legacy root absent; parameter catalog coverage is 100% or explicitly unsupported.

### WEB-007 — Run orchestration is in-memory, non-transactional and lacks quotas/recovery

**Current defect:** Process state is kept in a module dictionary, can be lost on restart, and there are no ownership, concurrency, CPU/RAM/time/disk quotas or durable stop semantics.

**Implement:** Create persistent Job/Run/Process records and a queue/worker service. Use process groups, graceful stop then hard kill, quota reservation, per-user and global limits, restart reconciliation, immutable command manifests and no hidden CLI overrides.

**Acceptance:** Restart preserves/reconciles jobs; quota tests pass; only resolved YAML controls the run; stop is owner-authorized and complete.

### WEB-008 — Artifact discovery is hard-coded and weakly bound to runs

**Current defect:** Results expose six hard-coded CSVs; run directories are found by substring scans; images are not bound to source CSVs or provenance.

**Implement:** Generate artifact_manifest.json per run, index every CSV/PNG/JSON/MAT/MD/log by immutable artifact ID, exact run ID and relative path. Record SHA256, schema, source artifact IDs, provenance, plot recipe and validity. No substring run matching.

**Acceptance:** All prior technical-pack contracts are discoverable; image/source hashes reconcile; missing source data shows unavailable rather than a fabricated plot.

### WEB-009 — Dashboard lacks run-centric results, validation, comparison and DUT visual design

**Current defect:** The new UI has only Config, Runs, Real-Time, Analytics and DevTools, with a hard-coded BLER plot.

**Implement:** Implement global run selector, Overview, Configure, Runs, Live, Results, Validation, Compare Runs, Artifact Explorer, Architecture/Parameter Catalog and Operations. Use the supplied DUT visualization catalog and visual archetypes; render from actual source CSV or validated PNG only.

**Acceptance:** Run dropdown controls every page; all artifacts visible by domain/DUT/phase; hero plots and validation badges render from actual run data.

### WEB-010 — Path, upload and download isolation is insufficient

**Current defect:** Client-supplied paths may address any repository file; YAML uploads are unlimited; result lookup uses path scans; no symlink-safe artifact IDs.

**Implement:** Use IDs instead of client paths. Allowlist active scenario and per-run artifact roots, resolve symlinks safely, constrain upload bytes/aliases/depth/tags, generate server filenames, stage outside web root and serve downloads through authorized artifact IDs.

**Acceptance:** Traversal, absolute path, symlink escape, YAML bomb and oversized upload tests all fail closed.

### WEB-011 — Operational safety, audit and observability are incomplete

**Current defect:** No immutable audit log, request correlation, quota telemetry, retention policy, backup/restore proof, or shared-deployment DB failure policy exists.

**Implement:** Add structured audit/security logs, request/run/task correlation IDs, liveness/readiness, queue/disk/DB/process metrics, redaction, retention/purge workflows, backup/restore tests and explicit degraded-mode policy. Shared/LAN mode must not silently lose auth/ownership state.

**Acceptance:** Every security/run/config/artifact/admin action is attributable; readiness reflects DB/worker/disk state; purge requires role and confirmation.

### WEB-012 — No comprehensive security/E2E test gate and old stack is not decommissioned

**Current defect:** Current tests do not prove auth, CSRF, RBAC, ownership, WebSocket protection, config round-trip, artifact coverage or old-stack removal.

**Implement:** Add pytest, frontend unit tests, Playwright E2E, route authorization matrix tests, YAML property tests, artifact-gallery contract tests, dependency/security scans and a decommission manifest. Delete the old stack only after parity and migration tests pass.

**Acceptance:** All mandatory tests pass; zero old-stack imports/start scripts/routes; build and deployment smoke pass on 0.0.0.0.

