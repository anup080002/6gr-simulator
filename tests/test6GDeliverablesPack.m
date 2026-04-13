function test6GDeliverablesPack()
%TEST6GDELIVERABLESPACK Verify the 6G LLS deliverables pack exists and is internally consistent.

repoRoot = fileparts(fileparts(mfilename("fullpath")));
docsRoot = fullfile(repoRoot, "docs", "6g_lls");

requiredDocs = [ ...
    "README.md"
    "delivery_overview.md"
    "architecture.md"
    "config_schema_reference.md"
    "block_diagrams_and_parameters.md"
    "processing_chains.md"
    "scenario_library.md"
    "scenario_library_manifest.json"
    "scenario_family_library.md"
    "scenario_family_manifest.json"
    "result_specification.md"
    "validation_rules.md"
    "sweep_framework.md"
    ];

for i = 1:numel(requiredDocs)
    assert(isfile(fullfile(docsRoot, requiredDocs(i))), ...
        "sixgr:test:6GDeliverables:MissingDoc", ...
        "Missing deliverable file '%s'.", requiredDocs(i));
end

manifestPath = fullfile(docsRoot, "scenario_library_manifest.json");
manifest = jsondecode(fileread(manifestPath));
assert(isfield(manifest, "scenarios"), ...
    "sixgr:test:6GDeliverables:MissingScenarios", ...
    "Scenario library manifest must contain a 'scenarios' array.");

scenarios = manifest.scenarios;
assert(numel(scenarios) >= 20, ...
    "sixgr:test:6GDeliverables:TooFewScenarios", ...
    "Scenario library manifest must contain at least 20 scenario packs.");

ids = strings(numel(scenarios), 1);
groups = strings(numel(scenarios), 1);
for i = 1:numel(scenarios)
    ids(i) = string(scenarios(i).id);
    groups(i) = string(scenarios(i).group);
    assert(strlength(ids(i)) > 0, ...
        "sixgr:test:6GDeliverables:EmptyID", ...
        "Scenario manifest entry %d has an empty id.", i);
    assert(isfield(scenarios(i), "path"), ...
        "sixgr:test:6GDeliverables:MissingPath", ...
        "Scenario manifest entry '%s' is missing its path.", ids(i));
    pathOnDisk = fullfile(repoRoot, char(string(scenarios(i).path)));
    assert(isfile(pathOnDisk), ...
        "sixgr:test:6GDeliverables:MissingScenarioFile", ...
        "Scenario manifest entry '%s' points to a missing file '%s'.", ids(i), pathOnDisk);
end

assert(numel(unique(ids)) == numel(ids), ...
    "sixgr:test:6GDeliverables:DuplicateIDs", ...
    "Scenario library manifest contains duplicate scenario ids.");
assert(numel(unique(groups)) >= 8, ...
    "sixgr:test:6GDeliverables:InsufficientGrouping", ...
    "Scenario library manifest should span multiple scenario groups.");

resultSpecPath = fullfile(docsRoot, "result_specification.md");
resultSpecText = string(fileread(resultSpecPath));
requiredAnchors = [ ...
    "## Expected Results and What a Correct 6G PHY LLS Should Be Able to Show"
    "#### CP-OFDM vs DFT-s-OFDM"
    "#### CSI-RS vs DMRS-based CSI Tracking"
    "#### DL-based vs UL-based vs Joint DL/UL CSI"
    "`Low-SNR region`"
    "The artifact set that must reveal this"
    "A result is correctness-proving only if it satisfies all of the following"
    "The following outputs are mandatory to prove that the simulator is behaving correctly"
    ];

for i = 1:numel(requiredAnchors)
    assert(contains(resultSpecText, requiredAnchors(i)), ...
        "sixgr:test:6GDeliverables:MissingExpectedResultsAnchor", ...
        "Result specification is missing required expected-results anchor '%s'.", requiredAnchors(i));
end

deliveryOverviewPath = fullfile(docsRoot, "delivery_overview.md");
deliveryOverviewText = string(fileread(deliveryOverviewPath));
requiredOverviewSections = [ ...
    "## 1. Architecture overview"
    "## 2. Complete config schema"
    "## 3. Per-block Tx/Rx chain specification"
    "## 4. Scenario family library"
    "## 5. Validation rules"
    "## 6. Expected-results specification"
    "## 7. Artifact/output specification"
    "## 8. Example resolved YAML configs"
    "## 9. Example sweep/matrix configs"
    "## 10. Implementation roadmap"
    "## 11. Test plan"
    "## 12. Success condition and sign-off criteria"
    ];

for i = 1:numel(requiredOverviewSections)
    assert(contains(deliveryOverviewText, requiredOverviewSections(i)), ...
        "sixgr:test:6GDeliverables:MissingDeliveryOverviewSection", ...
        "Delivery overview is missing required section '%s'.", requiredOverviewSections(i));
end

requiredSuccessAnchors = [ ...
    "### 12.1 A new band / waveform / CSI / HARQ / AI / energy scenario can be created without editing code"
    "### 12.2 Every PHY block is visible and configurable"
    "### 12.3 Every important result is exported in machine-readable form"
    "### 12.4 Baseline and candidate features are cleanly separated"
    "### 12.5 A researcher can reproduce a paper-ready 6G PHY LLS campaign from config and artifacts alone"
    ];

for i = 1:numel(requiredSuccessAnchors)
    assert(contains(deliveryOverviewText, requiredSuccessAnchors(i)), ...
        "sixgr:test:6GDeliverables:MissingSuccessConditionAnchor", ...
        "Delivery overview is missing required success-condition anchor '%s'.", requiredSuccessAnchors(i));
end
end
