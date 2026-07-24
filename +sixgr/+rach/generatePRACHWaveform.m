function tx = generatePRACHWaveform(cfg, varargin)
%GENERATEPRACHWAVEFORM Generate a waveform-accurate PRACH occasion.

tpSelf = sixgr.perf.TimeProfiler.scope("sixgr.rach.generatePRACHWaveform", ...
    "Stage", "prach_waveform_generation"); %#ok<NASGU>
p = inputParser;
p.FunctionName = "sixgr.rach.generatePRACHWaveform";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
parse(p, cfg, varargin{:});
opts = p.Results;

occasion = opts.Occasion;
if isempty(fieldnames(occasion))
    occasion = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
end

seq = sixgr.rach.generatePRACHSequence(cfg, "Occasion", occasion, "PreambleIndex", opts.PreambleIndex);
[waveform, grid, ofdmInfo, backend] = localModulatePRACHSequence(seq);

numTxAnt = round(double(sixgr.util.structGet(cfg, "NumTxAntennas", 1)));
if numTxAnt > 1
    waveform = repmat(waveform, 1, numTxAnt) / sqrt(numTxAnt);
end

tx = struct();
tx.Waveform = waveform;
tx.Grid = grid;
tx.Symbols = seq.Symbols;
tx.Indices = seq.Indices;
tx.Carrier = seq.Carrier;
tx.PRACH = seq.PRACH;
tx.SampleRate_Hz = double(ofdmInfo.SampleRate);
tx.OFDMInfo = ofdmInfo;
tx.WaveformGenerationBackend = backend;
tx.Occasion = occasion;
tx.PreambleIndex = seq.PreambleIndex;
tx.SequenceIndex = seq.SequenceIndex;
tx.Format = seq.Format;
end

function [waveform, grid, ofdmInfo, backend] = localModulatePRACHSequence(seq)
carrier = seq.Carrier;
prach = seq.PRACH;
grid = nrPRACHGrid(carrier, prach);
grid(seq.Indices) = seq.Symbols;
try
    [waveform, ofdmInfo] = nrPRACHOFDMModulate( ...
        carrier, prach, grid, "Windowing", 0);
catch cause
    failure = MException("sixgr:rach:PRACHOFDMModulatorUnavailable", ...
        "nrPRACHOFDMModulate rejected the canonical PRACH occasion. " + ...
        "The standard waveform path has no heuristic OFDM fallback: %s", ...
        cause.message);
    failure = addCause(failure, cause);
    throwAsCaller(failure);
end
if double(sixgr.util.structGet(ofdmInfo, "Windowing", NaN)) ~= 0
    error("sixgr:phy:frame:WindowingNotAppliedExactly", ...
        "Standard PRACH waveform generation requires exactly zero windowing.");
end
backend = "matlab_5g_toolbox_nrPRACHOFDMModulate_zero_windowing";
end
