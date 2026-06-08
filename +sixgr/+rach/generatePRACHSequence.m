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

carrier = localCarrierFromOccasionOrCfg(occasion, cfg);
prach = localPRACHFromOccasionOrCfg(occasion, cfg);
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

function carrier = localCarrierFromOccasionOrCfg(occasion, cfg)
carrier = nrCarrierConfig;
snap = sixgr.util.structGet(occasion, "Carrier", struct());
carrier.SubcarrierSpacing = double(sixgr.util.structGet(snap, "SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "CarrierSCSkHz", 15)));
carrier.NSizeGrid = double(sixgr.util.structGet(snap, "NSizeGrid", ...
    sixgr.util.structGet(cfg, "NSizeGrid", 52)));
carrier.NStartGrid = double(sixgr.util.structGet(snap, "NStartGrid", 0));
carrier.NCellID = double(sixgr.util.structGet(snap, "NCellID", 1));
carrier.NSlot = double(sixgr.util.structGet(snap, "NSlot", ...
    max(0, double(sixgr.util.structGet(occasion, "SlotIndex1", 1)) - 1)));
carrier.CyclicPrefix = char(string(sixgr.util.structGet(snap, "CyclicPrefix", "normal")));
end

function prach = localPRACHFromOccasionOrCfg(occasion, cfg)
prach = nrPRACHConfig;
snap = sixgr.util.structGet(occasion, "PRACH", struct());
prach.FrequencyRange = char(string(sixgr.util.structGet(snap, "FrequencyRange", ...
    sixgr.util.structGet(cfg, "FrequencyRange", "FR1"))));
prach.DuplexMode = char(string(sixgr.util.structGet(snap, "DuplexMode", ...
    sixgr.util.structGet(cfg, "DuplexMode", "FDD"))));
prach.ConfigurationIndex = double(sixgr.util.structGet(snap, "ConfigurationIndex", ...
    sixgr.util.structGet(cfg, "PRACHConfigurationIndex", 16)));
prach.SubcarrierSpacing = double(sixgr.util.structGet(snap, "SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "PRACHSubcarrierSpacing", 1.25)));
prach.SequenceIndex = double(sixgr.util.structGet(snap, "SequenceIndex", ...
    sixgr.util.structGet(cfg, "SequenceIndex", 0)));
prach.PreambleIndex = double(sixgr.util.structGet(snap, "PreambleIndex", ...
    localFirstPreamble(sixgr.util.structGet(cfg, "PreambleIndex", 0))));
prach.RestrictedSet = char(string(sixgr.util.structGet(snap, "RestrictedSet", ...
    sixgr.util.structGet(cfg, "RestrictedSet", "UnrestrictedSet"))));
prach.ZeroCorrelationZone = double(sixgr.util.structGet(snap, "ZeroCorrelationZone", ...
    sixgr.util.structGet(cfg, "ZeroCorrelationZone", 0)));
prach.FrequencyStart = double(sixgr.util.structGet(snap, "FrequencyStart", ...
    sixgr.util.structGet(cfg, "FrequencyStart", 0)));
prach.NPRACHSlot = double(sixgr.util.structGet(snap, "NPRACHSlot", ...
    max(0, double(sixgr.util.structGet(occasion, "SlotIndex1", 1)) - 1)));
try
    prach.TimeIndex = double(sixgr.util.structGet(snap, "TimeIndex", ...
        sixgr.util.structGet(occasion, "TimeIndex", 0)));
catch
end
end

function value = localFirstPreamble(spec)
arr = double(spec(:));
arr = arr(isfinite(arr));
if isempty(arr)
    value = 0;
else
    value = arr(1);
end
end
