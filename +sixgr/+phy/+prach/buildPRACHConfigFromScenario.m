function strictCfg = buildPRACHConfigFromScenario(baseCfg, varargin)
%BUILDPRACHCONFIGFROMSCENARIO Build a strict, scenario-bound PRACH config.
%
% Strict PRACH validation deliberately fails when required RACH parameters
% are not present in the resolved scenario/internal config. This prevents a
% conformance run from passing due to hidden PRACH defaults.

p = inputParser;
p.FunctionName = "sixgr.phy.prach.buildPRACHConfigFromScenario";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "", @(x) ischar(x) || isstring(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

cfg = localStruct(baseCfg);
missing = strings(0, 1);
required = { ...
    "random_access.enabled", ...
    "random_access.configuration_index", ...
    "random_access.prach_format", ...
    "random_access.subcarrier_spacing_khz", ...
    "random_access.root_sequence_index", ...
    "random_access.zero_correlation_zone", ...
    "random_access.restricted_set", ...
    "random_access.preamble_count", ...
    "random_access.preamble_index", ...
    "random_access.frequency_start", ...
    "random_access.n_cell_id", ...
    "random_access.snr_sweep_db", ...
    "random_access.timing_offset_sweep_samples", ...
    "random_access.frequency_offset_sweep_hz"};
for ii = 1:numel(required)
    if localIsMissing(sixgr.util.structGet(cfg, required{ii}, []))
        missing(end + 1, 1) = required{ii}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:phy:prach:MissingStrictConfigField", ...
        "Strict PRACH validation requires explicit resolved scenario field(s): %s.", ...
        strjoin(missing, ", "));
end
if ~logical(sixgr.util.structGet(cfg, "random_access.enabled", false))
    error("sixgr:phy:prach:PRACHDisabledStrictFailure", ...
        "Strict PRACH validation cannot pass when random_access.enabled=false.");
end

runFolder = char(string(opt.RunFolder));
if strlength(string(runFolder)) == 0
    runFolder = char(string(sixgr.util.structGet(cfg, "prach_lls.OutputDir", pwd)));
end
scenarioName = string(opt.ScenarioName);
if strlength(strtrim(scenarioName)) == 0
    scenarioName = string(sixgr.util.structGet(cfg, "meta.scenarioID", ...
        sixgr.util.structGet(cfg, "scenario.id", "prach_strict_validation")));
end

prachCfg = sixgr.rach.PRACHConfig(cfg, "OutputDir", runFolder);
prachCfg.ScenarioName = char(scenarioName);
prachCfg.BindingSource = string(sixgr.util.structGet(cfg, "random_access.binding_source", "scenario_config"));
prachCfg.NumPreambles = round(double(sixgr.util.structGet(cfg, "random_access.preamble_count", 64)));
prachCfg.NCellID = round(double(sixgr.util.structGet(cfg, "random_access.n_cell_id", prachCfg.NCellID)));
prachCfg.SNRSweep_dB = double(sixgr.util.structGet(cfg, "random_access.snr_sweep_db", prachCfg.SNRSweep_dB));
prachCfg.TimingOffsetSweepSamples = double(sixgr.util.structGet(cfg, "random_access.timing_offset_sweep_samples", [0 4 8]));
prachCfg.FrequencyOffsetSweepHz = double(sixgr.util.structGet(cfg, "random_access.frequency_offset_sweep_hz", [0 250]));
prachCfg.ConfigHash = sixgr.phy.prach.hashPRACHConfig(prachCfg);
prachCfg.StrictUnsupportedReason = "";
prachCfg.StrictConfigSource = "resolved_scenario_random_access";
prachCfg.StrictValidation = sixgr.phy.prach.validatePRACHConfigStrict(prachCfg);
strictCfg = prachCfg;
end

function cfg = localStruct(baseCfg)
if isstruct(baseCfg)
    cfg = baseCfg;
elseif isobject(baseCfg)
    cfg = struct(baseCfg);
else
    error("sixgr:phy:prach:BadConfigInput", "Unsupported PRACH config input.");
end
end

function tf = localIsMissing(value)
tf = isempty(value);
if tf
    return;
end
if isstring(value) || ischar(value)
    tf = strlength(strtrim(string(value))) == 0;
end
end
