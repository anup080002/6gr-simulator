function cfg = validateConfig(cfg, varargin)
%VALIDATECONFIG Fail-closed validation for the waveform-only LLS contract.

ip = inputParser;
ip.addParameter("ConfigPath", "<struct>", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
context = string(ip.Results.ConfigPath);

if ~(isstruct(cfg) && isscalar(cfg))
    error("sixgr:lls:InvalidConfig", "LLS configuration must be a scalar struct.");
end

localRequiredText(cfg, "scenario.id");
localAllowedText(cfg, "simulation.mode", "LLS");
link = upper(string(localAllowedText(cfg, "simulation.link", ["PUSCH","PDSCH"])));
localAllowedText(cfg, "simulation.executionBackend", "waveform_truth");
localAllowedText(cfg, "simulation.statisticalClass", ["publication_candidate","diagnostic_only"]);
localRequiredInteger(cfg, "simulation.masterSeed", 0, 2^32-1);
snrDb = localRequiredVector(cfg, "simulation.snrDb");
if isempty(snrDb) || any(~isfinite(snrDb)) || numel(unique(snrDb)) ~= numel(snrDb)
    error("sixgr:lls:InvalidSNRSweep", ...
        "simulation.snrDb must contain unique finite operating points in %s.", context);
end
localRequiredInteger(cfg, "simulation.minTransportBlocks", 1, Inf);
localRequiredInteger(cfg, "simulation.minBlockErrors", 1, Inf);
localRequiredInteger(cfg, "simulation.maxTransportBlocks", 1, Inf);
minTB = double(sixgr.util.structGet(cfg, "simulation.minTransportBlocks", NaN));
maxTB = double(sixgr.util.structGet(cfg, "simulation.maxTransportBlocks", NaN));
if maxTB < minTB
    error("sixgr:lls:InvalidStoppingRule", ...
        "simulation.maxTransportBlocks must be >= minTransportBlocks.");
end

forbidden = ["geometry","topology","sites","scheduler","traffic","rrc", ...
    "ueCoordinates","bsCoordinates","cellRadius","pathloss","servingCell", ...
    "linkAbstraction","blerLookup","sinrToBler"];
paths = localLeafPaths(cfg, "");
lowerPaths = lower(paths);
for idx = 1:numel(forbidden)
    token = lower(forbidden(idx));
    if any(lowerPaths == token | startsWith(lowerPaths, token + ".") | ...
            endsWith(lowerPaths, "." + token) | contains(lowerPaths, "." + token + "."))
        error("sixgr:lls:ForbiddenSystemLevelInput", ...
            "Core waveform LLS config may not contain system-level field '%s'.", forbidden(idx));
    end
end

localRequiredPositive(cfg, "carrier.frequencyHz");
scs = localRequiredMember(cfg, "carrier.subcarrierSpacingKHz", [15 30 60 120 240]);
nSizeGrid = localRequiredInteger(cfg, "carrier.nSizeGrid", 1, 275);
localRequiredInteger(cfg, "carrier.nCellId", 0, 1007);
localAllowedText(cfg, "carrier.cyclicPrefix", ["normal","extended"]);
if scs ~= 60 && strcmpi(string(sixgr.util.structGet(cfg, "carrier.cyclicPrefix", "")), "extended")
    error("sixgr:lls:InvalidCyclicPrefix", ...
        "Extended cyclic prefix is only supported at 60 kHz SCS.");
end

nPRB = localRequiredInteger(cfg, "allocation.numberPRB", 1, nSizeGrid);
startPRB = localRequiredInteger(cfg, "allocation.startPRB", 0, nSizeGrid-1);
if startPRB + nPRB > nSizeGrid
    error("sixgr:lls:AllocationOutsideCarrier", ...
        "PUSCH PRB allocation [%d,%d] exceeds carrier.nSizeGrid=%d.", ...
        startPRB, startPRB+nPRB-1, nSizeGrid);
end
symbols = localRequiredVector(cfg, "allocation.symbols");
if numel(symbols) ~= 2 || symbols(1) < 0 || symbols(2) < 1 || ...
        any(symbols ~= fix(symbols)) || sum(symbols) > 14
    error("sixgr:lls:InvalidSymbolAllocation", ...
        "allocation.symbols must be [zeroBasedStart positiveLength] within one normal-CP slot.");
end
localAllowedText(cfg, "allocation.mappingType", ["A","B"]);

linkPath = lower(link);
modulation = upper(string(localRequiredText(cfg, linkPath + ".modulation")));
if ~ismember(modulation, ["QPSK","16QAM","64QAM","256QAM"])
    error("sixgr:lls:UnsupportedModulation", ...
        "Baseline %s modulation must be QPSK, 16QAM, 64QAM, or 256QAM.", link);
end
localAllowedText(cfg, linkPath + ".tbsMode", "derived_from_exact_allocation");
layers = localRequiredInteger(cfg, linkPath + ".numberLayers", 1, 4);
ports = localRequiredInteger(cfg, linkPath + ".numberAntennaPorts", 1, 4);
if ports < layers
    error("sixgr:lls:InvalidAntennaLayerTuple", ...
        "%s antenna ports (%d) cannot be fewer than layers (%d).", link, ports, layers);
end
localRequiredInteger(cfg, linkPath + ".rnti", 0, 65535);
localRequiredInteger(cfg, linkPath + ".nid", 0, 1023);
localRequiredOpenUnit(cfg, linkPath + ".targetCodeRate");
localRequiredInteger(cfg, linkPath + ".mcsIndex", 0, 31);
if link == "PDSCH"
    localRequiredText(cfg, "pdsch.mcsTable");
    localRequiredLogical(cfg, "pdsch.mcsContext.ueCapability1024QAM");
    localRequiredLogical(cfg, "pdsch.mcsContext.rrcEnabled1024QAM");
    localRequiredLogical(cfg, "pdsch.mcsContext.dciEnabled1024QAM");
    localRequiredLogical(cfg, "pdsch.mcsContext.deploymentAllows1024QAM");
    localRequiredLogical(cfg, "pdsch.mcsContext.frequencyRangeAllows1024QAM");
    localRequiredLogical(cfg, "pdsch.mcsContext.bandAllows1024QAM");
    localRequiredText(cfg, "pdsch.mcsContext.frequencyRange");
    localRequiredText(cfg, "pdsch.mcsContext.operatingBand");
    localRequiredText(cfg, "pdsch.mcsContext.deploymentClass");
end
localRequiredInteger(cfg, linkPath + ".rv", 0, 3);
localRequiredInteger(cfg, linkPath + ".xOverhead", 0, 156);
localAllowedText(cfg, linkPath + ".transmissionScheme", ["nonCodebook","codebook","identity"]);
if link == "PUSCH"
    localRequiredLogical(cfg, "pusch.transformPrecoding");
end
localRequiredLogical(cfg, linkPath + ".ptrs.enabled");
localRequiredInteger(cfg, linkPath + ".dmrs.typeAPosition", 2, 3);
localRequiredMember(cfg, linkPath + ".dmrs.configurationType", [1 2]);
localRequiredInteger(cfg, linkPath + ".dmrs.additionalPositions", 0, 3);
localRequiredMember(cfg, linkPath + ".dmrs.length", [1 2]);
localRequiredInteger(cfg, linkPath + ".dmrs.numCDMGroupsWithoutData", 1, 3);
portsSet = localRequiredVector(cfg, linkPath + ".dmrs.portSet");
if numel(portsSet) ~= layers || any(portsSet < 0 | portsSet ~= fix(portsSet)) || ...
        numel(unique(portsSet)) ~= numel(portsSet)
    error("sixgr:lls:InvalidDMRSPortSet", ...
        "%s.dmrs.portSet must contain one unique zero-based port per layer.", linkPath);
end
if link == "PUSCH"
    localRequiredLogical(cfg, "pusch.dmrs.groupHopping");
    localRequiredLogical(cfg, "pusch.dmrs.sequenceHopping");
    if logical(cfg.pusch.dmrs.groupHopping) && logical(cfg.pusch.dmrs.sequenceHopping)
        error("sixgr:lls:InvalidDMRSHopping", ...
            "DM-RS group hopping and sequence hopping cannot both be enabled.");
    end
end

model = upper(string(localRequiredText(cfg, "channel.model")));
allowedModels = ["AWGN","TDL-A","TDL-B","TDL-C","TDL-D","TDL-E", ...
    "CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"];
if ~ismember(model, allowedModels)
    error("sixgr:lls:UnsupportedChannel", ...
        "channel.model must be AWGN or a concrete TDL-/CDL- profile, not a family token.");
end
txAnt = localRequiredInteger(cfg, "channel.txAntennas", 1, Inf);
rxAnt = localRequiredInteger(cfg, "channel.rxAntennas", 1, Inf);
if model == "AWGN" && (txAnt ~= 1 || rxAnt ~= 1 || layers ~= 1 || ports ~= 1)
    error("sixgr:lls:AWGNBaselineRequiresSISO", ...
        "The first AWGN reference profile is deliberately SISO/rank-1; use a later MIMO profile for multiple ports.");
end
localRequiredInteger(cfg, "channel.seed", 0, 2^32-1);
localAllowedText(cfg, "channel.normalization", "occupied_re_esn0");
delaySpread = double(sixgr.util.structGet(cfg, "channel.delaySpreadSeconds", NaN));
velocity = double(sixgr.util.structGet(cfg, "channel.velocityKmph", NaN));
if ~(isscalar(delaySpread) && isfinite(delaySpread) && delaySpread >= 0) || ...
        ~(isscalar(velocity) && isfinite(velocity) && velocity >= 0)
    error("sixgr:lls:InvalidFadingParameters", ...
        "channel.delaySpreadSeconds and velocityKmph must be finite and nonnegative.");
end
if model ~= "AWGN" && delaySpread <= 0
    error("sixgr:lls:InvalidFadingParameters", ...
        "A concrete TDL/CDL profile requires a positive channel.delaySpreadSeconds.");
end

estimation = lower(string(localRequiredText(cfg, "receiver.channelEstimation")));
if ~ismember(estimation, ["perfect","practical"])
    error("sixgr:lls:InvalidChannelEstimation", ...
        "receiver.channelEstimation must be perfect or practical.");
end
if link == "PDSCH" && estimation == "perfect"
    error("sixgr:lls:PDSCHPerfectCSIUnavailable", ...
        ["The production PDSCH receiver currently exposes DM-RS-based practical " ...
         "estimation but no exact-channel oracle trust boundary. Use practical " ...
         "or implement and qualify a true per-RE PDSCH oracle before claiming perfect CSI."]);
end
localAllowedText(cfg, "receiver.equalizer", ["MMSE","ZF"]);
localRequiredInteger(cfg, "receiver.ldpcMaxIterations", 1, Inf);
localRequiredText(cfg, "receiver.ldpcAlgorithm");
confidence = double(sixgr.util.structGet(cfg, "simulation.confidenceLevel", NaN));
if ~(isscalar(confidence) && isfinite(confidence) && confidence > 0 && confidence < 1)
    error("sixgr:lls:InvalidConfidenceLevel", ...
        "simulation.confidenceLevel must be strictly between zero and one.");
end
localRequiredLogical(cfg, "harq.enabled");
if logical(sixgr.util.structGet(cfg, "harq.enabled", true))
    error("sixgr:lls:HARQNotBaseline", ...
        "HARQ must be disabled for the first-transmission baseline curve.");
end
localRequiredLogical(cfg, "linkAdaptation.enabled");
if logical(sixgr.util.structGet(cfg, "linkAdaptation.enabled", true))
    error("sixgr:lls:LinkAdaptationNotFixedMCS", ...
        "Basic RAN1 BLER curves require fixed MCS/TBS; link adaptation must be disabled.");
end
localRequiredLogical(cfg, "results.generatePlots");
localRequiredText(cfg, "results.outputRoot");
localAllowedText(cfg, "results.imageFormat", "png");
end

function value = localRequiredText(cfg, path)
value = string(sixgr.util.structGet(cfg, path, ""));
if ~isscalar(value) || strlength(strtrim(value)) == 0
    error("sixgr:lls:MissingConfigField", "Required text field '%s' is missing.", path);
end
end

function value = localAllowedText(cfg, path, allowed)
value = localRequiredText(cfg, path);
if ~any(strcmpi(value, string(allowed)))
    error("sixgr:lls:InvalidConfigValue", ...
        "Field '%s' has unsupported value '%s'.", path, value);
end
end

function value = localRequiredVector(cfg, path)
value = double(sixgr.util.structGet(cfg, path, []));
value = value(:).';
if isempty(value) || any(~isfinite(value))
    error("sixgr:lls:MissingConfigField", "Required numeric vector '%s' is missing or invalid.", path);
end
end

function value = localRequiredInteger(cfg, path, minValue, maxValue)
value = double(sixgr.util.structGet(cfg, path, NaN));
if ~(isscalar(value) && isfinite(value) && value == fix(value) && value >= minValue && value <= maxValue)
    error("sixgr:lls:InvalidConfigValue", "Field '%s' must be an integer in [%g,%g].", path, minValue, maxValue);
end
end

function value = localRequiredMember(cfg, path, members)
value = double(sixgr.util.structGet(cfg, path, NaN));
if ~(isscalar(value) && isfinite(value) && any(value == members))
    error("sixgr:lls:InvalidConfigValue", "Field '%s' has unsupported value.", path);
end
end

function value = localRequiredPositive(cfg, path)
value = double(sixgr.util.structGet(cfg, path, NaN));
if ~(isscalar(value) && isfinite(value) && value > 0)
    error("sixgr:lls:InvalidConfigValue", "Field '%s' must be positive and finite.", path);
end
end

function value = localRequiredOpenUnit(cfg, path)
value = double(sixgr.util.structGet(cfg, path, NaN));
if ~(isscalar(value) && isfinite(value) && value > 0 && value < 1)
    error("sixgr:lls:InvalidConfigValue", "Field '%s' must be strictly between zero and one.", path);
end
end

function value = localRequiredLogical(cfg, path)
value = sixgr.util.structGet(cfg, path, []);
if ~((islogical(value) || isnumeric(value)) && isscalar(value) && isfinite(double(value)) && any(double(value) == [0 1]))
    error("sixgr:lls:InvalidConfigValue", "Field '%s' must be a Boolean scalar.", path);
end
value = logical(value);
end

function paths = localLeafPaths(value, prefix)
paths = strings(0,1);
if isstruct(value) && isscalar(value)
    names = fieldnames(value);
    for idx = 1:numel(names)
        if strlength(prefix) == 0
            child = string(names{idx});
        else
            child = prefix + "." + string(names{idx});
        end
        paths = [paths; child; localLeafPaths(value.(names{idx}), child)]; %#ok<AGROW>
    end
end
end
