function ok = testStrictControlChannelScenarioEvidence()
%TESTSTRICTCONTROLCHANNELSCENARIOEVIDENCE Verify scenario-level PDCCH/PUCCH waveform evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_mobile_2ue_100kmh_1sector_full_capture.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tmp);

evidence = sixgr.truth.exportStrictControlChannelEvidence(tmp, cfg, ...
    "RunId", "test_strict_control", ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "EnablePDCCH", true, ...
    "EnablePUCCH", true);
assert(logical(evidence.Ok), "Strict scenario control evidence must pass for PDCCH and PUCCH.");

pdcchPath = fullfile(tmp, "air_interface", "csv", "pdcch_trials.csv");
pucchPath = fullfile(tmp, "air_interface", "csv", "pucch_trials.csv");
pdcchCandidatePath = fullfile(tmp, "control", "csv", "pdcch_candidates.csv");
pucchResourcePath = fullfile(tmp, "control", "csv", "pucch_resource_mapping.csv");
assert(exist(pdcchPath, "file") == 2, "Missing waveform-backed air-interface PDCCH trials.");
assert(exist(pucchPath, "file") == 2, "Missing waveform-backed air-interface PUCCH trials.");
assert(exist(pdcchCandidatePath, "file") == 2, "Missing PDCCH candidate/CCE evidence.");
assert(exist(pucchResourcePath, "file") == 2, "Missing PUCCH resource-mapping evidence.");

pdcch = readtable(pdcchPath, "VariableNamingRule", "preserve");
pucch = readtable(pucchPath, "VariableNamingRule", "preserve");
pdcchCand = readtable(pdcchCandidatePath, "VariableNamingRule", "preserve");
pucchRes = readtable(pucchResourcePath, "VariableNamingRule", "preserve");

assert(height(pdcch) >= 8 && height(pdcchCand) > height(pdcch), ...
    "PDCCH evidence must include strict trials plus multiple blind-decode candidates.");
assert(all(ismember(["CandidatesAttempted","DCICrcPass","TxCCEIndex","SelectedCCEIndex", ...
    "GrantValid","StrictOk","NegativeExpectedOk"], string(pdcch.Properties.VariableNames))), ...
    "PDCCH trials must expose blind-decode, CCE, CRC, and grant-validation evidence.");
assert(any(logical(pdcch.StrictOk)) && any(logical(pdcch.NegativeExpectedOk)), ...
    "PDCCH trials must include positive decodes and negative rejection evidence.");
assert(~localTableContainsToken(pdcch, "available_runtime_abstraction"), ...
    "PDCCH waveform evidence must not carry runtime-abstraction labels.");

assert(height(pucch) >= 5 && height(pucchRes) == height(pucch), ...
    "PUCCH evidence must include measured trials and one resource mapping row per trial.");
assert(all(ismember(["PUCCHFormat","PUCCHPRBSet","PUCCHSymbolStart","PUCCHNumSymbols", ...
    "FrequencyHopping","PUCCHRECount","DMRSRECount","UCIContentMatch","DetectionMetric", ...
    "GridHash","WaveformHash","StrictOk"], string(pucch.Properties.VariableNames))), ...
    "PUCCH trials must expose resource mapping, RE counts, UCI decode, and waveform hashes.");
assert(all(logical(pucch.StrictOk)), "PUCCH strict waveform rows must pass.");
assert(any(double(pucch.PUCCHFormat) == 0) && any(double(pucch.PUCCHFormat) == 1) && ...
    any(double(pucch.PUCCHFormat) == 2), ...
    "PUCCH strict evidence must cover configured formats 0, 1, and 2.");
assert(any(double(pucch.DMRSRECount) > 0) && all(isfinite(double(pucch.PUCCHRECount))), ...
    "PUCCH evidence must include finite PUCCH RE counts and DMRS-backed rows.");
assert(~localTableContainsToken(pucch, "available_runtime_abstraction"), ...
    "PUCCH waveform evidence must not carry runtime-abstraction labels.");

ok = true;
end

function tf = localTableContainsToken(T, token)
tf = false;
token = lower(string(token));
vars = string(T.Properties.VariableNames);
for i = 1:numel(vars)
    col = T.(vars(i));
    if isstring(col) || iscellstr(col) || ischar(col)
        values = lower(string(col));
        if any(contains(values(:), token))
            tf = true;
            return;
        end
    end
end
end
