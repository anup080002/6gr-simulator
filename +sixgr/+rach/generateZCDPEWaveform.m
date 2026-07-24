function tx = generateZCDPEWaveform(cfg, varargin)
%GENERATEZCDPEWAVEFORM Generate a waveform-accurate ZC-DPE PRACH occasion.

p = inputParser;
p.FunctionName = "sixgr.rach.generateZCDPEWaveform";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
addParameter(p, "DPI_d", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
parse(p, cfg, varargin{:});
opts = p.Results;

occasion = opts.Occasion;
if isempty(fieldnames(occasion))
    occasion = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
end
cfgUse = cfg;
if ~isempty(opts.DPI_d)
    cfgUse = localWithZCDPEDPI(cfgUse, double(opts.DPI_d));
end

baseSeq = sixgr.rach.generatePRACHSequence(cfgUse, "Occasion", occasion, "PreambleIndex", opts.PreambleIndex);
zseq = sixgr.rach.generateZCDPESequence(cfgUse, "Occasion", occasion, "PreambleIndex", baseSeq.PreambleIndex);
symbols = baseSeq.Symbols;
actualSymbols = max(1, floor(numel(symbols) / max(double(baseSeq.LRA), 1)));
M = min(double(zseq.NumSymbols), actualSymbols);
for m = 0:M-1
    idx = (m * double(baseSeq.LRA) + 1):min((m + 1) * double(baseSeq.LRA), numel(symbols));
    symbols(idx) = symbols(idx) .* exp(1i * m * double(zseq.PhaseStep_rad));
end

carrier = baseSeq.Carrier;
prach = baseSeq.PRACH;
[waveform, grid, ofdmInfo, backend] = localModulateZCDPESymbols(symbols, baseSeq, cfgUse);

numTxAnt = round(double(sixgr.util.structGet(cfgUse, "NumTxAntennas", 1)));
if numTxAnt > 1
    waveform = repmat(waveform, 1, numTxAnt) / sqrt(numTxAnt);
end

tx = struct();
tx.Waveform = waveform;
tx.Grid = grid;
tx.Symbols = symbols;
tx.Indices = baseSeq.Indices;
tx.Carrier = carrier;
tx.PRACH = prach;
tx.SampleRate_Hz = double(ofdmInfo.SampleRate);
tx.OFDMInfo = ofdmInfo;
tx.WaveformGenerationBackend = backend;
tx.Occasion = occasion;
tx.PreambleIndex = baseSeq.PreambleIndex;
tx.SequenceIndex = baseSeq.SequenceIndex;
tx.Format = baseSeq.Format;
tx.ZCDPE = struct( ...
    "DPI_D", zseq.DPI_D, ...
    "DPI_d", zseq.DPI_d, ...
    "PhaseStep_rad", zseq.PhaseStep_rad, ...
    "NumSymbols", M, ...
    "IsOrthogonal", zseq.IsOrthogonal, ...
    "IsBackwardCompat", zseq.IsBackwardCompat, ...
    "Sequence", zseq.Sequence(:, 1:min(size(zseq.Sequence, 2), M)));

if zseq.IsBackwardCompat
    baseline = sixgr.rach.generatePRACHWaveform(cfgUse, "Occasion", occasion, "PreambleIndex", baseSeq.PreambleIndex);
    diffNorm = norm(tx.Waveform(:) - baseline.Waveform(:));
    refNorm = max(norm(baseline.Waveform(:)), eps);
    if diffNorm > 1e-6 * refNorm
        warning("sixgr:rach:ZCDPE:BackwardCompatWaveformDrift", ...
            "ZC-DPE d=0 waveform differs from baseline PRACH by relative norm %.3g.", diffNorm / refNorm);
    end
end
end

function [waveform, grid, ofdmInfo, backend] = localModulateZCDPESymbols(symbols, seq, cfg)
useToolbox = logical(sixgr.util.structGet(cfg, "UseToolboxPRACHOFDMModulator", ...
    sixgr.util.structGet(cfg, "random_access.use_toolbox_prach_ofdm_modulator", true)));
if useToolbox
    try
        carrier = seq.Carrier;
        prach = seq.PRACH;
        grid = nrPRACHGrid(carrier, prach);
        grid(seq.Indices) = symbols;
        [waveform, ofdmInfo] = nrPRACHOFDMModulate( ...
            carrier, prach, grid, "Windowing", 0);
        backend = "matlab_5g_toolbox_nrPRACHOFDMModulate_zero_windowing";
        return;
    catch ME
        allowFallback = logical(sixgr.util.structGet(cfg, "AllowInrepoPRACHOFDMFallback", ...
            sixgr.util.structGet(cfg, "random_access.allow_inrepo_prach_ofdm_fallback", false)));
        if ~allowFallback
            error("sixgr:rach:ZCDPEOFDMModulatorUnavailable", ...
                "nrPRACHOFDMModulate failed for the resolved ZC-DPE PRACH config and fallback is disabled: %s", ME.message);
        end
    end
end
[waveform, grid, ofdmInfo] = sixgr.rach.modulatePRACHSymbols(symbols, seq, cfg);
backend = "inrepo_nrPRACH_symbol_ofdm_explicit_fallback";
end

function cfgOut = localWithZCDPEDPI(cfgIn, dpiIndex)
if isstruct(cfgIn)
    cfgOut = cfgIn;
else
    cfgOut = struct(cfgIn);
end
cfgOut = sixgr.util.structSet(cfgOut, "ZCDPE.DPI_d", double(dpiIndex));
end
