function out = run6GRPDSCHStudy(configPath, presetName)
%run6GRPDSCHStudy Launch focused truthful 6GR PDSCH study presets.

if nargin < 1 || strlength(string(configPath)) == 0
    configPath = fullfile(pwd, "simulator", "configs", "scenarios", "pdsch_6gr_truth_study.yaml");
end
if nargin < 2 || strlength(string(presetName)) == 0
    presetName = "preset1_fr1_baseline";
end

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

cfgPath = string(configPath);
if exist(cfgPath, "file") ~= 2
    error("sixgr:pdsch:run6GRPDSCHStudy:MissingConfig", ...
        "Scenario config not found: %s", cfgPath);
end

scfg = sixgr.lls6g.config.loadScenarioConfig(cfgPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(pwd, "results", "pdsch6gr_script"));
matrix = localPresetMatrix(cfg, string(presetName));

out = sixgr.pdsch.runPDSCHStudyLLS(cfg, ...
    "ScenarioID", char(string(scfg.ScenarioID)), ...
    "ScenarioMatrix", matrix, ...
    "WriteOutputs", true, ...
    "Verbose", true);
end

function matrix = localPresetMatrix(cfg, presetName)
switch lower(strtrim(char(presetName)))
    case {"preset1_fr1_baseline","preset1"}
        matrix = [ ...
            localPoint("fr1_type0_low", 0, "type0_bitmap", 2, 10, "TDL-C", 30, 3, 1, "none", "disabled", 1, 2e9, 0, "FDD", 20, 52)
            localPoint("fr1_type1_mid", 12, "type1_riv", 2, 10, "TDL-C", 100, 30, 1, "none", "disabled", 1, 2e9, 0, "FDD", 20, 52)
            localPoint("fr1_type1_high", 20, "type1_riv", 2, 10, "TDL-C", 300, 120, 1, "none", "disabled", 1, 2e9, 0, "FDD", 20, 52)
            ];
    case {"preset2_4ghz_truth","preset2"}
        matrix = [ ...
            localPoint("fr1_4g_rank1", 10, "type1_riv", 2, 10, "CDL-A", 100, 30, 1, "none", "disabled", 1, 4e9, 1, "TDD", 100, 273)
            localPoint("fr1_4g_rank2", 14, "type0_bitmap", 2, 10, "CDL-D", 300, 30, 2, "none", "disabled", 1, 4e9, 1, "TDD", 100, 273)
            ];
    case {"preset3_7ghz_study","preset3"}
        matrix = [ ...
            localPoint("7g_ptrs_off", 10, "type1_riv", 2, 10, "CDL-D", 100, 30, 1, "none", "disabled", 1, 7e9, 1, "TDD", 100, 273)
            localPoint("7g_ptrs_on", 10, "type1_riv", 2, 10, "CDL-D", 100, 30, 1, "none", "enabled", 1, 7e9, 1, "TDD", 100, 273)
            ];
    case {"preset4_30ghz_fr2","preset4"}
        matrix = [ ...
            localPoint("fr2_ptrs_on", 8, "type1_riv", 1, 8, "CDL-D", 30, 30, 1, "none", "enabled", 1, 30e9, 3, "TDD", 100, 66)
            localPoint("fr2_ptrs_off", 8, "type1_riv", 1, 8, "CDL-D", 30, 30, 1, "none", "disabled", 1, 30e9, 3, "TDD", 100, 66)
            ];
    case {"preset5_hst","preset5"}
        matrix = [ ...
            localPoint("hst_4g", 10, "type1_riv", 2, 10, "CDL-A", 100, 350, 1, "none", "disabled", 1, 4e9, 1, "TDD", 100, 273)
            localPoint("hst_7g", 10, "type1_riv", 2, 10, "CDL-D", 100, 500, 1, "none", "enabled", 1, 7e9, 1, "TDD", 100, 273)
            localPoint("hst_30g", 10, "type1_riv", 1, 8, "CDL-D", 30, 500, 1, "none", "enabled", 1, 30e9, 3, "TDD", 100, 66)
            ];
    case {"preset6_low_overhead_dmrs_ai_hook","preset6"}
        matrix = [ ...
            localPoint("dmrs_low_overhead_hook", 14, "type1_riv", 2, 10, "TDL-A", 30, 30, 1, "none", "disabled", 0, 4e9, 1, "TDD", 100, 273)
            localPoint("dmrs_baseline_overhead", 14, "type1_riv", 2, 10, "TDL-A", 30, 30, 1, "none", "disabled", 1, 4e9, 1, "TDD", 100, 273)
            ];
    otherwise
        error("sixgr:pdsch:run6GRPDSCHStudy:UnknownPreset", ...
            "Unknown PDSCH preset '%s'.", presetName);
end

for i = 1:numel(matrix)
    matrix(i).NumTrials = 1;
end
end

function point = localPoint(id, snr, fdraType, startSym, numSym, chModel, dsNs, speed, rank, repMode, ptrsMode, varargin)
dmrsAddPos = 1;
if nargin >= 12 && ~isempty(varargin{1})
    dmrsAddPos = varargin{1};
end
carrierHz = 2e9;
numerology = 0;
duplexMode = "FDD";
bandwidthMHz = 20;
nSizeGrid = 52;
if nargin >= 13 && ~isempty(varargin{2}), carrierHz = varargin{2}; end
if nargin >= 14 && ~isempty(varargin{3}), numerology = varargin{3}; end
if nargin >= 15 && ~isempty(varargin{4}), duplexMode = varargin{4}; end
if nargin >= 16 && ~isempty(varargin{5}), bandwidthMHz = varargin{5}; end
if nargin >= 17 && ~isempty(varargin{6}), nSizeGrid = varargin{6}; end
point = struct( ...
    "ScenarioID", id, ...
    "SNRdB", snr, ...
    "FDRAType", fdraType, ...
    "StartSymbol", startSym, ...
    "NumSymbols", numSym, ...
    "ChannelModel", chModel, ...
    "DelaySpread_ns", dsNs, ...
    "Rank", rank, ...
    "RepetitionMode", repMode, ...
    "PTRSMode", ptrsMode, ...
    "SpeedKmh", speed, ...
    "CarrierFrequencyHz", carrierHz, ...
    "Numerology", numerology, ...
    "DuplexMode", duplexMode, ...
    "ChannelBandwidthMHz", bandwidthMHz, ...
    "NSizeGrid", nSizeGrid, ...
    "DMRSAdditionalPosition", dmrsAddPos, ...
    "NumTrials", 1);
end
