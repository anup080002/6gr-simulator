# SixGR single implementation guide: H4 and n40 LLS

A local, read-only documentation website in the **main repository**, not a
second simulator, worktree or branch. It does not start MATLAB runs or change
configuration. The separate simulator dashboard on port 62906 is unaffected.

This is the single home for mathematics, port/layer diagrams, algorithms,
configuration flows, measurements, source links, and 3GPP/MATLAB references.
The home page starts with three paths: radio fundamentals, reading results,
and configuration. A four-step radio explanation and short introductions to
MCS, rank, goodput, BLER, SNR/SINR and unavailable measurements come first.
The sidebar keeps five essential links visible. Expand **All technical topics**
for the complete 16-topic library; advanced bookmarks and searches open it
automatically. Detailed chapters retain their original links, equations,
source viewer, calculators and next-reading navigation.
`../lls_gap_status_20261023.html` is an issue ledger only: pending work,
root causes, implemented-but-unverified repairs, and scoped verified fixes.
The guide serves that same ledger at `/issues.html`; it is not a second copy.
Local logs/results remain private and are not exposed by the documentation server.

### Open or restart the guide

From the repository directory:

```powershell
python docs\lls\h4_100mhz_guide\serve.py --port 62907
```

Open <http://127.0.0.1:62907/>. The server must remain running; after a laptop
restart, start it again. Port **62907** is this explanation guide. The **Live
dashboard** link opens the simulation GUI on **62906**, where the Run dropdown
selects current or previous runs. The guide does not poll or control simulations.
If the port is already in use, open the existing guide rather than starting a
second copy. This documentation-only UI change needs the focused guide browser
check below; it does not require launching another MATLAB simulation.

### External output location for a waveform run

The documentation server never launches a simulation. When launching the
selected n40 reference scenario separately, the external evidence directory must
also be authorized through the existing storage allowlist. Merely passing
`E:\SixGRResults` as a CLI argument is insufficient: an unauthorized absolute
root can resolve to the repository's `results` folder. This is a storage
setting, not a PHY/noise/decoder override. Check the resolved root before
starting physical work; use a fresh run tag to preserve earlier evidence.

```powershell
$env:SIXGR_RESULTS_ROOT = 'E:\SixGRResults'
matlab -batch "setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); assert(strcmpi(sixgr.report.resolveResultsRoot('E:\SixGRResults'),'E:\SixGRResults')); tag=['n40_sixpoint_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]; out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml','E:\SixGRResults',tag); disp(out.RunFolder); disp(out.Ok);"
```

Do not start this command while an existing waveform run is active. The YAML
owns the six reference-Es/N0 points, 60-slot child duration and disabled
checkpoints. A launched or completed process is not automatically a passed
physical or statistical result; inspect every child and the final receipt.

The latest technical chapters are [ports and CSI flow](http://127.0.0.1:62907/#port-layer-measurement-flow),
[n40 reference sweep](http://127.0.0.1:62907/#n40-reference-sweep), and
[measurement operators](http://127.0.0.1:62907/#measurement-operator-maths).
They share the existing navigation, search, source viewer and authority labels.
Chapter subsections use `#chapter-id?section=section-id` links, which expand
the relevant mathematics panel automatically. `implementation.js` is a chapter
module of this guide, not a separate documentation website.

The [engineering handbook](http://127.0.0.1:62907/#engineering-handbook)
adds four source-linked notebooks with the overview / input / algorithm /
output structure reviewed in the user's Intel v21.07 and 22.11 documents.
Ten expandable channel contracts connect the actual SixGR owners; receiver,
TDL/CDL/UMa/O2I and RF/port chapters contain original explanatory equations,
reference-plane cautions and two interactive arithmetic calculators.
The Intel PDFs and figures are not copied or served. This is an explanation
of SixGR, not a claim that Intel features or performance have been reproduced.

The receiver notebook also includes a worked one-RE layer/precoder/channel
example and a separate UL-SCH versus UCI decision diagram, with clickable
production owners. Teaching matrices are explicitly not simulated results;
receiver completion, CRC, usable feedback, delivered feedback and scheduler
state changes are explained separately. The measurement notebook explains
original SRS branch-power observations and their absolute/normalized planes.

24 October handbook verification: 15 affected documentation/security tests
passed. Headless Chromium verified four new chapters, 45 live source links,
chapter navigation, expandable contracts, source viewer, desktop/mobile
layout, theme switching and calculator positive/invalid-input cases.
These checks do not close the five older snapshot/inventory failures below.
Recheck with `python docs/lls/h4_100mhz_guide/verify_browser.py --handbook-only`.

24 October supplemental verification: 17 affected documentation/security
checks pass. The expanded handbook browser check verifies 47 source links,
the worked MIMO example and the independent PUSCH data/UCI branches. The
implementation-chapter browser check verifies 36 source links, subsection
navigation, source display and the separate issue-ledger filter. These are
documentation checks, not a replacement for the MATLAB repair receipts.

24 October relocation verification: 14 affected Python checks and focused
Chromium checks passed (three chapters, 34 current-source links, expandable
math panels, source viewer, mobile layout, and the issue filter). The broader
documentation suite still has five existing failures: a stale evidence
inventory, an obsolete power-control status expectation, and three stale
MATLAB-generated configuration/catalog snapshots. They remain visible and
must be refreshed with their real generators; no snapshot hash was patched
to disguise the mismatch. This is not PHY or campaign qualification.

## Open the guide

The documentation URL is **http://127.0.0.1:62907/** while its server is running.

To start it later, paste this **single line into Windows Command Prompt**:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && "C:\ProgramData\anaconda3\python.exe" "docs\lls\h4_100mhz_guide\serve.py" --port 62907
```

Leave that command window open, then open the URL. Ctrl+C stops only the
documentation server. If port 62907 is already in use by this guide, open the
existing URL instead of starting a duplicate. Do not open `index.html` with
`file://`: the source/configuration explorers require the local read-only API.

Other machines need Python 3.10+ and PyYAML; adjust the Python executable path.
No Node build, external fonts, online JavaScript, account or hosted upload is
required. Specification and MathWorks links need internet when clicked.

## Contents and evidence boundaries

- Chapters covering H4 and n40 configurations,
  LLS fundamentals, TX/RX, access, channels/signals, coding, scheduling,
  feedback/adaptation, arrays/beam management, propagation, RF and exports.
- The [antenna/port/power audit](http://127.0.0.1:62907/#antenna-port-power-audit)
  distinguishes physical elements, RF chains, CSI ports, beam resources and
  transmitted layers; documents panel-center spacing and polarization repairs;
  and separates NR procedures from engineering power/energy assumptions.
  On 21 October, 27 focused documentation tests passed and Chromium checked
  all 47 chapters plus 172 source links with no browser errors. This is
  documentation verification, not whole-run PHY or statistical qualification.
- A three-way **3GPP clause / MATLAB building block / SixGR source** comparison,
  with implementation choices and remaining qualification limits explicit.
- A new [standards crosswalk](http://127.0.0.1:62907/#standards-crosswalk)
  covers 18 areas, with pinned clause references, implementation flows,
  structural matches, non-normative design choices and remaining verification.
  It adds TR 38.901 §7.7 link-level channel references, TS 38.141-1
  performance/FRC applicability and independent MathWorks DL/UL example links.
- Every earlier technical chapter now includes relevant dashboard/output
  interpretation. The [dashboard field guide](http://127.0.0.1:62907/#dashboard-reading)
  has 19 searchable families: what a row means, field groups, units/planes,
  joins, useful observations and limits. This includes UE admission, initial
  access, received CSI, actual rank, QCL/TCI, UCI, SRS/TRS and RF.
- The [output atlas](http://127.0.0.1:62907/#output-atlas) indexes 35 exact
  realtime table definitions, 21 canonical runtime and 14 procedure CSV
  mappings, 35 live-chart pairs, 194 declared tables, 390 declared charts
  and 27 visual contracts. These are declarations, not successful run outputs.
  The dated retained-run inventory contains **714 CSV and 239 PNG files**,
  including checkpoint revisions. It records headers/first-record presence
  and file presence, **not numerical correctness or final acceptance**.
- [Plot-reading examples](http://127.0.0.1:62907/#result-reading) explain
  BLER/goodput, EVM/NMSE, constellations, power, waveform/PSD/PAPR, resources,
  feedback, timing, channel geometry and qualification. Educational arithmetic
  is explicitly separated from measurements.
- A searchable **42-method algorithm register**. Each entry records its
  calculation, production owners, flow, reading references and applicability.
  Every chapter is tagged as applicable: 3GPP-defined structure/procedure,
  TR38.901 model, MathWorks implementation, SixGR engineering choice,
  research assumption, or evidence/software infrastructure. These authority
  tags are not execution or conformance certificates.
- **15 detailed channel/element walkthroughs**, each following configuration,
  transmission, received observations, estimation/decoding, causal use and
  outputs: frame/resources; SSB/PSS/SSS/PBCH; PRACH/four-step access; PDCCH;
  PDSCH; PUSCH; CSI-RS/CSI-IM; codebook/PMI/RI/CRI; beam/TCI/QCL; PUCCH;
  SRS; TRS; DM-RS/PT-RS/equalization/decoding; propagation; RF/converters.
- Worked calculations for FFT/CP/sample clocks, gross REs versus actual data
  sets, noise calibration, inter-layer SINR, CSI aggregation, OLLA dB mapping,
  EVM/NMSE, sample delays, SRS phase ambiguity, throughput and confidence
  bounds. Interactive calculator examples are not run measurements.
- Causal completion and checkpoint-restoration chapters explain the
  slot49/50 batch repair, slot48 QCL gap, recommendation versus received CSI,
  and why a WebGUI can display the previous failure while files are restored.
- Current source viewer: actual repository files, numbered lines, SHA-256,
  paged large files and text search. Application-source links explicitly
  open committed GitHub main rather than expand the local source allow-list.
  No MATLAB implementation is copied here.
- Configuration snapshot generated by the real MATLAB scenario loader and
  builder, including 34 inherited source occurrences and native OFDM metadata.
- Searchable installed parameter catalogs: **3,422 LLS scenario parameter rules**,
  **406 native-core rules** and **18 matrix rules** at this verification. Native
  core rules are read directly from the current file used by `loadCoreCatalog`;
  SLS request parameters use the `sls.config` prefix. Nested-object names,
  constraints and declared defaults are retained without invented options.
- Live inventory of **438 configuration YAML files**, including **208 scenario
  files**, at initial verification. Building blocks and schemas are not
  standalone scenarios. These counts can change with the checkout.
- Interactive execution map, symbol-level TDD calendar, rank/eigenmode lesson,
  PRACH threshold calculator, HARQ identity lesson and QAM/noise/phase illustration; light/dark themes,
  mobile navigation and chapter printing.
- Configuration decision map covering 22 areas, from carrier/BWP/timebase and
  TX/RX to RF, beams, feedback, traffic, measurement/export and research policy.
  Each key links to its searchable rule; production-source links explain the
  consumers. Explicit-value, boolean, range and section filters help navigate
  the complete catalogs.
- Scenario-family guide with linked 5/20/100/400 MHz examples, fixed-MCS and
  adaptive children, access/beam experiments, absolute-power and normalized-SNR
  arms, sweeps, matrices and native SLS. Correct entry points and calibration
  blockers are explicit; no file is classified as accepted simply by existing.

Direct links while the guide is running:

- [Configuration decision map](http://127.0.0.1:62907/#configuration-map)
- [Exact channel-by-channel walkthroughs](http://127.0.0.1:62907/#channel-playbooks)
- [Algorithm authority register](http://127.0.0.1:62907/#algorithm-register)
- [Worked calculations](http://127.0.0.1:62907/#worked-calculations)
- [Interactive causal flow](http://127.0.0.1:62907/#causal-flow)
- [Measurement and export contracts](http://127.0.0.1:62907/#measurement-contract)
- [Checkpoint restoration / WebGUI status](http://127.0.0.1:62907/#restart-flow)
- [PASS/FAIL threshold authority](http://127.0.0.1:62907/#threshold-authority)
- [All declared YAML rules](http://127.0.0.1:62907/#parameters)
- [Native core / SLS rules](http://127.0.0.1:62907/#parameters?kind=core)
- [Scenario families and entry points](http://127.0.0.1:62907/#run-families)
- [All configuration files](http://127.0.0.1:62907/#scenarios)
- [PRACH formula, H4 calculation and statistical qualification](http://127.0.0.1:62907/#prach)
- [Slot-48 QCL reference-age/availability timeline](http://127.0.0.1:62907/#beam)
- [Conservative symbol allocations and fix-later plan](http://127.0.0.1:62907/#resource-efficiency)
- [DL/UL adaptation and actual feedback timing](http://127.0.0.1:62907/#adaptation)
- [Runtime bottlenecks and safe optimization priorities](http://127.0.0.1:62907/#recipe)

The exact example is
`simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml`.
It is a single 40 dB reference point, not the eight-point sweep. It retains the
100-slot/50 ms horizon including access, adaptive rank up to four, 64 gNB and
four UE dimensions, four SSB beams and eight CSI/data beam resources.

**Catalog acceptance is not runtime qualification.** Cross-field legality,
native toolbox capabilities and physical execution still require validation.
The guide does not claim every combination of declared parameters can run,
that all historical issues are closed, or that a 100-slot run is accepted.
Educational figures are not retained measurements. Standard versions are
pinned for reading, not used to silently change the installed implementation.
Opaque struct/list rules still require their implementation and cross-field
validation; the catalog browser does not invent unconstrained child fields.
For example, a 400 MHz lab-waveform file is not a substitute for the H4 shared
control/access runtime, and the file named `lls_2ghz_20mhz_rank2_cdlc_reference`
currently declares **1.900 GHz n39 TDD**. Read resolved values, not filenames.

## Refresh configuration/catalog snapshots

From the repository root in MATLAB:

```matlab
addpath(fullfile(pwd,'docs','lls','h4_100mhz_guide'));
refreshGuideSnapshots;
```

This invokes the actual `loadScenarioConfig`, `buildInternalConfig`,
`loadParameterCatalog` and `nrOFDMInfo` functions. It runs no waveform scenario,
test suite or campaign. The generated JSON files are documentation data,
not alternate executable YAMLs. Reload the browser after regeneration.

The server compares snapshot hashes with the inherited YAMLs and catalog
loader/schema files. Source hyperlinks always show the **current working
tree**, not the historical source used by a retained simulation receipt.
Authored explanations should be reviewed separately after implementation changes.
Snapshots were refreshed again on 20 October 2026 using the actual MATLAB
loader/builder, without running a waveform or test suite. On another checkout,
Git line-ending conversion can change byte hashes even when configuration text
is equivalent. If the guide flags a stale snapshot, regenerate it on that host;
do not manually replace its hashes or confuse a documentation snapshot with
executed scenario evidence. See the root README's server handoff instructions.

## Focused documentation verification

```bat
"C:\ProgramData\anaconda3\python.exe" -m pytest tests/test_h4_documentation.py -q
"C:\ProgramData\anaconda3\python.exe" docs/lls/h4_100mhz_guide/verify_browser.py --url http://127.0.0.1:62907
```

The second command needs installed Playwright and Chromium. Optional
`--screenshots logs/h4_documentation_browser_20261016` retains browser screenshots.
These checks validate documentation/source links, snapshots, read-only HTTP
boundaries, navigation, catalogs and illustrations—not PHY correctness.
They do not invoke `testAll` or a simulation.

20 October 2026 expanded documentation verification: **22 Python checks passed**
(also included in **437 passing focused documentation/publication/WebGUI/audit
checks**). Headless Chromium traversed all **41 chapters**, verified **148 local
source links**, checked authority tags and all internal chapter targets, and
exercised method filters, detailed-flow search, calculators, the causal diagram,
source viewer, catalogs and desktop/mobile layouts. It reported **zero browser
errors**, **42 methods**, **15 walkthroughs** and **24,435 authored words**.
This is documentation acceptance only. No MATLAB scenario or `testAll` was
launched for this documentation update; the existing continuation was untouched.

Local verification evidence:
`logs/lls_repairs/h4_guide_algorithms_20261020.xml`,
`logs/lls_repairs/h4_consolidation_20261020_python.xml` and
`logs/lls_repairs/h4_guide_algorithms_20261020_browser/`.
These generated receipts/screenshots are not committed measurement artifacts.

## Maintenance

- `chapters.js`: authored technical explanations, standards and source links.
- `guide.js` / `guide.css` / `index.html`: navigation, diagrams and layout.
- `serve.py`: loopback-only, read-only API; allow-listed source access.
- `refreshGuideSnapshots.m`: reproducible MATLAB documentation-data generation.
- `reference.json`, `parameter-catalog.json`, `matrix-catalog.json`,
  `catalog-provenance.json`: generated data with source provenance.
- `verify_browser.py`: focused UI verification.
- `buildEvidenceGuide.py` / `evidence-catalog.csv`: generated documentation
  inventory, not simulation output. The generator parses dashboard literals
  without importing its server and reads installed declaration modules.

### Refresh the evidence documentation inventory

From the repository root, no MATLAB process is needed:

```bat
python docs\lls\h4_100mhz_guide\buildEvidenceGuide.py
```

This refreshes installed declarations only. To also inspect a retained run,
provide its exact folder:

```bat
python docs\lls\h4_100mhz_guide\buildEvidenceGuide.py --run-folder "E:\SixGRResults\lls\h4_100_cdlc100_connected_impaired_40db_adaptation\h4_100mhz_local_e_20261019_v3"
```

The only output is `docs/lls/h4_100mhz_guide/evidence-catalog.csv`. It
does not change the run, checkpoints, logs, MATLAB or dashboard. CSV inspection
is bounded to 256 KiB per file and retains only column names and first-record
presence/width metadata—not payload values. It detects a header-only file
without using file size as evidence of trials. Large/truncated/malformed
records can yield an explicit inspection error; this is not a waveform failure.
PNG inspection establishes file presence only, not pixels or lineage.
An active run can change during/after inspection; the timestamp is not an
atomic run snapshot. Refresh the browser to reload the documentation inventory.

20 October dashboard/standards expansion: **26 focused documentation tests
passed**. Chromium visited all **45 chapters**, verified **150 local source
links**, exercised family/standard/output filters, CSV quoted-field parsing,
source viewers, calculators and desktop/mobile navigation with **zero browser
errors**. Screenshots are retained locally in
`logs/lls_repairs/h4_guide_dashboard_20261020_browser/`. This is documentation
verification, not an audit accepting the current simulation measurements.

Do not deploy this source-reading server on a public interface. It intentionally
exposes selected repository code to the local reader, but not results, logs,
Git internals or arbitrary filesystem paths.

### Deferred resource-efficiency work

The resource-efficiency chapter distinguishes legal NR allocations from the
conservative H4 choices: PDSCH `[2,12]` / special-slot `[2,8]`, PUSCH `[0,11]`,
two-symbol partial-band CORESET, SRS at symbol 11 and conditional PUCCH at 12–13.
It links TS38.214 time/resource mapping and the exact production owners.
H4-196, H4-197 and H4-198 in `docs/lls/h4_100mhz_20261015_issue_status.csv`
remain **OPEN/deferred**: DL early-symbol reuse, UL occasion-dependent allocation,
and resource-accounting/matched-performance verification. These are capability
and efficiency gaps, not established 3GPP violations merely because the
allocations are shorter than 14 symbols. No active scientific configuration,
MATLAB source, checkpoint or measured result was changed by this documentation.

20 October resource-efficiency addition: **27 focused documentation tests
passed**. Chromium verified **46 chapters**, **161 local source links**, the
three OPEN backlog entries, the expandable resource calculation, cross-links
and mobile layout with **zero browser errors**. Screenshots are retained in
`logs/lls_repairs/h4_guide_resource_efficiency_20261020_browser/`.
These checks validate documentation, not a newly implemented allocator or
physical throughput improvement.
