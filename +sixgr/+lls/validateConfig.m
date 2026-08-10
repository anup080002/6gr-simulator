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
studyType = lower(string(localAllowedText(cfg,"simulation.studyType", ...
    ["fixed_mcs_bler","harq_throughput","interference_bler","link_adaptation_throughput"])));
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
localRequiredLogical(cfg,"execution.parallelEnabled");
localRequiredInteger(cfg,"execution.maximumWorkers",1,Inf);
localRequiredInteger(cfg,"execution.batchTransportBlocks",1,Inf);

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
if link == "PDSCH"
    maxLayers = 8;
    maxPorts = 64;
else
    maxLayers = 4;
    maxPorts = 4;
end
layers = localRequiredInteger(cfg, linkPath + ".numberLayers", 1, maxLayers);
ports = localRequiredInteger(cfg, linkPath + ".numberAntennaPorts", 1, maxPorts);
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
    transformPrecoding = localRequiredLogical(cfg, "pusch.transformPrecoding");
end
localRequiredLogical(cfg, linkPath + ".ptrs.enabled");
localRequiredMember(cfg, linkPath + ".ptrs.timeDensity", [1 2 4]);
localRequiredMember(cfg, linkPath + ".ptrs.frequencyDensity", [2 4]);
localAllowedText(cfg, linkPath + ".ptrs.reOffset", ["00","01","10","11"]);
ptrsPolicy = lower(string(localAllowedText(cfg, ...
    linkPath + ".ptrs.portAssociationPolicy", ...
    ["first_scheduled_dmrs_port","configured_absolute_port"])));
ptrsPorts = localRequiredVector(cfg, linkPath + ".ptrs.portSet");
if any(ptrsPorts < 0 | ptrsPorts ~= fix(ptrsPorts)) ...
        || numel(unique(ptrsPorts)) ~= numel(ptrsPorts)
    error("sixgr:lls:InvalidPTRSPortSet", ...
        "%s.ptrs.portSet must contain unique zero-based integer ports.", linkPath);
end
localRequiredLogical(cfg, linkPath + ".ptrs.cpeCorrection");
if link == "PUSCH"
    localRequiredInteger(cfg, "pusch.ptrs.nid", 0, 1007);
    localRequiredMember(cfg, "pusch.ptrs.numPTRSSamples", [2 4]);
    localRequiredMember(cfg, "pusch.ptrs.numPTRSGroups", [2 4 8]);
end
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
if logical(sixgr.util.structGet(cfg, linkPath + ".ptrs.enabled", false)) ...
        && ptrsPolicy == "configured_absolute_port" ...
        && (numel(ptrsPorts) ~= 1 || ~ismember(ptrsPorts, portsSet))
    error("sixgr:lls:InvalidPTRSPortSet", ...
        "Enabled configured_absolute_port PT-RS requires exactly one port from %s.dmrs.portSet.", ...
        linkPath);
end
if link == "PUSCH"
    localRequiredLogical(cfg, "pusch.dmrs.groupHopping");
    localRequiredLogical(cfg, "pusch.dmrs.sequenceHopping");
    if logical(cfg.pusch.dmrs.groupHopping) && logical(cfg.pusch.dmrs.sequenceHopping)
        error("sixgr:lls:InvalidDMRSHopping", ...
            "DM-RS group hopping and sequence hopping cannot both be enabled.");
    end
    if transformPrecoding ...
            && double(cfg.pusch.dmrs.numCDMGroupsWithoutData) ~= 2
        error("sixgr:lls:TransformPrecodingDMRSConflict", ...
            ["pusch.transformPrecoding=true requires " ...
             "pusch.dmrs.numCDMGroupsWithoutData=2 for the executable NR waveform."]);
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
if model ~= "AWGN" && (txAnt < ports || rxAnt < layers)
    error("sixgr:lls:InsufficientMIMOArray", ...
        "Fading %s requires channel.txAntennas >= numberAntennaPorts and channel.rxAntennas >= numberLayers.", ...
        link);
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
if startsWith(model,"CDL-")
    localValidateCDLArray(cfg,"channel.cdl.transmitArray",txAnt);
    localValidateCDLArray(cfg,"channel.cdl.receiveArray",rxAnt);
end

localRequiredLogical(cfg,"interference.enabled");
interferenceEnabled = logical(sixgr.util.structGet(cfg,"interference.enabled",false));
dirDb = double(sixgr.util.structGet(cfg,"interference.desiredToInterferenceRatioDb",NaN));
if ~(isscalar(dirDb) && isfinite(dirDb))
    error("sixgr:lls:InvalidInterferenceConfiguration", ...
        "interference.desiredToInterferenceRatioDb must be a finite scalar.");
end
interfererRNTI = localRequiredInteger(cfg,"interference.rnti",0,65535);
interfererNID = localRequiredInteger(cfg,"interference.nid",0,1023);
if interferenceEnabled && interfererRNTI == double(sixgr.util.structGet(cfg,linkPath + ".rnti",NaN))
    error("sixgr:lls:InterfererIdentityCollision", ...
        "The desired and interfering links require distinct RNTIs.");
end
if interferenceEnabled && interfererNID == double(sixgr.util.structGet(cfg,linkPath + ".nid",NaN))
    error("sixgr:lls:InterfererIdentityCollision", ...
        "The desired and interfering links require distinct scrambling identities.");
end
interferenceModel = upper(string(localRequiredText(cfg,"interference.channel.model")));
if ~ismember(interferenceModel,allowedModels)
    error("sixgr:lls:UnsupportedInterferenceChannel", ...
        "interference.channel.model must be AWGN or a concrete TDL-/CDL- profile.");
end
interferenceTxAnt = localRequiredInteger(cfg,"interference.channel.txAntennas",1,Inf);
interferenceRxAnt = localRequiredInteger(cfg,"interference.channel.rxAntennas",1,Inf);
if interferenceEnabled && interferenceRxAnt ~= rxAnt
    error("sixgr:lls:InterferenceReceiverArrayMismatch", ...
        "Desired and interfering waveforms must terminate on the same %d-element receive array.",rxAnt);
end
if interferenceEnabled && interferenceTxAnt < ports
    error("sixgr:lls:InterferenceTransmitterArrayMismatch", ...
        "The interferer requires at least %d transmit antennas for the configured %s ports.",ports,link);
end
localRequiredInteger(cfg,"interference.channel.seed",0,2^32-1);
localAllowedText(cfg,"interference.channel.normalization","occupied_re_esn0");
interferenceDelay = double(sixgr.util.structGet(cfg,"interference.channel.delaySpreadSeconds",NaN));
interferenceVelocity = double(sixgr.util.structGet(cfg,"interference.channel.velocityKmph",NaN));
if ~(isscalar(interferenceDelay) && isfinite(interferenceDelay) && interferenceDelay >= 0) || ...
        ~(isscalar(interferenceVelocity) && isfinite(interferenceVelocity) && interferenceVelocity >= 0)
    error("sixgr:lls:InvalidInterferenceChannel", ...
        "Interferer delay spread and velocity must be finite and nonnegative.");
end
if interferenceModel ~= "AWGN" && interferenceDelay <= 0
    error("sixgr:lls:InvalidInterferenceChannel", ...
        "A fading interferer requires a positive delay spread.");
end
if interferenceEnabled && interferenceModel == "AWGN" && ...
        (interferenceTxAnt ~= 1 || interferenceRxAnt ~= 1 || layers ~= 1 || ports ~= 1)
    error("sixgr:lls:AWGNInterfererRequiresSISO", ...
        "The AWGN interferer profile is SISO/rank-1; configure a fading MIMO interferer otherwise.");
end
if interferenceEnabled && startsWith(interferenceModel,"CDL-")
    localValidateCDLArray(cfg,"interference.channel.cdl.transmitArray",interferenceTxAnt);
    localValidateCDLArray(cfg,"interference.channel.cdl.receiveArray",interferenceRxAnt);
end
if interferenceEnabled ~= (studyType == "interference_bler")
    error("sixgr:lls:StudyTypeFeatureMismatch", ...
        "interference.enabled is true exactly when simulation.studyType=interference_bler.");
end

estimation = lower(string(localRequiredText(cfg, "receiver.channelEstimation")));
if ~ismember(estimation, ["perfect","practical"])
    error("sixgr:lls:InvalidChannelEstimation", ...
        "receiver.channelEstimation must be perfect or practical.");
end
if link == "PDSCH"
    localAllowedText(cfg, "receiver.equalizer", "MMSE");
else
    localAllowedText(cfg, "receiver.equalizer", ["MMSE","ZF"]);
end
localRequiredInteger(cfg, "receiver.ldpcMaxIterations", 1, Inf);
localRequiredText(cfg, "receiver.ldpcAlgorithm");
localRequiredLogical(cfg, "receiver.useMexLDPC");
confidence = double(sixgr.util.structGet(cfg, "simulation.confidenceLevel", NaN));
if ~(isscalar(confidence) && isfinite(confidence) && confidence > 0 && confidence < 1)
    error("sixgr:lls:InvalidConfidenceLevel", ...
        "simulation.confidenceLevel must be strictly between zero and one.");
end
localRequiredLogical(cfg, "harq.enabled");
harqEnabled = logical(sixgr.util.structGet(cfg,"harq.enabled",false));
rvSequence = localRequiredVector(cfg,"harq.rvSequence");
if any(rvSequence < 0 | rvSequence > 3 | rvSequence ~= fix(rvSequence))
    error("sixgr:lls:InvalidHARQConfiguration", ...
        "harq.rvSequence must contain integer redundancy versions in [0,3].");
end
maxTransmissions = localRequiredInteger(cfg,"harq.maxTransmissions",1,4);
if numel(rvSequence) < maxTransmissions
    error("sixgr:lls:InvalidHARQConfiguration", ...
        "harq.rvSequence must cover every configured HARQ transmission.");
end
localAllowedText(cfg,"harq.stoppingMetric", ...
    ["first_transmission_bler","post_harq_residual_bler"]);
if harqEnabled ~= (studyType == "harq_throughput")
    error("sixgr:lls:StudyTypeFeatureMismatch", ...
        "harq.enabled is true exactly when simulation.studyType=harq_throughput.");
end
localRequiredLogical(cfg, "linkAdaptation.enabled");
if logical(sixgr.util.structGet(cfg, "linkAdaptation.enabled", true)) && ...
        studyType ~= "link_adaptation_throughput"
    error("sixgr:lls:LinkAdaptationNotFixedMCS", ...
        "Basic RAN1 BLER curves require fixed MCS/TBS; link adaptation must be disabled.");
end
if ~logical(sixgr.util.structGet(cfg,"linkAdaptation.enabled",false)) && ...
        studyType == "link_adaptation_throughput"
    error("sixgr:lls:StudyTypeFeatureMismatch", ...
        "link_adaptation_throughput requires linkAdaptation.enabled=true.");
end
if logical(sixgr.util.structGet(cfg,"linkAdaptation.enabled",false))
    mcsTable = lower(string(localAllowedText(cfg,"linkAdaptation.mcsTable", ...
        ["qam64_table1","qam256_table2","qam64LowSE_table3"])));
    cqiTable = lower(string(localAllowedText(cfg,"linkAdaptation.cqiTable", ...
        ["table1","table2","table3"]))); %#ok<NASGU>
    thresholds = localRequiredVector(cfg,"linkAdaptation.sinrThresholdsDb");
    if numel(thresholds) ~= 15 || any(diff(thresholds) <= 0)
        error("sixgr:lls:InvalidLinkAdaptationPolicy", ...
            "linkAdaptation.sinrThresholdsDb must contain 15 strictly increasing CQI thresholds.");
    end
    localRequiredText(cfg,"linkAdaptation.thresholdSource");
    localRequiredText(cfg,"linkAdaptation.thresholdValueRole");
    localRequiredText(cfg,"linkAdaptation.thresholdCalibrationId");
    initialMCS = localRequiredInteger(cfg,"linkAdaptation.initialMCSIndex",0,31);
    minimumMCS = localRequiredInteger(cfg,"linkAdaptation.minimumMCSIndex",0,31);
    maximumMCS = localRequiredInteger(cfg,"linkAdaptation.maximumMCSIndex",0,31);
    if minimumMCS > initialMCS || initialMCS > maximumMCS
        error("sixgr:lls:InvalidLinkAdaptationPolicy", ...
            "minimumMCSIndex <= initialMCSIndex <= maximumMCSIndex is required.");
    end
    if ~sixgr.link.resolveMCSProfile(mcsTable,maximumMCS).Valid
        error("sixgr:lls:InvalidLinkAdaptationPolicy", ...
            "maximumMCSIndex is not valid for linkAdaptation.mcsTable.");
    end
    feedbackDelay = localRequiredInteger(cfg,"linkAdaptation.feedbackDelaySlots",1,1); %#ok<NASGU>
    localRequiredLogical(cfg,"linkAdaptation.olla.enabled");
    initialOffset = localRequiredFinite(cfg,"linkAdaptation.olla.initialOffsetDb");
    ackStep = localRequiredPositive(cfg,"linkAdaptation.olla.ackStepDb");
    nackStep = localRequiredPositive(cfg,"linkAdaptation.olla.nackStepDb");
    minimumOffset = localRequiredFinite(cfg,"linkAdaptation.olla.minimumOffsetDb");
    maximumOffset = localRequiredFinite(cfg,"linkAdaptation.olla.maximumOffsetDb");
    if minimumOffset > initialOffset || initialOffset > maximumOffset
        error("sixgr:lls:InvalidLinkAdaptationPolicy", ...
            "OLLA minimumOffsetDb <= initialOffsetDb <= maximumOffsetDb is required.");
    end
    if ~(ackStep > 0 && nackStep > 0)
        error("sixgr:lls:InvalidLinkAdaptationPolicy", ...
            "OLLA ACK and NACK steps must be positive.");
    end
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

function value = localRequiredFinite(cfg,path)
value = double(sixgr.util.structGet(cfg,path,NaN));
if ~(isscalar(value) && isfinite(value))
    error("sixgr:lls:InvalidConfigValue","Field '%s' must be a finite scalar.",path);
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

function localValidateCDLArray(cfg,path,expectedAntennas)
arraySize = localRequiredVector(cfg,path + ".size");
if numel(arraySize) ~= 5 || any(arraySize < 1 | arraySize ~= fix(arraySize))
    error("sixgr:lls:InvalidCDLArrayConfiguration", ...
        "%s.size must be [M N P Mg Ng] with five positive integers.",path);
end
if prod(arraySize) ~= expectedAntennas
    error("sixgr:lls:CDLArrayAntennaCountMismatch", ...
        "%s.size has product %d, but the configured channel antenna count is %d.", ...
        path,prod(arraySize),expectedAntennas);
end
spacing = localRequiredVector(cfg,path + ".elementSpacingWavelength");
if numel(spacing) ~= 4 || any(spacing <= 0)
    error("sixgr:lls:InvalidCDLArrayConfiguration", ...
        "%s.elementSpacingWavelength must contain four positive values.",path);
end
angles = localRequiredVector(cfg,path + ".polarizationAnglesDeg");
if numel(angles) ~= arraySize(3)
    error("sixgr:lls:InvalidCDLArrayConfiguration", ...
        "%s.polarizationAnglesDeg must contain P=%d angles.",path,arraySize(3));
end
orientation = localRequiredVector(cfg,path + ".orientationDeg");
if numel(orientation) ~= 3
    error("sixgr:lls:InvalidCDLArrayConfiguration", ...
        "%s.orientationDeg must contain [bearing downtilt slant].",path);
end
localAllowedText(cfg,path + ".element",["38.901","isotropic"]);
localAllowedText(cfg,path + ".polarizationModel",["Model-1","Model-2"]);
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
