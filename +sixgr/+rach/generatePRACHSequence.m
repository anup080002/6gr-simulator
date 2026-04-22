function seq = generatePRACHSequence(cfg, varargin)
%GENERATEPRACHSEQUENCE Generate the PRACH symbols for one resolved occasion.

p = inputParser;
p.FunctionName = "sixgr.rach.generatePRACHSequence";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
parse(p, cfg, varargin{:});
opts = p.Results;

occasion = opts.Occasion;
if isempty(fieldnames(occasion))
    occasion = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
end

carrier = occasion.Carrier;
prach = occasion.PRACH;
if ~isempty(opts.PreambleIndex)
    prach.PreambleIndex = double(opts.PreambleIndex);
end

[symbols, symbolInfo] = nrPRACH(carrier, prach);
indices = nrPRACHIndices(carrier, prach);

seq = struct();
seq.Symbols = symbols;
seq.Indices = indices;
seq.SymbolInfo = symbolInfo;
seq.PreambleIndex = double(prach.PreambleIndex);
seq.SequenceIndex = double(prach.SequenceIndex);
seq.ZeroCorrelationZone = double(prach.ZeroCorrelationZone);
seq.RestrictedSet = char(string(prach.RestrictedSet));
seq.Format = char(string(prach.Format));
seq.LRA = double(prach.LRA);
seq.Carrier = carrier;
seq.PRACH = prach;
seq.Occasion = occasion;
end
