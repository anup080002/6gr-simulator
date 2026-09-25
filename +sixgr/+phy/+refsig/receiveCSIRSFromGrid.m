function rx=receiveCSIRSFromGrid(carrier,cfg,received,opt)
% CSI-RS receive processing independently callable without a PDSCH grant.
% Factored from PDSCH_Rx: the same pilot estimation, physical reference
% measurements, resource selection and immutable CSI measurement state.
% Inputs are a synchronized received grid and its receiver/OFDM metadata.
% No data decoder, CRC decision, HARQ state or scheduler decision is used.
arguments
    carrier (1,1) nrCarrierConfig
    cfg (1,1) struct
    received (1,1) struct
    opt (1,1) struct = struct()
end
assert(isfield(received,'OFDMGrid') && isfield(received,'OFDMInfo'), ...
    'sixgr:refsig:CSIReceivedGridRequired','Retain the synchronized grid and OFDM metadata.');
validateattributes(received.OFDMGrid,{'single','double'},{'nonempty','finite'});
assert(size(received.OFDMGrid,1)==12*carrier.NSizeGrid && ...
    size(received.OFDMGrid,2)==carrier.SymbolsPerSlot, ...
    'sixgr:refsig:CSIReceivedGridDimensions','Expected one complete received carrier slot.');
defaults=struct('CSIRSIndices',[],'CSIRSSymbols',[],'CSIRSInfo',struct(), ...
    'CSIRSConfig',[],'CSIRSScheduled',[],'CSIRSTransmitted',[], ...
    'PhysicalMeasurementReferencePlane',"",'PhysicalMeasurementSource',"", ...
    'ReceivedExecutionEvidence',struct());
names=fieldnames(defaults);
for k=1:numel(names)
    if ~isfield(opt,names{k}), opt.(names{k})=defaults.(names{k}); end
end
rx=struct();
csirsReceiverPipelineTic = tic;
[csirsInd, csirsSym, csirsInfo, csirsObservation, csirsConfig] = ...
    localObserveCSIRSRuntimeResource( ...
    carrier, cfg, received.OFDMGrid, opt, received.OFDMInfo);
rx.CSIRSIndices = csirsInd;
rx.CSIRSSymbols = csirsSym;
rx.CSIRSInfo = csirsInfo;
rx.CSIRS = csirsConfig;
csirsChannelEstimationTic = tic;
[csirsHest, csirsNoiseVar, csirsEstimateInfo] = ...
    localEstimateCSIRSChannelForPMI( ...
    carrier, received.OFDMGrid, csirsInd, csirsSym, csirsInfo, ...
    cfg, opt.ReceivedExecutionEvidence);
csirsChannelEstimationLatency_ms = 1e3 * toc(csirsChannelEstimationTic);
rx.CSIRSChannelEstimate = csirsHest;
rx.CSIRSNoiseVar = csirsNoiseVar;
rx.CSIRSChannelEstimation = csirsEstimateInfo;
rx.SelectedCSIRS = localSelectedCSIRSConfig( ...
    csirsConfig, csirsInfo, csirsEstimateInfo);
rx.CSIChannelEstimateForPMI = csirsHest;
rx.CSIChannelNoiseVarForPMI = csirsNoiseVar;
rx.CSIChannelEstimateSource = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "Source", "not_observed"));
if strlength(rx.CSIChannelEstimateSource) == 0
    rx.CSIChannelEstimateSource = "not_observed";
end
[csiMeasurementState, csiMeasurementInfo] = ...
    localBuildCSIMeasurementState(cfg, carrier, csirsHest, ...
    csirsNoiseVar, csirsEstimateInfo, received);
rx.CSIMeasurementState = csiMeasurementState;
rx.CSIMeasurementStateInfo = csiMeasurementInfo;
if ~isempty(csiMeasurementState)
    % The strict CSI facade verifies an immutable digest twice.  Pass the
    % exact same measured wideband matrix at both boundaries; never
    % reconstruct, resize, or substitute a configured channel oracle.
    rx.CSIChannelEstimateForPMI = csiMeasurementState.ChannelEstimate;
    rx.CSIChannelNoiseVarForPMI = csiMeasurementState.NoiseVariance;
end
csirsObservation.ChannelEstimationAttempted = logical(csirsObservation.Observed);
csirsObservation.ChannelEstimateAvailable = logical(sixgr.util.structGet( ...
    csirsEstimateInfo, "Available", false));
csirsObservation.ChannelEstimateSource = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "Source", ""));
csirsObservation.ChannelEstimator = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "ChannelEstimator", ""));
csirsObservation.ChannelInterpolationMethod = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "InterpolationMethod", ""));
csirsObservation.ChannelEstimateConvention = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "EffectiveChannelConvention", ""));
csirsObservation.ChannelEstimateNoiseVariance = double(csirsNoiseVar);
csirsObservation.ChannelEstimateCDMType = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "CDMType", ""));
csirsObservation.ChannelEstimateCDMLengths = localNumericVectorToken( ...
    sixgr.util.structGet(csirsEstimateInfo, "CDMLengths", []));
csirsObservation.PilotRECount = double(sixgr.util.structGet( ...
    csirsEstimateInfo, "PilotRECount", NaN));
csirsObservation.PilotResidualPower = double(sixgr.util.structGet( ...
    csirsEstimateInfo, "PilotResidualPower", NaN));
csirsObservation.PilotResidualNMSE_dB = double(sixgr.util.structGet( ...
    csirsEstimateInfo, "PilotResidualNMSE_dB", NaN));
[csirsObservation.ChannelEstimateDiagnosticSINR_dB, ...
    csirsObservation.ChannelEstimateDiagnosticSINRSource, ...
    csirsObservation.ChannelEstimateDiagnosticSINRStatus] = ...
    localCSIRSReferenceSINR(csirsHest, csirsNoiseVar, csirsEstimateInfo);
csirsObservation.HestDimensions = localSizeToken(csirsHest);
csirsObservation.HestRxPorts = localArrayDimension(csirsHest, 3);
csirsObservation.HestTxPorts = localArrayDimension(csirsHest, 4);
csirsObservation.SINRMeasurementDomain = "csi_rs_port3000_reference_re_received_plane";
if ~isfinite(csirsObservation.MeasurementRSRP_dBm)
    csirsObservation.PowerReferencePlane = ...
        "normalized_ofdm_resource_grid_after_receiver_synchronization";
end
csirsObservation.CSIMeasurementStateAvailable = ~isempty(csiMeasurementState);
csirsObservation.CSIMeasurementStatus = string(sixgr.util.structGet( ...
    csiMeasurementInfo, "Status", "not_required"));
csirsObservation.CSIMeasurementID = string(sixgr.util.structGet( ...
    csiMeasurementInfo, "MeasurementID", ""));
csirsObservation.CSIMeasurementDigest = string(sixgr.util.structGet( ...
    csiMeasurementInfo, "Digest", ""));
csirsObservation.CSIMeasurementProvenance = string(sixgr.util.structGet( ...
    csiMeasurementInfo, "Provenance", ""));
csirsObservation.CSIMeasurementSlot = double(sixgr.util.structGet( ...
    csiMeasurementInfo, "Slot", NaN));
csirsObservation.CSIMeasurementNoiseVariance = double(sixgr.util.structGet( ...
    csiMeasurementInfo, "NoiseVariance", NaN));
csirsObservation.ResourceID = double(sixgr.util.structGet( ...
    csirsEstimateInfo, "SelectedResourceID", csirsObservation.ResourceID));
csirsObservation.NumConfiguredResources = double(sixgr.util.structGet( ...
    csirsEstimateInfo, "NumConfiguredResources", 1));
csirsObservation.NumMeasuredResources = double(sixgr.util.structGet( ...
    csirsEstimateInfo, "NumMeasuredResources", ...
    double(logical(csirsObservation.ChannelEstimateAvailable))));
csirsObservation.ResourceObjectiveValues = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "ResourceObjectiveToken", ""));
csirsObservation.CRISelectionSource = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "SelectionSource", ""));
csirsObservation = localSelectCSIRSRSPResource( ...
    csirsObservation, csirsEstimateInfo);
csirsObservation = sixgr.phy.refsig.normalizeCSIRSPowerReference( ...
    csirsObservation, cfg);
if csirsObservation.ChannelEstimateAvailable
    csirsObservation.Consumed = true;
    csirsObservation.Consumer = "dl_csi_ri_pmi_cri_measurement";
end
csirsObservation.ChannelEstimationLatency_ms = ...
    double(csirsChannelEstimationLatency_ms);
csirsObservation.ReceiverPipelineLatency_ms = ...
    1e3 * toc(csirsReceiverPipelineTic);
csirsObservation.ReceiverStageLatencySource = ...
    "matlab_tic_toc_csirs_runtime_observation_and_estimation";
rx.CSIRSObservation = csirsObservation;
end

function [csirsInd, csirsSym, csirsInfo, obs, measurementConfig] = localObserveCSIRSRuntimeResource(carrier, cfg, rxGrid, opt, ofdmInfo)
csirsInd = opt.CSIRSIndices;
csirsSym = opt.CSIRSSymbols;
csirsInfo = opt.CSIRSInfo;
measurementConfig = opt.CSIRSConfig;
obs = localEmptyCSIRSObservation(cfg);
if isempty(csirsInfo) || ~isstruct(csirsInfo)
    csirsInfo = struct("Channel", "CSI-RS", "Enabled", false);
end
if ~isempty(opt.CSIRSScheduled) && ~logical(opt.CSIRSScheduled)
    if (~isempty(opt.CSIRSTransmitted) && logical(opt.CSIRSTransmitted)) || ...
            ~isempty(csirsInd) || ~isempty(csirsSym)
        error("sixgr:pdsch:CSIRSOccasionContractMismatch", ...
            char("CSI-RS cannot be transmitted or carry mapped resources when " + ...
             "the Tx runtime event declares a non-occasion."));
    end
    obs.Scheduled = false;
    obs.RuntimeMaterializationStatus = "configured_not_scheduled_this_slot";
    obs.Blocker = "outside_yaml_csirs_period_offset";
    obs.UpdateOutcome = "not_scheduled";
    return;
end
if ~isempty(opt.CSIRSTransmitted) && ~logical(opt.CSIRSTransmitted)
    obs.Scheduled = isempty(opt.CSIRSScheduled) || logical(opt.CSIRSScheduled);
    obs.RuntimeMaterializationStatus = "not_transmitted";
    obs.Blocker = "tx_runtime_csirs_event_not_transmitted";
    obs.UpdateOutcome = "not_observed";
    return;
end
if isempty(csirsInd) || isempty(csirsSym)
    if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
        obs.RuntimeMaterializationStatus = "disabled";
        obs.Blocker = "phy.csirs.enable_false";
        obs.UpdateOutcome = "not_observed";
        return;
    end
    try
        [csirsInd, csirsSym, csirsInfo, measurementConfig] = ...
            sixgr.phy.refsig.csirs(carrier, cfg);
    catch ME
        obs.RuntimeMaterializationStatus = "blocked_generation_failed";
        obs.Blocker = string(ME.identifier) + ":" + string(ME.message);
        obs.UpdateOutcome = "not_observed";
        return;
    end
end
if isempty(csirsInd) || isempty(csirsSym)
    obs.RuntimeMaterializationStatus = "blocked_empty_resource";
    obs.Blocker = "empty_csirs_indices_or_symbols";
    obs.UpdateOutcome = "not_observed";
    return;
end
obs.Scheduled = true;
obs.NRE = double(numel(csirsSym));
obs.NumPorts = double(sixgr.util.structGet(csirsInfo, "NumCSIRSPorts", NaN));
obs.RowNumber = double(sixgr.util.structGet(csirsInfo, "RowNumber", NaN));
obs.ResourceExtractionAttempted = true;
try
    rxRef = nrExtractResources(csirsInd, rxGrid);
catch
    try
        rxRef = rxGrid(double(csirsInd(:)));
    catch
        rxRef = [];
    end
end
if isempty(rxRef)
    obs.RuntimeMaterializationStatus = "blocked_extract_failed";
    obs.Blocker = "csirs_reference_re_extraction_failed";
    obs.UpdateOutcome = "not_observed";
    return;
end
obs.ResourceExtractionAvailable = true;
powerLin = mean(abs(rxRef(:)).^2, "omitnan");
obs.Observed = isfinite(powerLin) && powerLin > 0;
obs.MeasurementRSRP_dB = 10 * log10(max(double(powerLin), eps));
obs.MeasurementRelativeRSRP_dB = obs.MeasurementRSRP_dB;
obs.MeasurementRelativeSource = ...
    "received_csirs_reference_signal_power_post_front_end_normalized_grid";
physicalGrid = [];
physicalOFDMInfo = struct();
physicalGridStatus = "unavailable_missing_pre_front_end_measurement_waveform";
if isfield(opt, "PhysicalMeasurementGrid")
    physicalGrid = opt.PhysicalMeasurementGrid;
end
if isfield(opt, "PhysicalMeasurementOFDMInfo")
    physicalOFDMInfo = opt.PhysicalMeasurementOFDMInfo;
end
if isfield(opt, "PhysicalMeasurementGridStatus")
    physicalGridStatus = string(opt.PhysicalMeasurementGridStatus);
end
obs = localMeasurePhysicalCSIRSRSP( ...
    obs, carrier, cfg, rxGrid, physicalGrid, csirsInfo, ...
    measurementConfig, ofdmInfo, physicalOFDMInfo, physicalGridStatus, ...
    string(opt.PhysicalMeasurementReferencePlane), ...
    string(opt.PhysicalMeasurementSource),opt.ReceivedExecutionEvidence);
obs.RuntimeMaterializationStatus = "runtime_observed";
obs.UpdateOutcome = "observed_after_ofdm_demodulation";
obs.RuntimeEvidenceSource = "sixgr.phy.refsig.receiveCSIRSFromGrid";
end

function obs = localMeasurePhysicalCSIRSRSP(obs, carrier, cfg, rxGrid, ...
        physicalGrid, csirsInfo, defaultConfig, ofdmInfo, ...
        physicalOFDMInfo, physicalGridStatus, physicalReferencePlane, ...
        physicalSource,execution)
% Convert the Toolbox OFDM grid back to physical sqrt(W) before calling the
% TS 38.215 CSI-RS measurement implementation.  nrOFDMDemodulate uses an
% unnormalised FFT, so a grid bin is Nfft times the time-domain sample
% amplitude.  The production PowerContext defines abs(sample)^2 in mW.
powerContext = sixgr.util.structGet(cfg, "lls6g.runtimePowerContext", struct());
amplitudeUnit = string(sixgr.util.structGet( ...
    powerContext, "WaveformAmplitudeUnit", ""));
obs.PhysicalMeasurementStatus = "unavailable_missing_sqrt_mw_power_context";
obs.PhysicalMeasurementStandard = "3GPP_TS_38.215_via_nrCSIRSMeasurements";
if ~strcmpi(strtrim(amplitudeUnit), "sqrt_mW")
    return;
end
receiverMeasurement = sixgr.util.structGet( ...
    cfg, "lls6g.receiverMeasurement", struct());
frontEndApplied = logical(sixgr.util.structGet( ...
    receiverMeasurement, "CompositeReceiverFrontEndApplied", false));
if isempty(physicalGrid)
    if frontEndApplied
        obs.PhysicalMeasurementStatus = ...
            "unavailable_post_front_end_grid_without_antenna_plane_waveform";
        obs.MeasurementErrors = char(string(physicalGridStatus));
        return;
    end
    % Direct PHY callers without a composite receiver front end already
    % provide an antenna-plane grid.  This is the only permitted fallback;
    % a post-AGC/ADC grid is never reverse-labeled as physical dBm.
    physicalGrid = rxGrid;
    physicalOFDMInfo = ofdmInfo;
    physicalGridStatus = "available_direct_receiver_grid_no_composite_front_end";
    physicalReferencePlane = "receiver_antenna_connector_no_composite_front_end";
    physicalSource = "receiveCSIRSFromGrid_direct_receiver_grid";
end
if ~startsWith(string(physicalGridStatus), "available")
    obs.PhysicalMeasurementStatus = string(physicalGridStatus);
    return;
end
nfft = double(sixgr.util.structGet(physicalOFDMInfo, "Nfft", NaN));
if ~(isscalar(nfft) && isfinite(nfft) && nfft >= 1 && nfft == round(nfft))
    try
        derivedOFDM = nrOFDMInfo(carrier);
        nfft = double(derivedOFDM.Nfft);
    catch
        obs.PhysicalMeasurementStatus = "unavailable_missing_ofdm_fft_size";
        return;
    end
end

configs = cell(0,1);
resourceIDs = zeros(0,1);
resources = sixgr.util.structGet(csirsInfo, "Resources", []);
if ~isempty(resources)
    for ordinal = 1:numel(resources)
        candidate = sixgr.util.structGet(resources(ordinal), "Configuration", []);
        if isa(candidate, "nrCSIRSConfig")
            configs{end+1,1} = candidate; %#ok<AGROW>
            resourceIDs(end+1,1) = double(sixgr.util.structGet( ...
                resources(ordinal), "ResourceID", ordinal - 1)); %#ok<AGROW>
        end
    end
elseif isa(defaultConfig, "nrCSIRSConfig")
    configs = {defaultConfig};
    resourceIDs = double(sixgr.util.structGet(csirsInfo, "ResourceID", ...
        sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0)));
end
if isempty(configs)
    obs.PhysicalMeasurementStatus = "unavailable_missing_runtime_csirs_configuration";
    return;
end

scale = nfft * sqrt(1000); % sqrt(mW) grid -> sqrt(W) resource grid
physicalGrid = physicalGrid ./ cast(scale, "like", physicalGrid);
resourceAverage = nan(numel(configs),1);
perAntenna = cell(numel(configs),1);
physicalResources = cell(numel(configs),1);
measurementErrors = strings(numel(configs),1);
for ordinal = 1:numel(configs)
    try
        measured = sixgr.phy.refsig.measureCSIRSPhysicalResource( ...
            carrier,configs{ordinal},physicalGrid,cfg,execution);
        measured.ResourceID=resourceIDs(ordinal);
        physicalResources{ordinal}=measured;
        branchRSRP = measured.RSRPPerAntenna_dBm;
        perAntenna{ordinal} = branchRSRP;
        if ~measured.Available
            measurementErrors(ordinal) = "unavailable_physical_resource_measurement";
            continue;
        end
        % TS 38.215 receiver-diversity reporting requires the reported
        % CSI-RSRP to be no lower than the CSI-RSRP of any individual
        % receive branch.  Preserve every branch value for audit and use
        % the strongest measured branch for the UE-level report; averaging
        % branches can violate that normative lower bound.
        resourceAverage(ordinal) = max(branchRSRP);
    catch ME
        measurementErrors(ordinal) = string(ME.identifier);
    end
end
obs.MeasurementFFTSize = nfft;
obs.MeasurementGridScaleToSqrtW = scale;
obs.MeasurementReceiverGainCorrection_dB = 0;
obs.MeasurementReceiverGainCorrectionSource = ...
    "not_required_exact_pre_front_end_measurement_waveform";
obs.PhysicalMeasurementWaveformStatus = string(physicalGridStatus);
obs.PhysicalMeasurementWaveformSource = string(physicalSource);
obs.MeasurementResourceIDs = localNumericVectorToken(resourceIDs);
obs.MeasurementRSRPPerResource_dBm = localNumericVectorToken(resourceAverage);
obs.MeasurementRSRPPerResourceValues_dBm = resourceAverage;
obs.MeasurementRSRPPerAntennaByResource_dBm = perAntenna;
obs.MeasurementPhysicalResources = physicalResources;
obs.MeasurementPhysicalResourcesJSON = string(jsonencode(sixgr.util.jsonSafeValue(physicalResources)));
obs.MeasurementErrors = strjoin(measurementErrors(strlength(measurementErrors) > 0), "|");
valid = find(isfinite(resourceAverage), 1, "first");
if isempty(valid)
    obs.PhysicalMeasurementStatus = "unavailable_nr_csirs_measurement_failed";
    return;
end
obs.MeasurementSelectedResourceOrdinal = double(valid);
obs.MeasurementRSRP_dBm = resourceAverage(valid);
obs.MeasurementRSRPPerReceiveAntenna_dBm = ...
    localNumericVectorToken(perAntenna{valid});
obs.MeasurementAntennaAggregation = ...
    "maximum_per_receive_antenna_rsrp_ts_38_215_diversity_rule";
obs.MeasurementSource = ...
    "nrCSIRSMeasurements_runtime_pre_front_end_antenna_plane_grid";
obs.PowerReferencePlane = string(physicalReferencePlane);
obs.PhysicalMeasurementStatus = "available";
obs = localSelectCSIRSRSPResource(obs,struct('SelectedResourceOrdinal',valid));
end

function obs = localSelectCSIRSRSPResource(obs, estimateInfo)
% Re-selection must not retain the first resource's SINR when the selected
% CRI has no measurement. The initial strongest/first-resource probe is not
% authority for a different selected CSI resource.
obs.ReferenceMeasuredSINR_dB=NaN;
obs.ReferenceMeasuredSINRSource="";
obs.ReferenceMeasuredSINRStatus="unavailable_selected_resource_measurement";
obs.ReferenceSINRMeasurementJSON="";
values = sixgr.util.structGet(obs, "MeasurementRSRPPerResourceValues_dBm", []);
perAntenna = sixgr.util.structGet(obs, ...
    "MeasurementRSRPPerAntennaByResource_dBm", {});
ordinal = double(sixgr.util.structGet(estimateInfo, ...
    "SelectedResourceOrdinal", sixgr.util.structGet(obs, ...
    "MeasurementSelectedResourceOrdinal", 1)));
if ~(isscalar(ordinal) && isfinite(ordinal) && ordinal >= 1 && ...
        ordinal == round(ordinal) && ordinal <= numel(values))
    return;
end
if isfinite(values(ordinal))
    obs.MeasurementSelectedResourceOrdinal = ordinal;
    obs.MeasurementRSRP_dBm = double(values(ordinal));
    if ordinal <= numel(perAntenna) && ~isempty(perAntenna{ordinal})
        obs.MeasurementRSRPPerReceiveAntenna_dBm = ...
            localNumericVectorToken(perAntenna{ordinal});
    end
    resources=sixgr.util.structGet(obs,"MeasurementPhysicalResources",{});
    if ordinal<=numel(resources) && ~isempty(resources{ordinal})
        measured=resources{ordinal};
        if isfield(measured,'SINR')
            % Preserve signed low-SNR evidence even when no positive dB
            % estimate can be resolved; do not discard the measurement.
            obs.ReferenceSINRMeasurementJSON=string(jsonencode(sixgr.util.jsonSafeValue(measured.SINR)));
            obs.ReferenceMeasuredSINRSource=measured.SINR.Source;
            obs.ReferenceMeasuredSINRStatus=measured.SINR.Status;
        end
        if isfield(measured,'SINR') && measured.SINR.Available
            obs.ReferenceMeasuredSINR_dB=measured.SINR.CSI_SINR_dB;
            obs.ReferenceMeasuredSINRSource=measured.SINR.Source;
            obs.ReferenceMeasuredSINRStatus="available";
            obs.ReferenceSINRMeasurementJSON=string(jsonencode(sixgr.util.jsonSafeValue(measured.SINR)));
        end
        selected=sixgr.phy.refsig.selectCSIRSBranchMeasurements(measured);
        obs.MeasurementReceiveAntennaIndex1Based=double(selected.RSRPReceiveBranch1Based);
        obs.MeasurementRSSI_dBm=selected.RSSI_dBm;
        obs.MeasurementRSRQ_dB=selected.RSRQ_dB;
        obs.MeasurementRSRQReceiveAntennaIndex1Based=double(selected.RSRQReceiveBranch1Based);
        obs.MeasurementRSRQNumeratorRSRP_dBm=selected.RSRQNumeratorRSRP_dBm;
        obs.MeasurementRSRQDenominatorRSSI_dBm=selected.RSRQDenominatorRSSI_dBm;
        obs.MeasurementRSRQAntennaAggregation=selected.RSRQSelection;
        obs.MeasurementRSSIPerReceiveAntenna_dBm=localNumericVectorToken(measured.RSSIPerAntenna_dBm);
        obs.MeasurementRSRQPerReceiveAntenna_dB=localNumericVectorToken(measured.RSRQPerAntenna_dB);
        obs.MeasurementNumRB=measured.NumRB;
        obs.MeasurementFirstPRB0Based=measured.FirstPRB0Based;
        obs.MeasurementSymbolIndices0Based=localNumericVectorToken(measured.SymbolIndices0Based);
        obs.MeasurementSubcarrierSpacing_kHz=measured.SubcarrierSpacing_kHz;
        obs.MeasurementBandwidth_Hz=measured.Bandwidth_Hz;
        obs.MeasurementRSSIAntennaAggregation="same_branch_as_reported_rsrp";
        obs.MeasurementRSSIStatus="available";
    end
else
    % Never retain the first valid resource's power under a different CRI.
    obs.MeasurementSelectedResourceOrdinal=ordinal;
    obs.MeasurementRSRP_dBm=NaN;
    obs.MeasurementRSRPPerReceiveAntenna_dBm="";
    obs.MeasurementRSSI_dBm=NaN;
    obs.MeasurementRSRQ_dB=NaN;
    obs.MeasurementRSRQReceiveAntennaIndex1Based=NaN;
    obs.MeasurementRSRQNumeratorRSRP_dBm=NaN;
    obs.MeasurementRSRQDenominatorRSSI_dBm=NaN;
    obs.MeasurementRSRQAntennaAggregation="";
    obs.MeasurementRSSIPerReceiveAntenna_dBm="";
    obs.MeasurementRSRQPerReceiveAntenna_dB="";
    obs.MeasurementReceiveAntennaIndex1Based=NaN;
    obs.MeasurementNumRB=NaN;
    obs.MeasurementFirstPRB0Based=NaN;
    obs.MeasurementSymbolIndices0Based="";
    obs.MeasurementSubcarrierSpacing_kHz=NaN;
    obs.MeasurementBandwidth_Hz=NaN;
    obs.MeasurementRSSIAntennaAggregation="";
    obs.MeasurementRSSIStatus="unavailable_selected_resource_not_measured";
    obs.PhysicalMeasurementStatus="unavailable_selected_resource_not_measured";
end
end


function [Hest, nVar, estInfo] = localEstimateCSIRSChannelForPMI(carrier, rxGrid, csirsInd, csirsSym, csirsInfo, cfg, execution)
Hest = [];
nVar = NaN;
resources = sixgr.util.structGet(csirsInfo, "Resources", []);
if numel(resources) > 1
    [Hest, nVar, estInfo] = localEstimateCSIRSResourceSetForPMI( ...
        carrier, rxGrid, resources, cfg, execution);
    return;
end
numCSIRSPorts = double(sixgr.util.structGet(csirsInfo, "NumCSIRSPorts", NaN));
expectedTxPorts = max([numCSIRSPorts(isfinite(numCSIRSPorts)), 1]);
cdmType = string(sixgr.util.structGet(csirsInfo, "CDMType", ""));
cdmLengths = double(sixgr.util.structGet(csirsInfo, "CDMLengths", []));
estInfo = struct( ...
    "Available", false, ...
    "Status", "unavailable", ...
    "Source", "", ...
    "Reason", "", ...
    "ExpectedTxPorts", double(expectedTxPorts), ...
    "NumCSIRSPorts", double(numCSIRSPorts), ...
    "CDMType", cdmType, ...
    "CDMLengths", double(cdmLengths));
if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
    estInfo.Status = "disabled";
    estInfo.Reason = "phy.csirs.enable_false";
    return;
end
if isempty(rxGrid) || isempty(csirsInd) || isempty(csirsSym)
    estInfo.Reason = "missing_csirs_reference_evidence";
    return;
end
if isempty(cdmLengths)
    % An enabled CSI-RS estimate must use the exact CDM spreading lengths
    % resolved by the transmitted resource.  Do not infer a generic value
    % in the receiver or silently turn a malformed enabled resource into a
    % disabled observation.
    cdmLengths = sixgr.phy.refsig.csirsCDMLengths(cdmType);
    estInfo.CDMLengths = double(cdmLengths);
end
try
    [Hest, nVar, chInfo] = sixgr.phy.refsig.estimateCSIRSResourceChannel( ...
        carrier,rxGrid,csirsInd,csirsSym,cfg,expectedTxPorts,cdmLengths,execution);
    estInfo.ReferencePowerMeasurement=sixgr.util.structGet(chInfo,'ReferencePowerMeasurement',struct());
    estInfo.CoefficientErrorVarianceEstimatePerPortReceiveBranch=sixgr.util.structGet( ...
        chInfo,'CoefficientErrorVarianceEstimatePerPortReceiveBranch',[]);
    im=sixgr.phy.refsig.measureCSIIM(carrier,cfg,rxGrid);
    if im.Plan.Enabled
        assert(im.Available,'sixgr:phy:csiim:MissingObservation', ...
            'Enabled CSI-IM must be measured on this CSI-RS occasion.');
        K=size(rxGrid,1); L=size(rxGrid,2);
        assert(isempty(intersect(unique(mod(double(csirsInd(:))-1,K*L)+1), ...
            im.Plan.PhysicalIndices1Based)), ...
            'sixgr:phy:csiim:ReferenceCollision','CSI-IM overlaps the desired CSI-RS resource.');
        estInfo.ChannelEstimatorDisturbance=double(nVar);
        nVar=im.MeanPower;
        estInfo.InterferenceMeasurement=im;
    end
    estInfo.Available = ~isempty(Hest);
    if estInfo.Available
        estInfo.Status = "OK";
        estInfo.Source = "csirs_resource_selective_channel_estimate";
        estInfo.Reason = "";
        estInfo.HestSize = size(Hest);
        estInfo.NoiseVar = double(nVar);
        estInfo.ChannelEstimator = string(sixgr.util.structGet(chInfo, "EngineUsed", ""));
        estInfo.InferredReferencePortCount = double(sixgr.util.structGet(chInfo, "InferredReferencePortCount", NaN));
        estInfo.NumRxAnt = double(sixgr.util.structGet(chInfo, "NumRxAnt", size(rxGrid, 3)));
        estInfo.InterpolationMethod = string(sixgr.util.structGet(chInfo, "InterpolationMethod", ""));
        estInfo.EffectiveChannelConvention = string(sixgr.util.structGet(chInfo, "EffectiveChannelConvention", ""));
        estInfo.PilotRECount = double(sixgr.util.structGet(chInfo, "PilotRECount", NaN));
        estInfo.PilotResidualPower = double(sixgr.util.structGet(chInfo, "PilotResidualPower", NaN));
        estInfo.PilotResidualNMSE_dB = double(sixgr.util.structGet(chInfo, "PilotResidualNMSE_dB", NaN));
        estInfo.PilotMask = sixgr.util.structGet(chInfo, "PilotMask", []);
        estInfo.CDMLengths = double(sixgr.util.structGet( ...
            chInfo, "CDMLengths", cdmLengths));
    else
        estInfo.Status = "NOT_AVAILABLE";
        estInfo.Reason = "empty_csirs_channel_estimate";
    end
catch ME
    Hest = [];
    nVar = NaN;
    estInfo.Status = "NOT_AVAILABLE";
    estInfo.Source = "csirs_resource_selective_channel_estimate";
    estInfo.Reason = "csirs_channel_estimate_failed:" + string(ME.identifier);
end
end

function [selectedHest, selectedNVar, setInfo] = ...
        localEstimateCSIRSResourceSetForPMI(carrier, rxGrid, resources, cfg, execution)
nResources = numel(resources);
measurements = repmat(localEmptyCSIRSResourceMeasurement(), nResources, 1);
objectives = -inf(nResources, 1);
for ordinal = 1:nResources
    resource = resources(ordinal);
    resourceInfo = struct( ...
        "NumCSIRSPorts", double(resource.NumPorts), ...
        "ResourceID", double(resource.ResourceID), ...
        "CDMType", string(resource.CDMType), ...
        "CDMLengths", double(resource.CDMLengths));
    [Hest, nVar, info] = localEstimateCSIRSChannelForPMI( ...
        carrier, rxGrid, resource.Indices, resource.Symbols, resourceInfo, ...
        cfg, execution);
    measurements(ordinal).ResourceID = double(resource.ResourceID);
    measurements(ordinal).Hest = Hest;
    measurements(ordinal).NoiseVariance = double(nVar);
    measurements(ordinal).EstimationInfo = info;
    measurements(ordinal).Available = logical(sixgr.util.structGet(info, "Available", false));
    if measurements(ordinal).Available
        Hwb = localCSIRSWidebandChannelMatrix(Hest, info);
        objectives(ordinal) = localMeasuredCSIRSReceiverObjective(Hwb, nVar);
        measurements(ordinal).WidebandChannel = Hwb;
        measurements(ordinal).ReceiverObjective = objectives(ordinal);
    end
end
available = [measurements.Available].';
if ~any(available)
    selectedHest = [];
    selectedNVar = NaN;
    setInfo = struct("Available",false,"Status","NOT_AVAILABLE", ...
        "Source","csirs_resource_set_receiver_measurements", ...
        "Reason","no_csirs_resource_channel_estimate_available", ...
        "NumConfiguredResources",nResources,"NumMeasuredResources",0, ...
        "SelectedResourceID",NaN,"SelectionSource","not_available", ...
        "ResourceObjectiveToken",localNumericVectorToken(objectives), ...
        "ResourceMeasurements",measurements);
    return;
end
objectives(~available) = -inf;
[~, selectedOrdinal] = max(objectives);
selected = measurements(selectedOrdinal);
selectedHest = selected.Hest;
selectedNVar = selected.NoiseVariance;
setInfo = selected.EstimationInfo;
setInfo.Available = true;
setInfo.Status = "OK";
setInfo.Source = "csirs_resource_set_receiver_measurements";
setInfo.Reason = "";
setInfo.NumConfiguredResources = nResources;
setInfo.NumMeasuredResources = sum(available);
setInfo.SelectedResourceID = selected.ResourceID;
setInfo.SelectedResourceOrdinal = selectedOrdinal;
setInfo.SelectedCRI = selectedOrdinal - 1;
setInfo.SelectedReceiverObjective = objectives(selectedOrdinal);
setInfo.SelectionSource = "measured_csirs_resource_receiver_capacity_objective";
setInfo.ResourceObjectiveToken = localNumericVectorToken(objectives);
setInfo.ResourceMeasurements = measurements;
end

function objective = localMeasuredCSIRSReceiverObjective(H, nVar)
objective = -inf;
if isempty(H) || ndims(H) > 3 || any(~isfinite(real(H(:))) | ~isfinite(imag(H(:))))
    return;
end

nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
    return;
end
nStreams = max(1, size(H,2));
if ismatrix(H)
    H = reshape(H,size(H,1),size(H,2),1);
end
snapshotObjective = nan(size(H,3),1);
for snapshot = 1:size(H,3)
    Hs = H(:,:,snapshot);
    R = eye(size(Hs,1)) + (Hs * Hs') ./ max(nStreams * nVar, realmin);
    eigenvalues = real(eig((R + R') ./ 2));
    if all(isfinite(eigenvalues)) && all(eigenvalues > 0)
        snapshotObjective(snapshot) = sum(log2(eigenvalues));
    end
end
if any(isfinite(snapshotObjective))
    objective = mean(snapshotObjective,"omitnan");
end
end

function [sinrDb, source, status] = localCSIRSReferenceSINR(Hest, nVar, estimateInfo)
% Retain the legacy channel-power diagnostic, NOT TS 38.215 CSI-SINR.
% This is distinct from port-3000 reference-RE measurement and from
% PDSCH post-equalization SINR: signal power is the average received power
% of unit-energy orthogonal CSI-RS ports and the denominator is the noise
% plus interference variance measured by the CSI-RS estimator.
sinrDb = NaN;
source = "";
status = "unavailable";
if ~logical(sixgr.util.structGet(estimateInfo, "Available", false)) || ...
        isempty(Hest)
    status = "unavailable_missing_csirs_channel_estimate";
    return;
end
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar > 0)
    status = "unavailable_invalid_csirs_noise_variance";
    return;
end
if any(~isfinite(real(Hest(:))) | ~isfinite(imag(Hest(:))))
    status = "unavailable_nonfinite_csirs_channel_estimate";
    return;
end
Hwb = localCSIRSWidebandChannelMatrix(Hest, estimateInfo);
if isempty(Hwb)
    status = "unavailable_empty_csirs_wideband_channel";
    return;
end
if ismatrix(Hwb)
    Hwb = reshape(Hwb, size(Hwb,1), size(Hwb,2), 1);
end
nPorts = max(1, size(Hwb,2));
signalPowerPerRxSnapshot = squeeze(sum(abs(Hwb).^2, 2) ./ nPorts);
signalPower = mean(double(signalPowerPerRxSnapshot(:)), "omitnan");
if ~(isscalar(signalPower) && isfinite(signalPower) && signalPower > 0)
    status = "unavailable_invalid_csirs_signal_power";
    return;
end
sinrDb = 10 .* log10(signalPower ./ nVar);
source = "csirs_resource_selective_hest_over_measured_noise_interference_variance";
status = "available";
end

function value = localEmptyCSIRSResourceMeasurement()
value = struct("ResourceID",NaN,"Available",false,"Hest",[], ...
    "WidebandChannel",[],"NoiseVariance",NaN,"ReceiverObjective",-inf, ...
    "EstimationInfo",struct());
end

function token = localNumericVectorToken(values)
values = double(values(:).');
pieces = strings(size(values));
for ordinal = 1:numel(values)
    if isfinite(values(ordinal))
        pieces(ordinal) = compose("%.12g", values(ordinal));
    elseif values(ordinal) > 0
        pieces(ordinal) = "Inf";
    else
        pieces(ordinal) = "-Inf";
    end
end
token = "[" + strjoin(pieces, ",") + "]";
end

function obs = localEmptyCSIRSObservation(cfg)
obs = struct();
obs.SignalFamily = "CSI-RS";
obs.SignalDirection = "DL";
obs.ResourceID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0));
obs.ResourceSetID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceSetID", 0));
obs.Scheduled = false;
obs.Observed = false;
obs.Consumed = false;
obs.Consumer = "";
obs.RuntimeMaterializationStatus = "";
obs.Blocker = "";
obs.UpdateOutcome = "";
obs.RuntimeEvidenceSource = "";
obs.MeasurementRSRP_dB = NaN;
obs.MeasurementRelativeRSRP_dB = NaN;
obs.MeasurementRelativeSource = "";
obs.MeasurementRSRP_dBm = NaN;
obs.MeasurementRSRP_dB_re_UnitOccupiedRE_Es = NaN;
obs.MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = "";
obs.MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es = "";
obs.MeasurementRSSI_dBm = NaN;
obs.MeasurementRSSI_dB_re_UnitOccupiedRE_Es = NaN;
obs.MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = "";
obs.MeasurementRSRQ_dB = NaN;
obs.MeasurementRSRQReceiveAntennaIndex1Based = NaN;
obs.MeasurementRSRQNumeratorRSRP_dBm = NaN;
obs.MeasurementRSRQDenominatorRSSI_dBm = NaN;
obs.MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es = NaN;
obs.MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es = NaN;
obs.MeasurementRSRQAntennaAggregation = "";
obs.MeasurementRSSIPerReceiveAntenna_dBm = "";
obs.MeasurementRSRQPerReceiveAntenna_dB = "";
obs.MeasurementReceiveAntennaIndex1Based = NaN;
obs.MeasurementRSSIAntennaAggregation = "";
obs.MeasurementRSSIStatus = "not_attempted";
obs.MeasurementNumRB = NaN;
obs.MeasurementFirstPRB0Based = NaN;
obs.MeasurementSymbolIndices0Based = "";
obs.MeasurementSubcarrierSpacing_kHz = NaN;
obs.MeasurementBandwidth_Hz = NaN;
obs.MeasurementPhysicalResources = {};
obs.MeasurementPhysicalResourcesJSON = "";
obs.MeasurementRSRPPerReceiveAntenna_dBm = "";
obs.MeasurementRSRPPerResource_dBm = "";
obs.MeasurementRSRPPerResourceValues_dBm = [];
obs.MeasurementRSRPPerAntennaByResource_dBm = {};
obs.MeasurementResourceIDs = "";
obs.MeasurementSelectedResourceOrdinal = NaN;
obs.MeasurementAntennaAggregation = "";
obs.MeasurementFFTSize = NaN;
obs.MeasurementGridScaleToSqrtW = NaN;
obs.MeasurementReceiverGainCorrection_dB = NaN;
obs.MeasurementReceiverGainCorrectionSource = "";
obs.PhysicalMeasurementWaveformStatus = "not_attempted";
obs.PhysicalMeasurementWaveformSource = "";
obs.MeasurementErrors = "";
obs.PhysicalMeasurementStatus = "not_attempted";
obs.PhysicalMeasurementStandard = "";
obs.MeasurementSource = "";
obs.ResourceExtractionAttempted = false;
obs.ResourceExtractionAvailable = false;
obs.ChannelEstimationAttempted = false;
obs.ChannelEstimateAvailable = false;
obs.ChannelEstimateSource = "";
obs.ChannelEstimator = "";
obs.ChannelInterpolationMethod = "";
obs.ChannelEstimateConvention = "";
obs.ChannelEstimateNoiseVariance = NaN;
obs.ChannelEstimateCDMType = "";
obs.ChannelEstimateCDMLengths = "";
obs.PilotRECount = NaN;
obs.PilotResidualPower = NaN;
obs.PilotResidualNMSE_dB = NaN;
obs.ReferenceMeasuredSINR_dB = NaN;
obs.ReferenceMeasuredSINRSource = "";
obs.ReferenceMeasuredSINRStatus = "not_attempted";
obs.ReferenceSINRMeasurementJSON = "";
obs.ChannelEstimateDiagnosticSINR_dB = NaN;
obs.ChannelEstimateDiagnosticSINRSource = "";
obs.ChannelEstimateDiagnosticSINRStatus = "not_attempted";
obs.HestDimensions = "";
obs.HestRxPorts = NaN;
obs.HestTxPorts = NaN;
obs.SINRMeasurementDomain = "";
obs.PowerReferencePlane = "";
obs.CSIMeasurementStateAvailable = false;
obs.CSIMeasurementStatus = "not_required";
obs.CSIMeasurementID = "";
obs.CSIMeasurementDigest = "";
obs.CSIMeasurementProvenance = "";
obs.CSIMeasurementSlot = NaN;
obs.CSIMeasurementNoiseVariance = NaN;
obs.NumConfiguredResources = NaN;
obs.NumMeasuredResources = NaN;
obs.ResourceObjectiveValues = "";
obs.CRISelectionSource = "";
obs.NRE = NaN;
obs.NumPorts = NaN;
obs.RowNumber = NaN;
end

function selected = localSelectedCSIRSConfig(defaultConfig,info,estimateInfo)
selected = defaultConfig;
resources = sixgr.util.structGet(info,"Resources",[]);
if isempty(resources)
    return;
end
ordinal = double(sixgr.util.structGet(estimateInfo, ...
    "SelectedResourceOrdinal",1));
if ~(isscalar(ordinal) && isfinite(ordinal) && ordinal >= 1 && ...
        ordinal <= numel(resources) && ordinal == round(ordinal))
    error("sixgr:mimo:BeamReportMismatch", ...
        "Selected CSI-RS resource ordinal %g is invalid for %d resources.", ...
        ordinal,numel(resources));
end
candidate = sixgr.util.structGet(resources(ordinal),"Configuration",[]);
if ~isa(candidate,"nrCSIRSConfig")
    error("sixgr:mimo:MissingMeasurementState", ...
        "Selected CSI-RS measurement has no matching runtime nrCSIRSConfig.");
end
selected = candidate;
end

function [state, info] = localBuildCSIMeasurementState(cfg, carrier, Hest, nVar, estInfo, canonical)
state = [];
strictCSI = logical(sixgr.util.structGet(cfg, "phy.mimo.strict", false));
info = struct( ...
    "Required", strictCSI, ...
    "Status", "not_required", ...
    "MeasurementID", "", ...
    "Digest", "", ...
    "Provenance", "", ...
    "Slot", NaN, ...
    "NoiseVariance", NaN, ...
    "InterferenceCovarianceIncluded", false);
if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
    info.Status = "disabled_by_yaml";
    if strictCSI
        error("sixgr:mimo:MissingMeasurementState", ...
            "Strict DL CSI is enabled but CSI-RS transmission is disabled by YAML.");
    end
    return;
end
if ~logical(sixgr.util.structGet(estInfo, "Available", false)) || isempty(Hest)
    info.Status = "missing_runtime_csirs_channel_estimate";
    return;
end
Hwb = localCSIRSWidebandChannelMatrix(Hest, estInfo);
validShape = isnumeric(Hwb) && ~isempty(Hwb) && ndims(Hwb) <= 3 && ...
    size(Hwb,1) >= 1 && size(Hwb,2) >= 1 && size(Hwb,3) >= 1;
if ~validShape || ...
        any(~isfinite(real(Hwb(:))) | ~isfinite(imag(Hwb(:))))
    info.Status = "invalid_runtime_csirs_channel_estimate";
    if strictCSI
        error("sixgr:mimo:MissingMeasurementState", ...
            ["Strict DL CSI requires a finite measured Nrx-by-Nport " ...
             "CSI-RS channel matrix or Nrx-by-Nport-by-Nsnapshot stack."]);
    end
    return;
end
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
    info.Status = "invalid_runtime_csirs_noise_variance";
    if strictCSI
        error("sixgr:mimo:MissingMeasurementState", ...
            "Strict DL CSI requires measured finite CSI-RS noise variance.");
    end
    return;
end
report = sixgr.util.structGet(cfg, "phy.csi.reportConfiguration", struct());
reportPorts = double(sixgr.util.structGet(report, "Ports", NaN));
if isscalar(reportPorts) && isfinite(reportPorts) && ...
        reportPorts ~= size(Hwb, 2)
    error("sixgr:mimo:CSIReportPortMismatch", ...
        "CSI report declares %g ports, but the runtime CSI-RS receiver measured %d ports.", ...
        reportPorts, size(Hwb, 2));
end
slotValue = double(sixgr.util.structGet(cfg, ...
    "lls6g.userContext.RuntimeCurrentSlot", localCarrierSlot(carrier)));
if ~(isscalar(slotValue) && isfinite(slotValue) && slotValue >= 0)
    slotValue = 0;
end
slotValue = floor(slotValue);
maxAgeSlots = double(sixgr.util.structGet(cfg, ...
    "phy.mimo.measurementMaxAgeSlots", 8));
if ~(isscalar(maxAgeSlots) && isfinite(maxAgeSlots) && ...
        maxAgeSlots >= 0 && maxAgeSlots == floor(maxAgeSlots))
    error("sixgr:mimo:InvalidMeasurementAge", ...
        "phy.mimo.measurementMaxAgeSlots must be a nonnegative integer.");
end
ueIndex = double(sixgr.util.structGet(cfg, ...
    "lls6g.userContext.RuntimeUEIndex", 0));
if ~(isscalar(ueIndex) && isfinite(ueIndex) && ueIndex >= 0)
    ueIndex = 0;
end
resourceID = double(sixgr.util.structGet(estInfo, "SelectedResourceID", ...
    sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0)));
resourceOrdinal = double(sixgr.util.structGet(estInfo, "SelectedCRI", resourceID));
if ~(isscalar(resourceID) && isfinite(resourceID) && resourceID >= 0)
    resourceID = 0;
end
digest = sixgr.phy.mimo.MatrixContract.digest(Hwb);
measurementID = "csirs-ue" + string(floor(ueIndex)) + ...
    "-resource" + string(floor(resourceID)) + "-slot" + string(slotValue) + ...
    "-" + localShortDigest(digest);
Rint = sixgr.util.structGet(canonical, "InterferenceCovariance", []);
includesNoise=logical(sixgr.util.structGet(canonical,"InterferenceCovarianceIncludesNoise",false));
im=sixgr.util.structGet(estInfo,"InterferenceMeasurement",struct());
if logical(sixgr.util.structGet(im,"Available",false))
    Rint=im.Covariance;
    includesNoise=true;
end
if ~(isnumeric(Rint) && ismatrix(Rint) && ...
        all(size(Rint) == [size(Hwb, 1), size(Hwb, 1)]) && ...
        all(isfinite(real(Rint(:))) & isfinite(imag(Rint(:)))))
    Rint = [];
end
provenance = "measured_runtime_csirs_receiver_channel_and_noise";
state = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID=measurementID, ...
    UEID="UE-" + string(floor(ueIndex)), ...
    ResourceType="NZP-CSI-RS", ...
    ResourceID="CSI-RS-" + string(floor(resourceID)), ...
    ResourceOrdinal=resourceOrdinal, ...
    Slot=slotValue, ...
    MaxAgeSlots=maxAgeSlots, ...
    ChannelEstimate=Hwb, ...
    NoiseVariance=nVar, ...
    InterferenceCovariance=Rint, ...
    InterferenceCovarianceIncludesNoise=~isempty(Rint) && includesNoise, ...
    Provenance=provenance);
info.Status = "runtime_measured_state_ready";
info.MeasurementID = state.MeasurementID;
info.Digest = state.Digest;
info.Provenance = state.Provenance;
info.Slot = state.Slot;
info.NoiseVariance = double(state.NoiseVariance);
info.InterferenceCovarianceIncluded = ~isempty(Rint);
info.ChannelSnapshotCount = double(size(Hwb,3));
end

function Hwb = localCSIRSWidebandChannelMatrix(Hest, estInfo)
Hwb = [];
if isempty(Hest)
    return;
end
if nargin < 2 || ~isstruct(estInfo)
    estInfo = struct();
end
if ndims(Hest) >= 4
    H = double(Hest);
    K = size(H,1);
    L = size(H,2);
    R = size(H,3);
    P = size(H,4);
    pilotMask = sixgr.util.structGet(estInfo,"PilotMask",[]);
    if islogical(pilotMask) && isequal(size(pilotMask),[K L]) && any(pilotMask(:))
        symbolSet = find(any(pilotMask,1));
    else
        symbolSet = 1:L;
    end
    % One receiver channel snapshot per PRB and CSI-RS-bearing OFDM
    % symbol preserves frequency-selective energy without retaining the
    % full interpolated grid in every immutable measurement object.
    prbCount = floor(K/12);
    Hwb = complex(zeros(R,P,max(1,prbCount*numel(symbolSet))));
    writeIndex = 0;
    for symbolIndex = symbolSet
        for prb = 1:prbCount
            subcarrier = (prb-1)*12 + 7;
            snapshot = reshape(H(subcarrier,symbolIndex,:,:),R,P);
            if all(isfinite(real(snapshot(:))) & isfinite(imag(snapshot(:))))
                writeIndex = writeIndex + 1;
                Hwb(:,:,writeIndex) = snapshot;
            end
        end
    end
    Hwb = Hwb(:,:,1:writeIndex);
elseif ndims(Hest) == 3
    H = double(Hest);
    K = size(H,1);
    L = size(H,2);
    R = size(H,3);
    prbCount = floor(K/12);
    Hwb = complex(zeros(R,1,max(1,prbCount*L)));
    writeIndex = 0;
    for symbolIndex = 1:L
        for prb = 1:prbCount
            subcarrier = (prb-1)*12 + 7;
            snapshot = reshape(H(subcarrier,symbolIndex,:),R,1);
            if all(isfinite(real(snapshot(:))) & isfinite(imag(snapshot(:))))
                writeIndex = writeIndex + 1;
                Hwb(:,:,writeIndex) = snapshot;
            end
        end
    end
    Hwb = Hwb(:,:,1:writeIndex);
elseif ismatrix(Hest)
    % nrChannelEstimate's canonical output is K-by-L-by-Nrx-by-Nport.
    % MATLAB removes trailing singleton dimensions, so a one-Rx/one-port
    % estimate is returned as K-by-L.  It is a resource grid, not an
    % Nrx-by-Nport wideband matrix.  Treating its 14 OFDM symbols as ports
    % silently changes the CSI codebook dimension and caused a one-port
    % report to be compared against 14 apparent ports.
    H = double(Hest);
    K = size(H,1);
    L = size(H,2);
    expectedPorts = double(sixgr.util.structGet(estInfo,"ExpectedTxPorts",1));
    numRxAnt = double(sixgr.util.structGet(estInfo,"NumRxAnt",1));
    if ~(isscalar(expectedPorts) && isfinite(expectedPorts) && expectedPorts == 1 && ...
            isscalar(numRxAnt) && isfinite(numRxAnt) && numRxAnt == 1)
        error("sixgr:mimo:CSIRSChannelEstimateDimensionMismatch", ...
            ["A two-dimensional CSI-RS channel estimate is valid only for " ...
             "the canonical K-by-L one-Rx/one-port contract; metadata " ...
             "declares Nrx=%g and Nport=%g."], numRxAnt, expectedPorts);
    end
    pilotMask = sixgr.util.structGet(estInfo,"PilotMask",[]);
    if islogical(pilotMask) && isequal(size(pilotMask),[K L]) && any(pilotMask(:))
        symbolSet = find(any(pilotMask,1));
    else
        symbolSet = 1:L;
    end
    prbCount = floor(K/12);
    Hwb = complex(zeros(1,1,max(1,prbCount*numel(symbolSet))));
    writeIndex = 0;
    for symbolIndex = symbolSet
        for prb = 1:prbCount
            subcarrier = (prb-1)*12 + 7;
            snapshot = H(subcarrier,symbolIndex);
            if isfinite(real(snapshot)) && isfinite(imag(snapshot))
                writeIndex = writeIndex + 1;
                Hwb(1,1,writeIndex) = snapshot;
            end
        end
    end
    Hwb = Hwb(:,:,1:writeIndex);
end
if isvector(Hwb) && ismatrix(Hwb)
    Hwb = reshape(Hwb, numel(Hwb), 1);
end
if ndims(Hwb) > 3 || isempty(Hwb)
    Hwb = [];
end
end

function slotValue = localCarrierSlot(carrier)
slotValue = 0;
if isempty(carrier)
    return;
end
try
    slotValue = double(carrier.NSlot);
catch
end
end

function token = localShortDigest(digest)
chars = char(string(digest));
token = string(chars(1:min(12, numel(chars))));
end

function token = localSizeToken(value)
if isempty(value)
    token = "";
    return;
end
token = strjoin(string(size(value)), "x");
end

function value = localArrayDimension(A, dim)
if isempty(A)
    value = NaN;
    return;
end
sz = size(A);
if dim <= numel(sz)
    value = double(sz(dim));
elseif dim == 4
    value = 1;
else
    value = NaN;
end
end
