function ok = testSupplementalEvidenceScopeIsolation()
%TESTSUPPLEMENTALEVIDENCESCOPEISOLATION Component anchors cannot masquerade as in-path evidence.

setup6GRSimToolkit("Verbose", false);
runFolder = tempname();
mkdir(runFolder);
cleanup = onCleanup(@() localRemove(runFolder)); %#ok<NASGU>
cfg = struct( ...
    "meta", struct("scenarioID", "scope_unit", ...
        "configHash", repmat('a', 1, 64)), ...
    "frequency", struct("center_frequency_hz", 3.5e9, ...
        "channel_bandwidth_mhz", 100), ...
    "numerology", struct("subcarrier_spacing_hz", 30e3));
anchorRoot = sixgr.runtime.prepareComponentAnchorRoot( ...
    runFolder, "prach", cfg, cfg);
assert(startsWith(string(anchorRoot), string(fullfile(runFolder, "component_anchors", "prach"))));
identityPath = fullfile(anchorRoot, "component_anchor_identity.json");
assert(isfile(identityPath));
identity = jsondecode(fileread(identityPath));
assert(string(identity.EvidenceScope) == "component_anchor");
assert(~logical(identity.SameScenarioInPathEligible));
assert(string(identity.ParentScenarioID) == "scope_unit");
assert(string(identity.ParentConfigHash) == string(repmat('a', 1, 64)));
assert(double(identity.CenterFrequencyHz) == 3.5e9);
assert(double(identity.BandwidthHz) == 100e6);
assert(double(identity.SubcarrierSpacingHz) == 30e3);
assert(~isfolder(fullfile(runFolder, "control")), ...
    "Preparing a component anchor must not create primary in-path evidence folders.");
try
    sixgr.runtime.prepareComponentAnchorRoot(runFolder, "../escape", cfg, cfg);
    error("testSupplementalEvidenceScopeIsolation:ExpectedUnsafeName", ...
        "Unsafe component names must fail.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:InvalidComponentAnchorName"));
end
ok = true;
fprintf("PASS testSupplementalEvidenceScopeIsolation: supplemental evidence is isolated and typed component_anchor.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
