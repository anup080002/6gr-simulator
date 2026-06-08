function tx = generatePRACHWaveform(cfg, varargin)
%GENERATEPRACHWAVEFORM Generate a waveform-accurate PRACH occasion.

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
[waveform, grid, ofdmInfo] = sixgr.rach.modulatePRACHSymbols(seq.Symbols, seq, cfg);

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
tx.WaveformGenerationBackend = "inrepo_nrPRACH_symbol_ofdm";
tx.Occasion = occasion;
tx.PreambleIndex = seq.PreambleIndex;
tx.SequenceIndex = seq.SequenceIndex;
tx.Format = seq.Format;
end
