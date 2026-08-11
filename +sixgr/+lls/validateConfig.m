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
localRequiredText(cfg, linkPath + ".mcsTable");
if link == "PDSCH"
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
            "pusch.transformPrecoding=true requires " + ...
            "pusch.dmrs.numCDMGroupsWithoutData=2 for the executable NR waveform.");
    end
end

model = upper(string(localRequiredText(cfg, "channel.model")));
allowedModels = ["AWGN","TDL-A","TDL-B","TDL-C","TDL-D","TDL-E", ...
    "CDL-A","CDL-B","CDL-C","CDL-D","CDL-E", ...
    "NTN-TDL-A","NTN-TDL-B","NTN-TDL-C","NTN-TDL-D", ...
    "NTN-CDL-A","NTN-CDL-B","NTN-CDL-C","NTN-CDL-D"];
if ~ismember(model, allowedModels)
    error("sixgr:lls:UnsupportedChannel", ...
        "channel.model must be AWGN or a concrete terrestrial/NTN TDL/CDL " + ...
        "profile, not a family token.");
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
residualEnabled = localRequiredLogical(cfg,"synchronizationResidual.enabled");
residualTiming = double(sixgr.util.structGet(cfg, ...
    "synchronizationResidual.timingErrorSeconds",NaN));
residualFrequency = double(sixgr.util.structGet(cfg, ...
    "synchronizationResidual.frequencyErrorHz",NaN));
if ~(isscalar(residualTiming) && isfinite(residualTiming)) || ...
        ~(isscalar(residualFrequency) && isfinite(residualFrequency))
    error("sixgr:lls:InvalidSynchronizationResidual", ...
        "Synchronization residual timing and frequency must be finite scalars.");
end
localRequiredText(cfg,"synchronizationResidual.source");
receiverUsesResidualOracle = localRequiredLogical(cfg, ...
    "synchronizationResidual.receiverUsesOracle");
if receiverUsesResidualOracle
    error("sixgr:lls:SynchronizationResidualOracleForbidden", ...
        "The production receiver may not consume injected timing/CFO truth.");
end
if ~residualEnabled && (abs(residualTiming) > 0 || abs(residualFrequency) > 0)
    error("sixgr:lls:DisabledSynchronizationResidualNonzero", ...
        "Disabled synchronization residuals must have zero timing and frequency values.");
end
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
antennaEnabled = localRequiredLogical(cfg,"antenna.enabled");
if (startsWith(model,"CDL-") || startsWith(model,"NTN-CDL-")) && ~antennaEnabled
    localValidateCDLArray(cfg,"channel.cdl.transmitArray",txAnt);
    localValidateCDLArray(cfg,"channel.cdl.receiveArray",rxAnt);
end
localValidateNTN(cfg,model);
localValidateAntenna(cfg,model,link,ports,txAnt,rxAnt);
localValidateISAC(cfg,link,ports);

localRequiredLogical(cfg,"interference.enabled");
interferenceEnabled = logical(sixgr.util.structGet(cfg,"interference.enabled",false));
if logical(cfg.ntn.enabled) && interferenceEnabled
    error("sixgr:lls:NTNInterferenceConfigurationRequired", ...
        "Enabled NTN interference requires an independent NTN geometry, " + ...
        "Doppler and delay block for the interferer. This schema does not " + ...
        "silently reuse the desired-link orbit.");
end
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
dmrsResidualBoundEnabled = localRequiredLogical(cfg, ...
    "receiver.postEqualizationSINR.dmrsResidualBoundEnabled");
decisionResidualBoundEnabled = localRequiredLogical(cfg, ...
    "receiver.postEqualizationSINR.decisionDirectedResidualBoundEnabled");
localAllowedText(cfg,"receiver.decoderNoiseVariance.mode", ...
    ["post_equalization","pre_equalization"]);
if link == "PDSCH" && (dmrsResidualBoundEnabled || decisionResidualBoundEnabled)
    error("sixgr:lls:UnsupportedPDSCHResidualSINRBound", ...
        "PDSCH does not implement the PUSCH DM-RS/decision-directed " + ...
        "post-equalization SINR bounds; configure both receiver bounds false.");
end
localRequiredLogical(cfg,"provenance.requireGitCommit");
localRequiredLogical(cfg,"provenance.requireCleanWorktree");
localRequiredLogical(cfg,"provenance.requireStableSourceThroughoutRun");
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

function localValidateNTN(cfg,model)
enabled = localRequiredLogical(cfg,"ntn.enabled");
isNTNProfile = startsWith(model,"NTN-TDL-") || startsWith(model,"NTN-CDL-");
if enabled ~= isNTNProfile
    error("sixgr:lls:NTNEnableProfileMismatch", ...
        "ntn.enabled and channel.model must agree: enabled NTN requires an " + ...
        "NTN-TDL-* or NTN-CDL-* profile, and those profiles require ntn.enabled=true.");
end

localAllowedText(cfg,"ntn.standardReference","3GPP TR 38.811");
localAllowedText(cfg,"ntn.researchTaxonomy", ...
    ["baseline_benchmark","agreed_starting_point", ...
     "study_item_candidate","optional_research_experiment"]);
localAllowedText(cfg,"ntn.channelProfile", ...
    ["NTN-TDL-A","NTN-TDL-B","NTN-TDL-C","NTN-TDL-D", ...
     "NTN-CDL-A","NTN-CDL-B","NTN-CDL-C","NTN-CDL-D"]);
localAllowedText(cfg,"ntn.orbit.type",["LEO","MEO","GEO"]);
localAllowedText(cfg,"ntn.orbit.model","circular");
satelliteAltitudeM = localRequiredPositive(cfg,"ntn.orbit.satelliteAltitudeM");
groundAltitudeM = localRequiredFinite(cfg,"ntn.orbit.groundAltitudeM");
if groundAltitudeM < 0 || groundAltitudeM >= satelliteAltitudeM
    error("sixgr:lls:InvalidNTNAltitude", ...
        "ntn.orbit.groundAltitudeM must be nonnegative and below satelliteAltitudeM.");
end
elevationDeg = localRequiredFinite(cfg,"ntn.orbit.elevationAngleDeg");
if elevationDeg <= 0 || elevationDeg > 90
    error("sixgr:lls:InvalidNTNElevation", ...
        "ntn.orbit.elevationAngleDeg must be in (0,90] degrees.");
end
localRequiredFinite(cfg,"ntn.orbit.epochSeconds");
localAllowedText(cfg,"ntn.payload.architecture","regenerative_service_link");
localRequiredLogical(cfg,"ntn.doppler.satelliteMotionEnabled");
localRequiredLogical(cfg,"ntn.doppler.mobileMotionEnabled");
localAllowedText(cfg,"ntn.doppler.compensationMode", ...
    ["none","ideal_transmitter_geometry","ideal_receiver_geometry"]);
azimuthDeg = localRequiredFinite(cfg,"ntn.doppler.mobileDirectionAzimuthDeg");
zenithDeg = localRequiredFinite(cfg,"ntn.doppler.mobileDirectionZenithDeg");
if azimuthDeg < 0 || azimuthDeg > 360 || zenithDeg < 0 || zenithDeg > 180
    error("sixgr:lls:InvalidNTNDirection", ...
        "ntn.doppler mobile direction must use azimuth in [0,360] and " + ...
        "zenith in [0,180] degrees.");
end
delayEnabled = localRequiredLogical(cfg,"ntn.propagationDelay.enabled");
localAllowedText(cfg,"ntn.propagationDelay.model","static_slant_range");
delayCompensation = lower(string(localAllowedText(cfg, ...
    "ntn.propagationDelay.compensationMode", ...
    ["disabled","perfect_geometry_timing_advance"])));
if delayEnabled && delayCompensation ~= "perfect_geometry_timing_advance"
    error("sixgr:lls:UnsupportedNTNDelayCompensation", ...
        "The compact slot LLS requires perfect_geometry_timing_advance " + ...
        "when NTN propagation delay is enabled.");
end
if ~delayEnabled && delayCompensation ~= "disabled"
    error("sixgr:lls:InvalidNTNDelayCompensation", ...
        "Disabled NTN propagation delay requires compensationMode=disabled.");
end
localAllowedText(cfg,"ntn.tdl.mimoCorrelation",["Low","Medium","Medium-A","High","Custom"]);
localAllowedText(cfg,"ntn.tdl.polarization",["Co-Polar","Cross-Polar","Custom"]);
localRequiredLogical(cfg,"ntn.cdl.autoOrientSatelliteArray");
atmosphericEnabled = localRequiredLogical(cfg,"ntn.atmosphericLoss.enabled");
localAllowedText(cfg,"ntn.atmosphericLoss.model","ITU-R P.618");
if enabled && atmosphericEnabled
    error("sixgr:lls:NTNAtmosphericLossRequiresPowerBudgetMode", ...
        "ntn.atmosphericLoss.enabled=true requires a transmit-power/thermal-noise " + ...
        "link-budget study. The configured Es/N0 sweep cannot apply P.618 loss " + ...
        "without changing its SNR reference plane.");
end
if enabled && (exist("slantRangeCircularOrbit","file") ~= 2 || ...
        exist("dopplerShiftCircularOrbit","file") ~= 2)
    error("sixgr:lls:MissingSatelliteCommunicationsToolbox", ...
        "Enabled NTN execution requires Satellite Communications Toolbox.");
end
localRequiredLogical(cfg,"ntn.output.enabled");
localRequiredLogical(cfg,"ntn.output.structuredComponentFolders");
localRequiredLogical(cfg,"ntn.output.saveCSV");
localRequiredLogical(cfg,"ntn.output.savePNG");
localAllowedText(cfg,"ntn.output.imageFormat",["png","jpeg"]);
localRequiredInteger(cfg,"ntn.output.imageResolutionDPI",72,600);
localRequiredLogical(cfg,"ntn.output.prohibitSVG");
if enabled && (~logical(cfg.ntn.output.enabled) || ...
        ~logical(cfg.ntn.output.saveCSV) || ~logical(cfg.ntn.output.savePNG) || ...
        ~logical(cfg.ntn.output.prohibitSVG))
    error("sixgr:lls:IncompleteNTNOutputContract", ...
        "Enabled NTN requires CSV plus PNG/JPEG evidence and prohibitSVG=true.");
end
end

function localValidateAntenna(cfg,model,link,logicalPorts,txAnt,rxAnt)
enabled = localRequiredLogical(cfg,"antenna.enabled");
localAllowedText(cfg,"antenna.standardReference","3GPP TR 38.901");
localAllowedText(cfg,"antenna.researchTaxonomy", ...
    ["baseline_benchmark","agreed_starting_point", ...
     "study_item_candidate","optional_research_experiment"]);
localAllowedText(cfg,"antenna.couplingMode", ...
    ["disabled","cdl_physical_element_domain"]);
localAllowedText(cfg,"antenna.pointingMode", ...
    ["disabled","auto_first_path_boresight"]);
localAllowedText(cfg,"antenna.powerNormalization", ...
    ["disabled","unit_norm_per_logical_port"]);
if enabled && ~(startsWith(model,"CDL-") || startsWith(model,"NTN-CDL-"))
    error("sixgr:lls:AntennaPatternRequiresCDL", ...
        "antenna.enabled=true requires a concrete CDL-* or NTN-CDL-* " + ...
        "profile. TDL has no per-path angle state, so a plotted directional " + ...
        "array cannot honestly be coupled to that waveform.");
end

if enabled && ~strcmpi(string(cfg.antenna.couplingMode), ...
        "cdl_physical_element_domain")
    error("sixgr:lls:InvalidAntennaCouplingMode", ...
        "Enabled antenna execution requires couplingMode=cdl_physical_element_domain.");
end
if enabled && ~strcmpi(string(cfg.antenna.pointingMode), ...
        "auto_first_path_boresight")
    error("sixgr:lls:InvalidAntennaPointingMode", ...
        "Enabled antenna execution currently requires auto_first_path_boresight.");
end
if enabled && ~strcmpi(string(cfg.antenna.powerNormalization), ...
        "unit_norm_per_logical_port")
    error("sixgr:lls:InvalidAntennaPowerNormalization", ...
        "Enabled antenna execution requires unit_norm_per_logical_port.");
end

gnbElements = localValidateAntennaRole(cfg,"gnb",logicalPorts,link == "PDSCH");
ueElements = localValidateAntennaRole(cfg,"ue",logicalPorts,link == "PUSCH");
if ~enabled
    return;
end
if link == "PDSCH"
    expectedTx = gnbElements;
    expectedRx = ueElements;
else
    expectedTx = ueElements;
    expectedRx = gnbElements;
end
if txAnt ~= expectedTx || rxAnt ~= expectedRx
    error("sixgr:lls:AntennaChannelDimensionMismatch", ...
        "For %s, channel.txAntennas/channel.rxAntennas must equal the " + ...
        "executed physical transmitter/receiver element counts %d/%d, " + ...
        "but the configuration contains %d/%d.", ...
        link,expectedTx,expectedRx,txAnt,rxAnt);
end
if exist("phased.NRAntennaElement","class") ~= 8 || ...
        exist("phased.NRRectangularPanelArray","class") ~= 8
    error("sixgr:lls:MissingPhasedArraySystemToolbox", ...
        "antenna.enabled=true requires Phased Array System Toolbox NR antenna objects.");
end
end

function localValidateISAC(cfg,link,logicalPorts)
enabled = localRequiredLogical(cfg,"isac.enabled");
localAllowedText(cfg,"isac.researchTaxonomy", ...
    ["baseline_benchmark","agreed_starting_point", ...
    "study_item_candidate","optional_research_experiment"]);
localAllowedText(cfg,"isac.approach","communication_centric_nr_ofdm");
mode = lower(string(localAllowedText(cfg,"isac.sensingMode", ...
    ["monostatic_gnb","bistatic_gnb_ue"])));
localAllowedText(cfg,"isac.waveformAuthority","exact_runtime_pdsch_waveform");
localAllowedText(cfg,"isac.executionScope", ...
    ["first_diagnostic_transport_block","first_committed_dl_grant"]);
localAllowedText(cfg,"isac.channelModel","phased_scattering_mimo");
localAllowedText(cfg,"isac.processing.observationSource", ...
    "known_runtime_waveform_matched_filter");
localAllowedText(cfg,"isac.processing.matchedFilterImplementation", ...
    "frequency_domain_exact_reference");
localAllowedText(cfg,"isac.processing.beamformer","conventional_phase_shift");
localRequiredLogical(cfg,"isac.processing.includeElementResponse");
localAllowedText(cfg,"isac.processing.backgroundRemoval", ...
    ["none","slow_time_mean"]);
localRequiredInteger(cfg,"isac.seed",0,2^32-1);
localRequiredInteger(cfg,"isac.coherentRepetitions",2,256);
localRequiredFinite(cfg,"isac.transmitPowerDbm");
noiseFigure = localRequiredFinite(cfg,"isac.receiver.noiseFigureDb");
if noiseFigure < 0
    error("sixgr:lls:InvalidISACReceiver", ...
        "isac.receiver.noiseFigureDb must be finite and nonnegative.");
end
localRequiredPositive(cfg,"isac.receiver.referenceTemperatureK");
localRequiredFinite(cfg,"isac.receiver.gainDb");
localRequiredLogical(cfg,"isac.channel.simulateDirectPath");
localRequiredInteger(cfg,"isac.channel.warmupPulses",1,64);
localAllowedText(cfg,"isac.scene.nodePositionAuthority", ...
    ["configured_compact_geometry","coupled_runtime_topology"]);
localRequiredVector3(cfg,"isac.scene.gnbPositionM");
localRequiredVector3(cfg,"isac.scene.uePositionM");
targetCount = localRequiredInteger(cfg,"isac.scene.numberTargets",1,64);
positions = localRequiredVector(cfg,"isac.scene.targetPositionsM");
velocities = localRequiredVector(cfg,"isac.scene.targetVelocitiesMps");
realCoeff = localRequiredVector(cfg,"isac.scene.reflectionCoefficientReal");
imagCoeff = localRequiredVector(cfg,"isac.scene.reflectionCoefficientImag");
if numel(positions) ~= 3*targetCount || numel(velocities) ~= 3*targetCount
    error("sixgr:lls:InvalidISACTargetGeometry", ...
        ["ISAC flattened targetPositionsM and targetVelocitiesMps must " ...
        "each contain exactly 3*scene.numberTargets values."]);
end
if numel(realCoeff) ~= targetCount || numel(imagCoeff) ~= targetCount
    error("sixgr:lls:InvalidISACTargetReflectivity", ...
        ["ISAC reflectionCoefficientReal and reflectionCoefficientImag " ...
        "must contain one value per target."]);
end
if any(~isfinite([positions(:);velocities(:);realCoeff(:);imagCoeff(:)]))
    error("sixgr:lls:InvalidISACTargetGeometry", ...
        "ISAC target geometry, velocity, and reflection coefficients must be finite.");
end
localRequiredPositive(cfg,"isac.processing.maximumRangeM");
localRequiredInteger(cfg,"isac.processing.rangeFFTSize",64,2^22);
localRequiredInteger(cfg,"isac.processing.dopplerFFTSize",2,4096);
azMin = localRequiredFinite(cfg,"isac.processing.azimuthGrid.minimumDeg");
azMax = localRequiredFinite(cfg,"isac.processing.azimuthGrid.maximumDeg");
azStep = localRequiredPositive(cfg,"isac.processing.azimuthGrid.stepDeg");
if azMin < -180 || azMax > 180 || azMin >= azMax || ...
        mod((azMax-azMin)/azStep,1) > 1e-9
    error("sixgr:lls:InvalidISACAzimuthGrid", ...
        ["ISAC azimuth grid must satisfy -180 <= minimumDeg < maximumDeg " ...
        "<= 180 and be exactly divisible by stepDeg."]);
end
localRequiredInteger(cfg,"isac.detection.trainingCellsRange",1,256);
localAllowedText(cfg,"isac.detection.algorithm","ca_cfar_2d");
localRequiredInteger(cfg,"isac.detection.trainingCellsAngle",1,256);
localRequiredInteger(cfg,"isac.detection.guardCellsRange",0,256);
localRequiredInteger(cfg,"isac.detection.guardCellsAngle",0,256);
localRequiredOpenUnit(cfg,"isac.detection.probabilityFalseAlarm");
localRequiredInteger(cfg,"isac.detection.maximumDetections",1,256);
localRequiredInteger(cfg,"isac.detection.nonMaximumSuppressionRangeBins",0,256);
localRequiredInteger(cfg,"isac.detection.nonMaximumSuppressionAngleBins",0,256);
minimumMatched = localRequiredInteger(cfg,"isac.acceptance.minimumMatchedTargets",0,targetCount);
localRequiredPositive(cfg,"isac.acceptance.maximumRangeErrorM");
localRequiredPositive(cfg,"isac.acceptance.maximumAzimuthErrorDeg");
localRequiredLogical(cfg,"isac.output.enabled");
localRequiredLogical(cfg,"isac.output.structuredComponentFolders");
localRequiredLogical(cfg,"isac.output.saveCSV");
localRequiredLogical(cfg,"isac.output.savePNG");
localAllowedText(cfg,"isac.output.imageFormat",["png","jpeg"]);
localRequiredInteger(cfg,"isac.output.imageResolutionDPI",72,600);
localRequiredLogical(cfg,"isac.output.prohibitSVG");
if enabled
    if ~logical(cfg.isac.output.enabled) || ...
            ~logical(cfg.isac.output.saveCSV) || ...
            ~logical(cfg.isac.output.savePNG) || ...
            ~logical(cfg.isac.output.prohibitSVG)
        error("sixgr:lls:IncompleteISACOutputContract", ...
            "Enabled ISAC requires CSV plus PNG/JPEG evidence and prohibitSVG=true.");
    end
    if link ~= "PDSCH"
        error("sixgr:lls:ISACRequiresPDSCH", ...
            "The implemented communication-centric ISAC branch requires simulation.link=PDSCH.");
    end
    if ~logical(sixgr.util.structGet(cfg,"antenna.enabled",false))
        error("sixgr:lls:ISACRequiresPhysicalAntenna", ...
            "Enabled ISAC requires antenna.enabled=true and a physical CDL array.");
    end
    if logicalPorts ~= 1
        error("sixgr:lls:ISACMultiportNotQualified", ...
            ["The current matched-filter ISAC receiver is qualified for one " ...
            "logical PDSCH beam port; configure pdsch.numberAntennaPorts=1."]);
    end
    if numel(double(cfg.simulation.snrDb)) ~= 1
        error("sixgr:lls:ISACRequiresSingleOperatingPoint", ...
            "Enabled ISAC currently requires exactly one simulation.snrDb point.");
    end
    if logical(cfg.execution.parallelEnabled)
        error("sixgr:lls:ISACParallelCaptureUnsupported", ...
            "Enabled ISAC requires execution.parallelEnabled=false for one deterministic coherent capture.");
    end
    if minimumMatched < 1
        error("sixgr:lls:InvalidISACAcceptance", ...
            "Enabled ISAC requires acceptance.minimumMatchedTargets >= 1.");
    end
    if mode == "monostatic_gnb" && ...
            logical(sixgr.util.structGet(cfg,"isac.channel.simulateDirectPath",false))
        error("sixgr:lls:InvalidISACDirectPath", ...
            "Monostatic collocated sensing requires simulateDirectPath=false to avoid a zero-range self path.");
    end
end
end

function value = localRequiredVector3(cfg,path)
value = localRequiredVector(cfg,path);
if numel(value) ~= 3
    error("sixgr:lls:InvalidVector3", ...
        "%s must contain exactly three finite numeric values.",path);
end
end

function numElements = localValidateAntennaRole(cfg,role,logicalPorts,isTransmitter)
path = "antenna." + role;
localAllowedText(cfg,path + ".model","3gpp_nr_rectangular_panel");
localAllowedText(cfg,path + ".architecture","full_digital_element_domain");
size4 = localRequiredVector(cfg,path + ".size");
if numel(size4) ~= 4 || any(size4 < 1 | size4 ~= fix(size4))
    error("sixgr:lls:InvalidAntennaArraySize", ...
        "%s.size must be [rows columns panelRows panelColumns].",path);
end
spacing = localRequiredVector(cfg,path + ".spacingWavelength");
if numel(spacing) ~= 4 || any(spacing <= 0)
    error("sixgr:lls:InvalidAntennaSpacing", ...
        "%s.spacingWavelength must contain four positive values.",path);
end
orientation = localRequiredVector(cfg,path + ".orientationDeg");
if numel(orientation) ~= 3
    error("sixgr:lls:InvalidAntennaOrientation", ...
        "%s.orientationDeg must contain [bearing downtilt slant].",path);
end
polarizationAngles = localRequiredVector(cfg,path + ".polarizationAnglesDeg");
if ~ismember(numel(polarizationAngles),[1 2]) || ...
        numel(unique(polarizationAngles)) ~= numel(polarizationAngles)
    error("sixgr:lls:InvalidAntennaPolarization", ...
        "%s.polarizationAnglesDeg must contain one or two distinct slant angles.",path);
end
numElements = prod(size4) * numel(polarizationAngles);
numRFChains = localRequiredInteger(cfg,path + ".numRFChains",1,Inf);
if numRFChains ~= numElements
    error("sixgr:lls:AntennaRFChainElementMismatch", ...
        "%s full_digital_element_domain requires numRFChains=%d.",path,numElements);
end
beamAngles = double(sixgr.util.structGet(cfg,path + ".steeringAzElDeg",[]));
if isvector(beamAngles) && numel(beamAngles) == 2
    beamAngles = reshape(beamAngles,1,2);
end
if isempty(beamAngles) || ~ismatrix(beamAngles) || size(beamAngles,2) ~= 2 || ...
        any(~isfinite(beamAngles),"all") || ...
        any(beamAngles(:,1) < -180 | beamAngles(:,1) > 180) || ...
        any(beamAngles(:,2) < -90 | beamAngles(:,2) > 90)
    error("sixgr:lls:InvalidAntennaSteeringAngles", ...
        "%s.steeringAzElDeg must be an N-by-2 [azimuth elevation] matrix.",path);
end
if isTransmitter && size(beamAngles,1) ~= logicalPorts
    error("sixgr:lls:AntennaSteeringPortMismatch", ...
        "%s.steeringAzElDeg must contain one beam row per %d logical port(s).", ...
        path,logicalPorts);
end
frequencyRange = localRequiredVector(cfg,path + ".element.frequencyRangeHz");
fc = double(cfg.carrier.frequencyHz);
if numel(frequencyRange) ~= 2 || frequencyRange(1) < 0 || ...
        frequencyRange(2) <= frequencyRange(1) || ...
        fc < frequencyRange(1) || fc > frequencyRange(2)
    error("sixgr:lls:InvalidAntennaFrequencyRange", ...
        "%s.element.frequencyRangeHz must bracket carrier.frequencyHz.",path);
end
localRequiredMember(cfg,path + ".element.polarizationModel",[1 2]);
beamwidth = localRequiredVector(cfg,path + ".element.beamwidthDeg");
sidelobe = localRequiredVector(cfg,path + ".element.sidelobeLevelDb");
if numel(beamwidth) ~= 2 || any(beamwidth <= 0 | beamwidth > 180) || ...
        numel(sidelobe) ~= 2 || any(sidelobe <= 0)
    error("sixgr:lls:InvalidAntennaElementPattern", ...
        "%s element beamwidth/sidelobe values are invalid.",path);
end
maximumAttenuation = localRequiredPositive(cfg,path + ".element.maximumAttenuationDb");
if maximumAttenuation < max(sidelobe)
    error("sixgr:lls:InvalidAntennaElementPattern", ...
        "%s.element.maximumAttenuationDb must not be below its sidelobe levels.",path);
end
localRequiredFinite(cfg,path + ".element.maximumGainDbi");
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
