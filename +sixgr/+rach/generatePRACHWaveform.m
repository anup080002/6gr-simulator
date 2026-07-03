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
[waveform, grid, ofdmInfo, backend] = localModulatePRACHSequence(seq, cfg);

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

function [waveform, grid, ofdmInfo, backend] = localModulatePRACHSequence(seq, cfg)
useToolbox = logical(sixgr.util.structGet(cfg, "UseToolboxPRACHOFDMModulator", ...
    sixgr.util.structGet(cfg, "random_access.use_toolbox_prach_ofdm_modulator", true)));
if useToolbox
    try
        carrier = seq.Carrier;
        prach = seq.PRACH;
        grid = nrPRACHGrid(carrier, prach);
        grid(seq.Indices) = seq.Symbols;
        [waveform, ofdmInfo] = nrPRACHOFDMModulate(carrier, prach, grid);
        backend = "matlab_5g_toolbox_nrPRACHOFDMModulate";
        return;
    catch ME
        allowFallback = logical(sixgr.util.structGet(cfg, "AllowInrepoPRACHOFDMFallback", ...
            sixgr.util.structGet(cfg, "random_access.allow_inrepo_prach_ofdm_fallback", false)));
        if ~allowFallback
            error("sixgr:rach:PRACHOFDMModulatorUnavailable", ...
                "nrPRACHOFDMModulate failed for the resolved PRACH config and fallback is disabled: %s", ME.message);
        end
    end
end
[waveform, grid, ofdmInfo] = sixgr.rach.modulatePRACHSymbols(seq.Symbols, seq, cfg);
backend = "inrepo_nrPRACH_symbol_ofdm_explicit_fallback";
end
