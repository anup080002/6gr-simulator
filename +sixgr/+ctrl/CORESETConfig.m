function coreset = CORESETConfig(raw, ctrlCfg)
%CORESETConfig Resolve the 6GR CORESET study configuration.

if nargin < 1 || isempty(raw)
    raw = struct();
end

coreset = struct();
coreset.CORESETID = double(sixgr.util.structGet(raw, "CORESETID", 0));
coreset.DurationSymbols = localIntegerField(raw, "DurationSymbols", 2, ...
    true, "sixgr:ctrl:CORESETConfig:BadDuration");
coreset.StartSymbol = localIntegerField(raw, "StartSymbol", 0, ...
    false, "sixgr:ctrl:CORESETConfig:BadSymbolWindow");
coreset.FrequencyAllocationMode = char(string(sixgr.util.structGet(raw, "FrequencyAllocationMode", "contiguous")));
coreset.FrequencyResourceMask = sixgr.util.structGet(raw, "FrequencyResourceMask", []);
coreset.NumRB = localIntegerField(raw, "NumRB", ...
    min(24, ctrlCfg.NSizeGrid), true, ...
    "sixgr:ctrl:CORESETConfig:BadFrequencyAllocation");
coreset.RBStart = localIntegerField(raw, "RBStart", 0, false, ...
    "sixgr:ctrl:CORESETConfig:BadFrequencyAllocation");
coreset.RBSetList = double(sixgr.util.structGet(raw, "RBSetList", []));
coreset.REGSizeRE = max(1, round(double(sixgr.util.structGet(raw, "REGSizeRE", 12))));
coreset.REGBundleSize = max(1, round(double(sixgr.util.structGet(raw, "REGBundleSize", 2))));
coreset.InterleavingEnabled = logical(sixgr.util.structGet(raw, "InterleavingEnabled", false));
coreset.InterleaverSize = max(1, round(double(sixgr.util.structGet(raw, "InterleaverSize", 2))));
coreset.ShiftIndex = max(0, round(double(sixgr.util.structGet(raw, "ShiftIndex", ctrlCfg.CellID))));
coreset.NumREGPerCCE = max(1, round(double(sixgr.util.structGet(raw, "NumREGPerCCE", 6))));
coreset.REGIndexingMode = char(string(sixgr.util.structGet(raw, "REGIndexingMode", "sequential_reg_groups")));
coreset.MappingType = char(string(sixgr.util.structGet(raw, "MappingType", "noninterleaved")));
coreset.DMRSPortSet = double(sixgr.util.structGet(raw, "DMRSPortSet", 0));
coreset.DMRSAdditionalPositions = max(0, round(double(sixgr.util.structGet(raw, "DMRSAdditionalPositions", 0))));
coreset.DMRSConfigType = char(string(sixgr.util.structGet(raw, "DMRSConfigType", "single_port_density_3_per_rb")));
coreset.MaxCandidatesPerAL = sixgr.util.structGet(raw, "MaxCandidatesPerAL", struct("AL1", 8, "AL2", 4, "AL4", 2, "AL8", 1, "AL16", 1));
coreset.AssociatedSearchSpaceIDs = double(sixgr.util.structGet(raw, "AssociatedSearchSpaceIDs", []));
coreset.StudyLabel = "agreed_starting_point";

switch lower(string(coreset.FrequencyAllocationMode))
    case "contiguous"
        rbList = coreset.RBStart + (0:coreset.NumRB-1);
    case "noncontiguous"
        rbList = unique(double(coreset.RBSetList(:).'), "stable");
        if isempty(rbList)
            error("sixgr:ctrl:CORESETConfig:MissingRBSetList", ...
                "Noncontiguous CORESET allocation requires RBSetList.");
        end
        if any(~isfinite(rbList)) || any(rbList ~= fix(rbList))
            error("sixgr:ctrl:CORESETConfig:BadFrequencyAllocation", ...
                "Noncontiguous CORESET RBSetList must contain zero-based integers.");
        end
    otherwise
        error("sixgr:ctrl:CORESETConfig:BadFrequencyMode", ...
            "FrequencyAllocationMode must be contiguous or noncontiguous.");
end

if any(rbList < 0) || any(rbList >= ctrlCfg.NSizeGrid)
    error("sixgr:ctrl:CORESETConfig:RBOutOfRange", ...
        "CORESET RB allocation exceeds the configured carrier grid.");
end
if coreset.DurationSymbols > 3
    error("sixgr:ctrl:CORESETConfig:BadDuration", ...
        "CORESET DurationSymbols must be an integer in [1,3].");
end
symbolsPerSlot = double(sixgr.util.structGet( ...
    ctrlCfg, "SymbolsPerSlot", 14));
if ~(isscalar(symbolsPerSlot) && isfinite(symbolsPerSlot) && ...
        symbolsPerSlot >= 1 && symbolsPerSlot == fix(symbolsPerSlot))
    error("sixgr:ctrl:CORESETConfig:BadSymbolWindow", ...
        "SymbolsPerSlot must be a positive integer.");
end
if coreset.StartSymbol + coreset.DurationSymbols > symbolsPerSlot
    error("sixgr:ctrl:CORESETConfig:BadSymbolWindow", ...
        "CORESET duration exceeds the slot symbol budget.");
end
scs_kHz = double(sixgr.util.structGet(ctrlCfg, "SubcarrierSpacing_kHz", ...
    sixgr.util.structGet(ctrlCfg, "SubcarrierSpacing", NaN)));
if isfinite(scs_kHz) && scs_kHz >= 120 && coreset.DurationSymbols > 1
    error("sixgr:ctrl:CORESETConfig:InvalidDurationForSCS", ...
        "CORESET duration %d is not allowed for SCS %.0f kHz; use one symbol for SCS >= 120 kHz.", ...
        coreset.DurationSymbols, scs_kHz);
end
if ~ismember(lower(string(coreset.MappingType)), ["noninterleaved","interleaved"])
    error("sixgr:ctrl:CORESETConfig:BadMappingType", ...
        "MappingType must be noninterleaved or interleaved.");
end

coreset.RBList = rbList(:).';
coreset.TotalSubcarriers = numel(coreset.RBList) * 12;
if coreset.REGSizeRE > coreset.TotalSubcarriers
    error("sixgr:ctrl:CORESETConfig:BadREGSize", ...
        "REGSizeRE=%d exceeds the allocated CORESET frequency span.", coreset.REGSizeRE);
end
end

function value = localIntegerField(raw, field, defaultValue, positive, errorID)
value = double(sixgr.util.structGet(raw, field, defaultValue));
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value == fix(value);
if positive
    valid = valid && value > 0;
else
    valid = valid && value >= 0;
end
if ~valid
    if positive
        constraint = "a positive integer";
    else
        constraint = "a nonnegative integer";
    end
    error(errorID, "CORESET %s must be %s; received '%s'.", ...
        field, constraint, string(value));
end
end
