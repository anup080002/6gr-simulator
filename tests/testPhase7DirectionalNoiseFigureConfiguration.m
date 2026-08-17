function ok = testPhase7DirectionalNoiseFigureConfiguration()
%TESTPHASE7DIRECTIONALNOISEFIGURECONFIGURATION BS/UE NF are distinct concepts.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cfg = struct();
cfg.scenario.bs.noiseFigure_dB = 5;
cfg.scenario.ue.noiseFigure_dB = 7;
cfg.air_interface.bs_noise_figure_dB = 5;
cfg.air_interface.ue_noise_figure_dB = 7;
sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmp);

conflicts = readtable(fullfile(tmp, "configuration", "csv", ...
    "configuration_conflicts.csv"), "VariableNamingRule", "preserve", ...
    "TextType", "string");
for concept = ["bs_noise_figure_db", "ue_noise_figure_db"]
    row = strcmp(string(conflicts.Concept), concept);
    assert(any(row) && all(string(conflicts.ConflictStatus(row)) ~= "conflict_unresolved"), ...
        "Directional receiver noise figure was incorrectly classified as a configuration conflict: %s", concept);
end
assert(~any(string(conflicts.Concept) == "noise_figure_db"), ...
    "BS and UE noise figures must not be collapsed into one ambiguous configuration concept.");

gates = readtable(fullfile(tmp, "reports", "csv", "phase7_truth_gates.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(localLogical(gates.ResolvedConfigurationConsistentOk(1)), ...
    "Different but internally consistent BS/UE noise figures must pass resolved-configuration consistency.");
ok = true;
end

function tf = localLogical(value)
if islogical(value) || isnumeric(value)
    tf = logical(value);
else
    tf = any(strcmpi(strtrim(string(value)), ["true","1","yes","pass"]));
end
end
