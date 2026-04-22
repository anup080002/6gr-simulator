function occasion = mapPRACHToOccasion(cfg, varargin)
%MAPPRACHTOOCCASION Resolve a valid PRACH occasion in slot/time space.

p = inputParser;
p.FunctionName = "sixgr.rach.mapPRACHToOccasion";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "OccasionIndex", 1, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
addParameter(p, "Carrier", [], @(x) isempty(x) || isa(x, "nrCarrierConfig"));
addParameter(p, "PRACH", [], @(x) isempty(x) || isa(x, "nrPRACHConfig"));
parse(p, cfg, varargin{:});
opts = p.Results;

if isfield(cfg, "ToolboxCarrier") && isempty(opts.Carrier)
    carrier = cfg.ToolboxCarrier;
else
    carrier = nrCarrierConfig;
    carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "CarrierSCSkHz", 15));
    carrier.NSizeGrid = double(sixgr.util.structGet(cfg, "NSizeGrid", 52));
    carrier.NStartGrid = 0;
    carrier.NCellID = 1;
end

if isfield(cfg, "ToolboxPRACH") && isempty(opts.PRACH)
    prach = cfg.ToolboxPRACH;
else
    prach = nrPRACHConfig;
    prach.FrequencyRange = char(string(sixgr.util.structGet(cfg, "FrequencyRange", "FR1")));
    prach.DuplexMode = char(string(sixgr.util.structGet(cfg, "DuplexMode", "FDD")));
    prach.ConfigurationIndex = double(sixgr.util.structGet(cfg, "PRACHConfigurationIndex", 16));
    prach.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "PRACHSubcarrierSpacing", 1.25));
    prach.SequenceIndex = double(sixgr.util.structGet(cfg, "SequenceIndex", 0));
    prach.PreambleIndex = double(localFirstPreamble(sixgr.util.structGet(cfg, "PreambleIndex", 0)));
    prach.RestrictedSet = char(string(sixgr.util.structGet(cfg, "RestrictedSet", "UnrestrictedSet")));
    prach.ZeroCorrelationZone = double(sixgr.util.structGet(cfg, "ZeroCorrelationZone", 0));
    prach.FrequencyStart = double(sixgr.util.structGet(cfg, "FrequencyStart", 0));
end

ordinalTarget = round(double(opts.OccasionIndex));
numSlots = round(double(sixgr.util.structGet(cfg, "NumSlots", 40)));
ordinal = 0;

for slotIdx = 0:max(0, numSlots - 1)
    carrier.NSlot = double(slotIdx);
    prach.NPRACHSlot = double(slotIdx);
    numTimeOcc = max(1, double(prach.NumTimeOccasions));
    for timeIdx = 0:max(0, numTimeOcc - 1)
        try
            prach.TimeIndex = double(timeIdx);
        catch
        end
        try
            prachSym = nrPRACH(carrier, prach);
            prachInd = nrPRACHIndices(carrier, prach);
        catch
            prachSym = [];
            prachInd = [];
        end
        if isempty(prachSym) || isempty(prachInd)
            continue;
        end
        ordinal = ordinal + 1;
        if ordinal ~= ordinalTarget
            continue;
        end
        occasion = struct();
        occasion.Ordinal = ordinal;
        occasion.SlotIndex0 = slotIdx;
        occasion.SlotIndex1 = slotIdx + 1;
        occasion.TimeIndex = timeIdx;
        occasion.FrequencyStart = double(prach.FrequencyStart);
        occasion.SymbolLocation = double(prach.SymbolLocation);
        occasion.PRACHDuration = double(prach.PRACHDuration);
        occasion.NumTimeOccasions = double(prach.NumTimeOccasions);
        occasion.Carrier = carrier;
        occasion.PRACH = prach;
        occasion.Indices = prachInd;
        occasion.Symbols = prachSym;
        return;
    end
end

error("sixgr:rach:mapPRACHToOccasion:NoSuchOccasion", ...
    "Could not materialize PRACH occasion %g within %g scanned slots.", ordinalTarget, numSlots);
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
