function det = detectPRACHWaveform(rxWaveform, prachCfg, varargin)
%DETECTPRACHWAVEFORM Strict PRACH detector wrapper with receiver-only inputs.

p = inputParser;
p.FunctionName = "sixgr.phy.prach.detectPRACHWaveform";
addRequired(p, "rxWaveform", @(x) isnumeric(x) && ~isempty(x));
addRequired(p, "prachCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "CandidatePreambles", 0:63, @(x) isnumeric(x));
addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || isnumeric(x));
parse(p, rxWaveform, prachCfg, varargin{:});
opt = p.Results;

args = {"Occasion", opt.Occasion, "CandidatePreambles", opt.CandidatePreambles, ...
    "DetectionThresholdMode", prachCfg.DetectionThresholdMode};
if ~isempty(opt.DetectionThreshold)
    args = [args, {"DetectionThreshold", opt.DetectionThreshold}]; %#ok<AGROW>
else
    args = [args, {"DetectionThreshold", prachCfg.DetectionThreshold}]; %#ok<AGROW>
end
det = sixgr.rach.PRACHDetector(rxWaveform, prachCfg, args{:});
det.ProxyUsed = false;
det.Skipped = false;
det.ToolboxMissing = false;
det.UsedOracleFields = "";
det.DetectorInputPolicy = "rx_waveform_plus_receiver_config_only";
end
