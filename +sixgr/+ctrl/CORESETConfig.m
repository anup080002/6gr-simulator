function coreset = CORESETConfig(raw, ctrlCfg)
%CORESETConfig Resolve the 6GR CORESET study configuration.

if nargin < 1 || isempty(raw)
    raw = struct();
end

coreset = struct();
coreset.CORESETID = double(sixgr.util.structGet(raw, "CORESETID", 0));
coreset.DurationSymbols = max(1, round(double(sixgr.util.structGet(raw, "DurationSymbols", 2))));
coreset.StartSymbol = max(0, round(double(sixgr.util.structGet(raw, "StartSymbol", 0))));
coreset.FrequencyAllocationMode = char(string(sixgr.util.structGet(raw, "FrequencyAllocationMode", "contiguous")));
coreset.FrequencyResourceMask = sixgr.util.structGet(raw, "FrequencyResourceMask", []);
coreset.NumRB = max(1, round(double(sixgr.util.structGet(raw, "NumRB", min(24, ctrlCfg.NSizeGrid)))));
coreset.RBStart = max(0, round(double(sixgr.util.structGet(raw, "RBStart", 0))));
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
        rbList = unique(round(double(coreset.RBSetList(:).')));
        if isempty(rbList)
            error("sixgr:ctrl:CORESETConfig:MissingRBSetList", ...
                "Noncontiguous CORESET allocation requires RBSetList.");
        end
    otherwise
        error("sixgr:ctrl:CORESETConfig:BadFrequencyMode", ...
            "FrequencyAllocationMode must be contiguous or noncontiguous.");
end

if any(rbList < 0) || any(rbList >= ctrlCfg.NSizeGrid)
    error("sixgr:ctrl:CORESETConfig:RBOutOfRange", ...
        "CORESET RB allocation exceeds the configured carrier grid.");
end
if coreset.StartSymbol + coreset.DurationSymbols > 14
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
