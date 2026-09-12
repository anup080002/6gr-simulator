function [rx, info] = PDSCH_Rx(rxWaveform, cfg, varargin)
%PDSCH_Rx Recover a basic PDSCH transmission (OFDM -> PDSCH -> DL-SCH).
%
%   [RX,INFO] = sixgr.phy.dl.PDSCH_Rx(RXWAVEFORM, CFG) performs
%   DMRS-aided timing, OFDM demodulation, channel estimation,
%   MMSE equalization, nrPDSCHDecode demodulation, LDPC rate recovery,
%   LDPC decoding, and transport block CRC checking.
%
%   Name-Value options:
%     "Carrier"     : nrCarrierConfig override
%     "PDSCH"       : nrPDSCHConfig override
%     "PDSCHIndices": mapping indices override
%     "TransportBlockSize": expected TB size (bits)
%     "TargetCodeRate": code rate (0..1)
%     "RV"          : redundancy version (0..3)
%     "NoiseVar"    : noise variance (if known)
%     "NoiseVarDomain": "time", "grid", "frequency", or "auto"
%     "MaxIterations": LDPC iterations (default from cfg)
%     "Algorithm"   : LDPC algorithm ("Normalized min-sum" by default)
%     "PrecodingMatrix": wideband or PRG-bundled PDSCH precoder used by TX
%     "PHYGrant"    : frozen canonical grant dimensional contract
%     "CodingPlan"  : immutable TX DLSCHCodingPlan object(s), required
%     "TrueChannel" : exact physical K-by-L-by-NRx-by-NTx channel tensor
%     "OracleTestMode": explicitly permit perfect-CSI calibration input
%     "PhysicalMeasurementWaveform": antenna-plane waveform used only for
%         calibrated absolute-power measurements; decoding still uses the
%         primary post-front-end RXWAVEFORM
%     "PhysicalMeasurementReferencePlane": declared reference plane for
%         PhysicalMeasurementWaveform
%     "PhysicalMeasurementSource": producer/provenance token for that
%         waveform
%
%   CFG.phy.pdsch.dmrs.dataToDMRSEPREDifference_dB controls the PDSCH
%   data-EPRE minus DM-RS-EPRE difference. The default is 0 dB. The
%   normative -3 dB token maps to exact beta=sqrt(2), matching the
%   transmitter and retaining configured versus realized dB provenance.
%
%   Outputs:
%     RX.TransportBlock     : recovered TB bits (if CRC passes)
%     RX.CRCError           : true if TB CRC fails
%     RX.Ok                 : ~CRCError
%     RX.CodewordLLR        : soft bits before rate recovery
%     RX.ChannelEstimate    : H estimate
%     RX.NoiseVar           : used noise variance
%     RX.TimingOffset       : raw estimated timing offset (samples)
%     RX.AppliedTimingCorrection_samples : applied waveform correction (samples)
%
%   Notes:
%     Ranks 1-4 use one codeword. Ranks 5-8 use two independent DL-SCH
%     codeword paths with per-codeword RV, CodingLayout and soft buffers.

sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.dl.PDSCH_Rx", ...
    "PDSCH", "DL", struct("Stage","RX"));

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCHIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSSymbols', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSInfo', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('CSIRSConfig', [], @(x) isempty(x) || isa(x, 'nrCSIRSConfig'));
ip.addParameter('CSIRSScheduled', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('CSIRSTransmitted', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('PhysicalMeasurementWaveform', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PhysicalMeasurementReferencePlane', "", @(x) ischar(x) || isstring(x));
ip.addParameter('PhysicalMeasurementSource', "", @(x) ischar(x) || isstring(x));
ip.addParameter('TransportBlockSize', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>0)));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>0 & x(:)<1)));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>=0 & x(:)<=3)));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('SchedulerGrantContext', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('Assignment', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHSchedulingAssignment'));
ip.addParameter('ResourcePlan', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHResourcePlan'));
ip.addParameter('ReferenceSignalConfig', struct(), ...
    @(x) (isstruct(x) && isscalar(x)) || ...
        isa(x, 'sixgr.pdsch.PDSCHReferenceSignalConfig'));
ip.addParameter('ReceiverConfig', struct(), @(x) isstruct(x) && isscalar(x));
ip.addParameter('PrecoderBundle', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHPrecoderBundle'));
ip.addParameter('IntegrationContext', struct(), @(x) isstruct(x) && isscalar(x));
ip.addParameter('HARQManager', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHHARQManager'));
ip.addParameter('ExecutionProfile', "", @(x) ischar(x) || isstring(x));
ip.addParameter('HARQSoftBufferLLR', [], @(x) isempty(x) || isnumeric(x) || iscell(x) || isstruct(x));
ip.addParameter('HARQSoftBufferLayout', struct(), @(x) isempty(x) ...
    || isstruct(x) || iscell(x) ...
    || isa(x,'sixgr.pdsch.DLSCHCodingPlan'));
ip.addParameter('CodingLayout', struct(), @(x) isempty(x) || isstruct(x) || iscell(x));
ip.addParameter('CodingPlan', [], @(x) isempty(x) || ...
    isa(x,'sixgr.pdsch.DLSCHCodingPlan') || iscell(x));
ip.addParameter('CalibrationReceiverBundle', struct(), ...
    @(x) isempty(x) || (isstruct(x) && isscalar(x)));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('TimingSearchWindowSamples', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
ip.addParameter('ReceiverTrackingState', [], @(x) isempty(x) || isstruct(x));
ip.addParameter('InterferenceContributionTensor', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('InterferenceContributionSource', "", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('InterferenceContributionDomain', "receiver_sample_waveform_pre_noise", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('InterferenceCovariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('InterferenceCovarianceSource', "", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('InterferenceCovarianceIncludesNoise', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('TrueChannel', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('OracleTestMode', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
profScope = sixgr.perf.TimeProfiler.scope("sixgr.phy.dl.PDSCH_Rx", ...
    "Stage", "dl_pdsch_rx", ...
    "Metadata", struct( ...
    "NSamples", double(numel(rxWaveform)), ...
    "NSubcarriers", double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)) * 12, ...
    "NSymbols", 14, ...
    "NRx", double(max(1, size(rxWaveform, 2))), ...
    "NTx", double(sixgr.util.structGet(cfg, "scenario.gnb.nTxAnt", 1)), ...
    "NLayers", double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)), ...
    "TBSBits", double(localScalarOrNaN(opt.TransportBlockSize)), ...
    "MaxIterations", double(localScalarOrNaN(opt.MaxIterations)))); %#ok<NASGU>
sixgr.config.assertRuntimeFeatureUse(cfg, "cfo_correction", ...
    sixgr.util.structGet(cfg, "phy.rx.cfoCorrectionEnabled", false), ...
    "PDSCH_Rx.cfoCorrection");
sixgr.config.assertRuntimeFeatureUse(cfg, "iq_imbalance_correction", ...
    sixgr.util.structGet(cfg, "phy.rx.iqImbalanceCorrectionEnabled", false), ...
    "PDSCH_Rx.iqImbalanceCorrection");
phyGrant = opt.PHYGrant;
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
executionProfile = localResolveRXExecutionProfile( ...
    cfg, opt.ExecutionProfile, opt.Assignment);
ptrsAuthority = localPTRSAuthorityFeature(cfg, executionProfile, opt.Assignment);
sixgr.config.assertRuntimeFeatureUse(cfg, ptrsAuthority, ...
    localRequestedPTRSEnabled(cfg, opt, phyGrant, hasPHYGrant), ...
    "PDSCH_Rx:" + executionProfile);
sixgr.config.assertRuntimeFeatureUse(cfg, "ptrs_cpe_correction", ...
    sixgr.util.structGet(cfg, "phy.pdsch.ptrs.enableCPECorrection", false), ...
    "PDSCH_Rx.ptrsCPECorrection");
strictAssignmentProfile = any(executionProfile == ...
    ["connected_strict","sps_strict","ra_si_strict"]);
if strictAssignmentProfile && isempty(opt.Assignment)
    error("sixgr:pdsch:MissingSchedulingAssignment", ...
        "%s PDSCH reception requires a decoded immutable scheduling assignment.", ...
        executionProfile);
end
if executionProfile == "ra_si_strict" && ...
        string(opt.Assignment.get("ControlAuthority")) ~= ...
        "receiver_crc_valid_decode"
    error("sixgr:pdsch:InvalidRASIReceiveAuthority", ...
        "RA/SI PDSCH reception requires receiver CRC-valid decoded-DCI ownership.");
end

if ~isempty(opt.Assignment)
    [rx, info] = localDelegateCanonicalPDSCHReceiver( ...
        rxWaveform, cfg, opt, executionProfile, hasPHYGrant);
    return;
end
if any(executionProfile == ["phy_calibration","scheduler_truth"])
    [rx, info] = localDelegateCanonicalGrantReceiver( ...
        rxWaveform, cfg, opt, phyGrant, hasPHYGrant, ...
        executionProfile);
    return;
end
error("sixgr:pdsch:MissingSchedulingAssignment", ...
    "Non-calibration PDSCH reception requires an immutable scheduling assignment.");
end

function featureName = localPTRSAuthorityFeature(cfg, executionProfile, assignment)
featureName = "ptrs";
rntiType = "";
if isa(assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    assignmentData = assignment.toStruct();
    rntiType = upper(strtrim(string(sixgr.util.structGet( ...
        assignmentData, "RNTIType", ""))));
end
if string(executionProfile) ~= "ra_si_strict"
    return;
end
features = sixgr.util.structGet(cfg, "runtime.features", struct());
if rntiType == "SI-RNTI" && isfield(features, "sib1_ptrs")
    featureName = "sib1_ptrs";
elseif rntiType == "RA-RNTI" && isfield(features, "ra_msg2_ptrs")
    featureName = "ra_msg2_ptrs";
elseif rntiType == "TC-RNTI" && isfield(features, "ra_msg4_ptrs")
    featureName = "ra_msg4_ptrs";
end
end

function enabled = localRequestedPTRSEnabled(cfg, opt, phyGrant, hasPHYGrant)
if hasPHYGrant
    enabled = logical(sixgr.util.structGet(phyGrant, ...
        "CodingLayout.PTRSEnabled", false));
elseif ~isempty(opt.PDSCH)
    enabled = logical(localObjectValue(opt.PDSCH, "EnablePTRS", false));
elseif isa(opt.ReferenceSignalConfig, ...
        "sixgr.pdsch.PDSCHReferenceSignalConfig")
    enabled = logical(opt.ReferenceSignalConfig.get("EnablePTRS"));
else
    enabled = logical(sixgr.util.structGet(cfg, "phy.pdsch.enablePTRS", ...
        sixgr.util.structGet(cfg, "phy.ptrs.enable", false)));
end
end

function [rx, info] = localDelegateCanonicalGrantReceiver( ...
        rxWaveform, cfg, opt, phyGrant, hasPHYGrant, executionProfile)
if ~any(executionProfile == ["phy_calibration","scheduler_truth"])
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        "Grant receiver adapter received profile '%s'.", ...
        executionProfile);
end
if executionProfile == "scheduler_truth"
    localRequireSchedulerTruthRXAdapterInputs( ...
        phyGrant, hasPHYGrant, opt.SchedulerGrantContext);
end
if logical(opt.OracleTestMode) && executionProfile ~= "phy_calibration"
    error("sixgr:pdsch:PerfectCSIRequiresCalibrationProfile", ...
        "True-channel PDSCH reception is permitted only for the explicit phy_calibration profile.");
end
if ~isempty(opt.TrueChannel) && ~logical(opt.OracleTestMode)
    error("sixgr:pdsch:OracleTestModeRequired", ...
        "PDSCH TrueChannel input requires OracleTestMode=true.");
end
if logical(opt.OracleTestMode) && isempty(opt.TrueChannel)
    error("sixgr:pdsch:MissingTrueChannel", ...
        "Perfect-CSI PDSCH calibration requires the exact runtime TrueChannel tensor.");
end
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions( ...
        phyGrant, "pdsch_rx_calibration_adapter_entry");
    cfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, phyGrant);
end
localValidateSupportedCodewordScope(cfg, opt.PDSCH);
if isempty(opt.Carrier)
    [carrier, carrierInfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    carrierInfo = struct();
end
if isempty(opt.PDSCH)
    [~, pdschInfo, pdsch] = ...
        sixgr.phy.grid.allocREsPDSCH(carrier, cfg);
else
    pdsch = opt.PDSCH;
    [kernelIndices, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
    if ~isempty(opt.PDSCHIndices) ...
            && ~isequal(double(opt.PDSCHIndices), ...
                double(kernelIndices))
        error("sixgr:pdsch:CalibrationResourcePlanMismatch", ...
            ["PDSCHIndices override differs from the final configured " ...
            "PDSCH data-index kernel output."]);
    end
end
if ~exist('kernelIndices','var')
    kernelIndices = nrPDSCHIndices(carrier,pdsch);
end
nCodewords = localResolvePDSCHNumCodewords( ...
    pdsch, round(double(pdsch.NumLayers)));
codingPlans = localRequireCalibrationCodingPlans( ...
    opt.CodingPlan,nCodewords);
rv = cellfun(@(plan) double(plan.RV),codingPlans);
targetRate = cellfun( ...
    @(plan) double(plan.TargetCodeRate),codingPlans);
transportBlockSizes = cellfun( ...
    @(plan) double(plan.TransportBlockSize),codingPlans);
localAssertOptionalCalibrationPlanVector( ...
    opt.RV,rv,"sixgr:pdsch:CalibrationCodingPlanRVMismatch","RV");
localAssertOptionalCalibrationPlanVector( ...
    opt.TargetCodeRate,targetRate, ...
    "sixgr:pdsch:CalibrationCodingPlanRateMismatch","TargetCodeRate");
localAssertOptionalCalibrationPlanVector( ...
    opt.TransportBlockSize,transportBlockSizes, ...
    "sixgr:pdsch:CalibrationCodingPlanTBSMismatch","TransportBlockSize");
maxIterations = opt.MaxIterations;
if isempty(maxIterations)
    maxIterations = sixgr.phy.phycode.resolveLDPCMaxIterations( ...
        cfg, "Direction", "DL");
end
algorithm = opt.Algorithm;
if isempty(algorithm)
    algorithm = sixgr.util.structGet( ...
        cfg, "phy.ldpc.algorithm", "Normalized min-sum");
end
xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead( ...
    cfg, localObjectValue(pdsch, "SymbolAllocation", []));
[~, dmrsPowerInfo] = localApplyPDSCHDMRSEPREDifference( ...
    complex(1), cfg);
if executionProfile == "phy_calibration" && ...
        ~isempty(fieldnames(opt.CalibrationReceiverBundle))
    reusedCalibrationReceiverBundle = true;
    bundle = localReuseCalibrationReceiverBundle( ...
        opt.CalibrationReceiverBundle, carrier, pdsch, kernelIndices, ...
        codingPlans, xOverhead, dmrsPowerInfo, rxWaveform, opt, ...
        maxIterations, algorithm);
else
    reusedCalibrationReceiverBundle = false;
    mcsOwnership = ...
        sixgr.pdsch.PDSCHCalibrationFacadeAdapter.resolveMCSOwnership( ...
            cfg, phyGrant, nCodewords);
    request = struct( ...
        "ExecutionProfile", executionProfile, ...
        "SchedulerGrantContext", opt.SchedulerGrantContext, ...
        "TargetCodeRate", targetRate, "RV", rv, ...
        "XOverhead", xOverhead, ...
        "MCSTablePerCodeword", mcsOwnership.MCSTablePerCodeword, ...
        "MCSIndexPerCodeword", mcsOwnership.MCSIndexPerCodeword, ...
        "UECapability1024QAM", mcsOwnership.UECapability1024QAM, ...
        "RRCEnabled1024QAM", mcsOwnership.RRCEnabled1024QAM, ...
        "DCIEnabled1024QAM", mcsOwnership.DCIEnabled1024QAM, ...
        "DCIFormat", mcsOwnership.DCIFormat, ...
        "UECapability1024QAMVariant", ...
            mcsOwnership.UECapability1024QAMVariant, ...
        "MaxNumberMIMOLayersPDSCH", ...
            mcsOwnership.MaxNumberMIMOLayersPDSCH, ...
        "NumLayers", double(pdsch.NumLayers), ...
        "DeploymentAllows1024QAM", ...
            mcsOwnership.DeploymentAllows1024QAM, ...
        "FrequencyRange", mcsOwnership.FrequencyRange, ...
        "OperatingBand", mcsOwnership.OperatingBand, ...
        "DeploymentClass", mcsOwnership.DeploymentClass, ...
        "FrequencyRangeAllows1024QAM", ...
            mcsOwnership.FrequencyRangeAllows1024QAM, ...
        "BandAllows1024QAM", mcsOwnership.BandAllows1024QAM, ...
        "TransportBlockSizes", transportBlockSizes, ...
        "TransportBlockBits", [], ...
        "CodingPlans", {codingPlans}, ...
        "PrecodingMatrix", opt.PrecodingMatrix, ...
        "ReservedREZeroBased", zeros(1,0), ...
        "DMRSAmplitudeScale", ...
            double(dmrsPowerInfo.DMRSAmplitudeScale), ...
        "DMRSPortResolutionPolicy", ...
            "explicit_calibration_rank_order_ports", ...
        "NPhysicalRxAntennas", size(rxWaveform,2), ...
        "NoiseVariance", opt.NoiseVar, ...
        "NoiseVarianceDomain", opt.NoiseVarDomain, ...
        "MaxIterations", maxIterations, ...
        "Algorithm", algorithm, ...
        "ReceiverOnly", true);
    bundle = sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materialize( ...
        cfg, carrier, pdsch, request);
end
localAssertCalibrationCodingLayoutMatchesPlan( ...
    opt.CodingLayout, codingPlans);
[rxWaveform, trackingCorrection, timingResolution, syncState] = ...
    localApplyCalibrationReceiverTracking( ...
    rxWaveform, carrier, pdsch, cfg, opt);
opt.RuntimeTrackingCorrection = trackingCorrection;
opt.RuntimeTimingResolution = timingResolution;
opt.RuntimeSynchronizationState = syncState;
[opt.PhysicalMeasurementGrid, opt.PhysicalMeasurementOFDMInfo, ...
    opt.PhysicalMeasurementGridStatus] = ...
    localPreparePhysicalMeasurementGrid( ...
    opt.PhysicalMeasurementWaveform, carrier, trackingCorrection, ...
    timingResolution);

appliedTimingCorrection = double(sixgr.util.structGet( ...
    timingResolution, "AppliedCorrection_samples", 0));
[pdschInd, ~] = nrPDSCHIndices(carrier, pdsch);
configuredNoiseVariance = double(opt.NoiseVar);
if isempty(configuredNoiseVariance) || ~isscalar(configuredNoiseVariance) ...
        || ~isfinite(configuredNoiseVariance) || configuredNoiseVariance < 0
    configuredNoiseVariance = 0;
end
    rxPortShape = complex(zeros(0,0,size(rxWaveform,2)));
    [Rint, rintInfo, RintIncludesNoise] = ...
        localResolvePDSCHInterferenceCovariance(opt, carrier, pdschInd, cfg, ...
        appliedTimingCorrection, configuredNoiseVariance,rxPortShape,[],[],[]);

canonical = sixgr.pdsch.PDSCHReceiver( ...
    rxWaveform, bundle.Assignment, bundle.ResourcePlan, ...
    bundle.Carrier, bundle.ReferenceConfig, ...
    bundle.ReceiverConfig, ...
    "CodingPlans", bundle.CodingPlans, ...
    "PrecoderBundle", bundle.PrecoderBundle, ...
    "PriorRecoveredLLR", opt.HARQSoftBufferLLR, ...
    "PriorCodingPlan", opt.HARQSoftBufferLayout, ...
    "HARQKey", char(bundle.Assignment.AssignmentId), ...
    "HARQManager", opt.HARQManager, ...
    "UseMexLDPC",logical(sixgr.util.structGet( ...
        cfg,"phy.ldpc.useMexBatchDecode",false)), ...
    "InterferenceCovariance", Rint, ...
    "InterferenceCovarianceInfo", rintInfo, ...
    "InterferenceCovarianceIncludesNoise", logical(RintIncludesNoise), ...
    "TrueChannel", opt.TrueChannel, ...
    "OracleTestMode", logical(opt.OracleTestMode), ...
    "EnablePTRSCPECorrection", logical(sixgr.util.structGet( ...
        cfg, "phy.pdsch.ptrs.enableCPECorrection", false)), ...
    "EnableDMRSResidualPostEqSINRBound", logical(sixgr.util.structGet( ...
        cfg, "phy.pdsch.measurements.dmrsResidualPostEqSINRBoundEnabled", false)), ...
    "EnableDecisionDirectedPostEqSINRBound", logical(sixgr.util.structGet( ...
        cfg, "phy.pdsch.measurements.decisionDirectedPostEqSINRBoundEnabled", false)));
[rx, info] = localAdaptCanonicalCalibrationRX( ...
    canonical, bundle, pdschInfo, carrierInfo, ...
    dmrsPowerInfo, cfg, opt, phyGrant, hasPHYGrant);
rx.CalibrationReceiverBundleReused = ...
    logical(reusedCalibrationReceiverBundle);
info.CalibrationReceiverBundleReused = ...
    logical(reusedCalibrationReceiverBundle);
end

function bundle = localReuseCalibrationReceiverBundle( ...
        raw,carrier,pdsch,kernelIndices,codingPlans,xOverhead, ...
        dmrsPowerInfo,rxWaveform,opt,maxIterations,algorithm)
required = ["Assignment","ResourcePlan","Carrier","PDSCH", ...
    "ReferenceConfig","ReceiverConfig","CodingPlans", ...
    "TransportBlockSizes","TargetCodeRate","RV","XOverhead"];
if ~all(isfield(raw,required))
    error("sixgr:pdsch:IncompleteCalibrationReceiverBundle", ...
        "The transmitter calibration receiver bundle is incomplete.");
end
if string(raw.Assignment.Profile) ~= "phy_calibration"
    error("sixgr:pdsch:CalibrationReceiverBundleProfileMismatch", ...
        "Only a phy_calibration transmitter bundle may be reused.");
end
carrierProperties = ["NCellID","NSizeGrid","NStartGrid", ...
    "SubcarrierSpacing","NFrame","NSlot","CyclicPrefix"];
for index = 1:numel(carrierProperties)
    name = char(carrierProperties(index));
    if ~isequal(raw.Carrier.(name),carrier.(name))
        error("sixgr:pdsch:CalibrationReceiverBundleCarrierMismatch", ...
            "Transmitter and receiver carrier property %s differs.",name);
    end
end
pdschProperties = ["NID","RNTI","NumLayers","Modulation", ...
    "PRBSet","SymbolAllocation","MappingType","VRBToPRBInterleaving", ...
    "VRBBundleSize","EnablePTRS"];
for index = 1:numel(pdschProperties)
    name = char(pdschProperties(index));
    if ~isequal(raw.PDSCH.(name),pdsch.(name))
        error("sixgr:pdsch:CalibrationReceiverBundlePDSCHMismatch", ...
            "Transmitter and receiver PDSCH property %s differs.",name);
    end
end
localAssertCalibrationResourceAgreement( ...
    raw.ResourcePlan,carrier,pdsch,kernelIndices);
rawPlans = raw.CodingPlans;
if ~iscell(rawPlans), rawPlans = {rawPlans}; end
if numel(rawPlans) ~= numel(codingPlans) || ...
        any(~cellfun(@(a,b) string(a.PlanID) == string(b.PlanID), ...
        rawPlans,codingPlans))
    error("sixgr:pdsch:CalibrationReceiverBundleCodingPlanMismatch", ...
        "Transmitter and receiver immutable coding plans differ.");
end
if double(raw.XOverhead) ~= double(xOverhead) || ...
        abs(double(raw.ReferenceConfig.get("DMRSAmplitudeScale")) - ...
        double(dmrsPowerInfo.DMRSAmplitudeScale)) > 32*eps
    error("sixgr:pdsch:CalibrationReceiverBundleReferenceMismatch", ...
        "Transmitter and receiver overhead or DM-RS power contracts differ.");
end
bundle = raw;
receiver = bundle.ReceiverConfig;
if double(receiver.NPhysicalRxAntennas) ~= size(rxWaveform,2)
    error("sixgr:pdsch:CalibrationReceiverBundleAntennaMismatch", ...
        "Transmitter bundle receiver branches differ from the received waveform.");
end
if ~isempty(opt.NoiseVar)
    domain = lower(strtrim(string(opt.NoiseVarDomain)));
    if any(domain == ["grid","frequency"])
        gridNoiseVariance = double(opt.NoiseVar);
    elseif domain == "time"
        ofdmOptions = bundle.ReferenceConfig.get("OFDMOptions");
        calibration = sixgr.phy.waveform.calibrateOFDMNoiseTransform( ...
            carrier,ofdmOptions{:});
        [gridNoiseVariance,~] = ...
            sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
            opt.NoiseVar,calibration,"InputDomain","time", ...
            "Source","pdsch_tx_receiver_bundle_reuse");
    else
        error("sixgr:pdsch:CalibrationReceiverBundleNoiseDomain", ...
            "Bundle reuse requires an explicit time or grid NoiseVarDomain.");
    end
    receiver.NoiseVariance = double(gridNoiseVariance);
end
receiver.MaxIterations = double(maxIterations);
receiver.Algorithm = char(string(algorithm));
bundle.ReceiverConfig = receiver;
bundle.ReceiverMaterializationSource = ...
    "same_transmission_calibration_bundle_exact_reuse";
end

function localAssertCalibrationResourceAgreement( ...
        resourcePlan,carrier,pdsch,kernelIndices)
% The immutable ownership plan records each scheduled base-grid RE once.
% nrPDSCHIndices records one linear grid index for every layer.  Comparing
% those vectors directly is therefore valid only for rank one.  Prove the
% stronger multi-layer invariant without discarding the layer dimension:
% every owned base RE must occur exactly once on every configured layer.
nSubcarriers = 12 * double(carrier.NSizeGrid);
symbolsPerSlot = double(carrier.SymbolsPerSlot);
planeSize = nSubcarriers * symbolsPerSlot;
nLayers = double(pdsch.NumLayers);
expectedBase = double(resourcePlan.DataIndices(:)) + 1;
actualLinear = double(kernelIndices(:));

validScalarContract = isscalar(planeSize) && isfinite(planeSize) ...
    && planeSize == fix(planeSize) && planeSize > 0 ...
    && isscalar(nLayers) && isfinite(nLayers) ...
    && nLayers == fix(nLayers) && nLayers >= 1;
validIndices = all(isfinite(actualLinear)) ...
    && all(actualLinear == fix(actualLinear)) ...
    && all(actualLinear >= 1) ...
    && all(actualLinear <= planeSize * nLayers);
expectedCardinality = numel(expectedBase) * nLayers;
if ~validScalarContract || ~validIndices ...
        || numel(actualLinear) ~= expectedCardinality
    error("sixgr:pdsch:CalibrationReceiverBundleResourceMismatch", ...
        "Transmitter resource ownership and receiver PDSCH indices " + ...
        "have incompatible grid, layer, bounds, or cardinality contracts.");
end

actualBase = mod(actualLinear - 1,planeSize) + 1;
expectedLayeredBase = repmat(expectedBase,nLayers,1);
if ~isequal(sort(actualBase),sort(expectedLayeredBase))
    error("sixgr:pdsch:CalibrationReceiverBundleResourceMismatch", ...
        "Transmitter resource ownership differs from the receiver " + ...
        "PDSCH base-grid indices or per-layer multiplicity.");
end
end

function localRequireSchedulerTruthRXAdapterInputs( ...
        phyGrant, hasPHYGrant, grant)
if ~hasPHYGrant
    error("sixgr:pdsch:MissingSchedulerTruthPHYGrant", ...
        "scheduler_truth PDSCH receiver requires a frozen exact PHYGrant.");
end
if ~logical(sixgr.util.structGet(phyGrant, "IsFrozen", false))
    error("sixgr:pdsch:UnfrozenSchedulerTruthPHYGrant", ...
        "scheduler_truth PDSCH receiver requires an immutable frozen PHYGrant.");
end
if ~(isstruct(grant) && ~isempty(fieldnames(grant)) && ...
        logical(sixgr.util.structGet(grant, ...
            "PDCCHGrantBindingOk", false)) && ...
        logical(sixgr.util.structGet(grant, ...
            "ControlDecodeOk", false)))
    error("sixgr:pdsch:MissingSchedulerTruthPDCCHBinding", ...
        "scheduler_truth PDSCH receiver requires a decoded, successfully bound PDCCH grant.");
end
end

function [rx, info] = localAdaptCanonicalCalibrationRX( ...
        canonical, bundle, pdschInfo, carrierInfo, ...
        dmrsPowerInfo, cfg, opt, phyGrant, hasPHYGrant)
carrier = bundle.Carrier;
pdsch = bundle.PDSCH;
nCodewords = numel(bundle.TransportBlockSizes);
nLayers = double(pdsch.NumLayers);
nPorts = double(bundle.ReferenceConfig.get("NPhysicalTxAntennas"));
plane = double(carrier.NSizeGrid) * 12 ...
    * double(carrier.SymbolsPerSlot);
[pdschInd, kernelInfo] = nrPDSCHIndices(carrier,pdsch);
[dmrsInd, dmrsSymBase, dmrsInfo] = ...
    sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);
dmrsSym = complex(dmrsSymBase) ...
    .* double(dmrsPowerInfo.DMRSAmplitudeScale);
ptrsInd = [];
ptrsSym = complex(zeros(0,1));
if pdsch.EnablePTRS
    ptrsInd = nrPDSCHPTRSIndices(carrier,pdsch);
    ptrsSym = complex(nrPDSCHPTRS(carrier,pdsch));
end
pdschAntInd = localCalibrationRXPortIndices( ...
    bundle.ResourcePlan.DataIndices,nPorts,plane);
dmrsUnion = unique([bundle.ResourcePlan.DMRSIndicesPerPort{:}], ...
    "sorted");
dmrsAntInd = localCalibrationRXPortIndices( ...
    dmrsUnion,nPorts,plane);
ptrsUnion = unique([bundle.ResourcePlan.PTRSIndicesPerPort{:}], ...
    "sorted");
ptrsAntInd = localCalibrationRXPortIndices( ...
    ptrsUnion,nPorts,plane);

layouts = cellfun(@(x) x.toCodingLayout(), ...
    canonical.CodingPlans, "UniformOutput", false);
rateBits = double(bundle.ResourcePlan.GPerCodeword);
mapping = localBuildPDSCHRxCodewordLayerContract( ...
    pdsch, rateBits, layouts);
mapping = localFinalizePDSCHRxCodewordLayerContract( ...
    mapping, canonical.DescrambledLLR, canonical.LayerSymbols);
[decoded, recLLR, recInfo, decodedBlocks, activeIterations, ...
    parityChecks, cbCRCError, lineage] = ...
    localCanonicalRXDecodeEvidence(canonical.Decode,nCodewords);

estimatedNoise = double(canonical.EstimatedNoiseVariance);
decoderNoise = double(canonical.NoiseVarianceUsedForLLR);
if ~(isscalar(decoderNoise) && isfinite(decoderNoise) ...
        && decoderNoise > 0)
    decoderNoise = eps;
end
channelEstimate = canonical.EffectiveLayerChannelEstimate;
if isempty(channelEstimate)
    channelEstimate = canonical.ChannelGainPerPhysicalPort;
end
sinr = double(canonical.Metrics. ...
    MeasuredPostEqualizationSINRdBPerLayer);
postEqSINR = mean(sinr,"omitnan");
rawEqualizerSINRPerLayer = double(sixgr.util.structGet(canonical, ...
    "PostEqSINRRawEqualizerPerLayer_dB",sinr));
rawEqualizerSINR = mean(rawEqualizerSINRPerLayer,"omitnan");
llrCell = canonical.DescrambledLLR;
llr = llrCell{1};
codewordLLRCount = cellfun(@numel,llrCell);
segmentation = cellfun(@(x) ...
    sixgr.util.structGet(x,"Segmentation",struct()), ...
    layouts,"UniformOutput",false);

rx = canonical;
executionProfile = string(bundle.Assignment.Profile);
isSchedulerTruth = executionProfile == "scheduler_truth";
rx.ExecutionProfile = char(executionProfile);
rx.FacadeContractVersion = "PDSCH_RxCompatibilityFacade/v3";
rx.CanonicalDelegation = true;
rx.DelegationTarget = "sixgr.pdsch.PDSCHReceiver";
rx.StrictSchedulingOwnership = logical(isSchedulerTruth);
rx.SchedulingOwnership = char(ternaryPDSCHRXProfile( ...
    isSchedulerTruth, ...
    "decoded_scheduler_grant_pdcch_bound_assignment", ...
    "explicit_phy_calibration_assignment"));
rx.AssignmentId = char(bundle.Assignment.AssignmentId);
rx.TransportBlockSize = double(bundle.TransportBlockSizes);
rx.TransportBlockSizePerCodeword = ...
    double(bundle.TransportBlockSizes);
rx.Ok = logical(canonical.CRCPass);
rx.TBCRCPass = logical(canonical.CRCPass);
trackingCorrection = sixgr.util.structGet( ...
    opt, "RuntimeTrackingCorrection", struct());
timingResolution = sixgr.util.structGet( ...
    opt, "RuntimeTimingResolution", struct());
rx.ReceiveTiming = sixgr.util.structGet(timingResolution,'ReceiveTiming',struct());
syncState = sixgr.util.structGet( ...
    opt, "RuntimeSynchronizationState", struct());
rx.TimingOffset = double(sixgr.util.structGet( ...
    syncState, "RawTimingEstimate_samples", NaN));
rx.RawTimingEstimate_samples = rx.TimingOffset;
rx.KnownTimingDelay_samples = double(sixgr.util.structGet( ...
    syncState, "KnownTimingDelay_samples", 0));
rx.TimingEstimateForCorrection_samples = double(sixgr.util.structGet( ...
    syncState, "EstimatedTimingOffsetForCorrection_samples", ...
    rx.RawTimingEstimate_samples - rx.KnownTimingDelay_samples));
rx.AppliedTimingCorrection_samples = double(sixgr.util.structGet( ...
    timingResolution, "AppliedCorrection_samples", NaN));
rx.TimingEstimateUsed = logical(sixgr.util.structGet( ...
    timingResolution, "EstimateUsed", false));
rx.TimingEstimateSource = char(string(sixgr.util.structGet( ...
    timingResolution, "Source", "unavailable")));
rx.TimingEstimateStatus = char(string(sixgr.util.structGet( ...
    timingResolution, "Status", "unavailable")));
rx.TimingEstimateApplicationPolicy = char(string(sixgr.util.structGet( ...
    timingResolution, "ApplicationPolicy", "")));
rx.TimingEstimateWasClipped = logical(sixgr.util.structGet( ...
    timingResolution, "WasClipped", false));
rx.SynchronizationState = syncState;
rx.NoiseVar = decoderNoise;
rx.NoiseVarStatus = "OK";
rx.NoiseVarSource = ...
    "canonical_post_equalization_noise_variance";
rx.NoiseVarReason = "";
rx.NoiseVarStrictFailure = false;
rx.NoiseVarDomain = ...
    "post_equalization_decoder_symbol_domain";
rx.PreEqualizationNoiseVar = estimatedNoise;
rx.PreEqualizationNoiseVariance = estimatedNoise;
rx.PreEqualizationNoiseVarDomain = ...
    "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarianceDomain = ...
    "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarianceSource = ...
    "canonical_pdsch_dmrs_channel_estimator";
rx.PreEqualizationNoiseVarTransformSource = ...
    "calibration_adapter_explicit_domain_conversion";
rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet( ...
    canonical.OFDMInfo, "SampleToGridNoiseVarianceGain", NaN));
rx.DecoderNoiseVar = decoderNoise;
rx.PostEqualizationNoiseVar = decoderNoise;
rx.PostEqualizationNoiseVariance = decoderNoise;
rx.PostEqualizationNoiseVarianceDomain = ...
    "unit_constellation_layer_symbol_post_equalization";
rx.PostEqualizationNoiseVarianceSource = ...
    "canonical_pdsch_equalizer_decoder_variance";
rx.DecoderNoiseVarStatus = "OK";
rx.DecoderNoiseVarSource = ...
    "canonical_pdsch_receiver";
if logical(sixgr.util.structGet(canonical, ...
        "PostEqSINRDecisionResidualBoundApplied",false))
    rx.DecoderNoiseVarReductionMethod = ...
        "decision_directed_post_equalization_residual_bound";
elseif logical(sixgr.util.structGet(canonical, ...
        "PostEqSINRDMRSResidualBoundApplied",false))
    rx.DecoderNoiseVarReductionMethod = ...
        "dmrs_post_equalization_residual_bound";
else
    rx.DecoderNoiseVarReductionMethod = ...
        "canonical_equalizer_per_resource_variance";
end
rx.ReceiverUsable = true;
rx.DecodeAttempted = true;
rx.DecodeUsable = true;
rx.FailureReason = "";
rx.DecodeLatency_s = double(sixgr.util.structGet( ...
    canonical.Decode,"DecodeLatency_s",NaN));
rx.DecodeLatencySource = char(string(sixgr.util.structGet( ...
    canonical.Decode,"DecodeLatencySource","unavailable")));
rx.DecodeLatencyPerCodeword_s = double(sixgr.util.structGet( ...
    canonical.Decode,"DecodeLatencyPerCodeword_s", ...
    rx.DecodeLatency_s));
rx.UseMexLDPC = logical(sixgr.util.structGet( ...
    canonical.Decode,"UseMexLDPC",false));
rx.LDPCDecoderEngine = string(sixgr.util.structGet( ...
    canonical.Decode,"DecoderEngine","nrLDPCDecode"));
rx.MaxDecoderIterations = ...
    double(bundle.ReceiverConfig.MaxIterations);
rx.DecoderIterations = mean(activeIterations,"omitnan");
rx.NumCodeBlocks = double(layouts{1}.NumCodeBlocks);
rx.NumCodeBlocksPerCodeword = cellfun( ...
    @(x) double(x.NumCodeBlocks),layouts);
rx.CodeBlockLength_bits = ...
    double(layouts{1}.CodeBlockLength);
rx.CodeBlockLengthPerCodeword_bits = cellfun( ...
    @(x) double(x.CodeBlockLength),layouts);
rx.TransportBlockCRCLength = ...
    double(layouts{1}.TBCRCLength);
rx.TransportBlockCRCLengthPerCodeword = cellfun( ...
    @(x) double(x.TBCRCLength),layouts);
rx.TransportBlockLenWithCRC = ...
    double(layouts{1}.TransportBlockLengthWithCRC);
rx.TransportBlockLenWithCRCPerCodeword = cellfun( ...
    @(x) double(x.TransportBlockLengthWithCRC),layouts);
rx.CodingLayout = layouts{1};
rx.CodingLayouts = layouts;
rx.CodewordLayerMapping = mapping;
rx.NumCodewords = nCodewords;
rx.ActualNumCodewords = nCodewords;
rx.CodewordLLRCountPerCodeword = codewordLLRCount;
rx.DecodedBitLineage = lineage{1};
rx.DecodedBitLineagePerCodeword = lineage;
rx.LDPCRateRecoverNumCodeBlocks = ...
    double(layouts{1}.NumCodeBlocks);
rx.LDPCRateRecoverNumCodeBlocksPerCodeword = cellfun( ...
    @(x) double(x.NumCodeBlocks),layouts);
harqInfo = cellfun(@(x) x.HARQCombineInfo, decoded, ...
    "UniformOutput", false);
harqSummary = localSummarizeHARQCombining(harqInfo);
rx.HARQSoftCombiningApplied = logical(harqSummary.Applied);
rx.HARQSoftCombiningAppliedPerCodeword = ...
    logical(harqSummary.AppliedPerCodeword);
rx.HARQSoftCombiningReason = string(harqSummary.Reason);
rx.HARQSoftCombiningCurrentNumel = double(harqSummary.CurrentNumel);
rx.HARQSoftCombiningPriorNumel = double(harqSummary.PriorNumel);
rx.HARQSoftCombiningPositionAware = logical(harqSummary.PositionAware);
rx.HARQSoftCombiningOverlapPositionCount = ...
    double(harqSummary.OverlapPositionCount);
rx.XOverhead = double(bundle.XOverhead);
rx.CFOEstimateAvailable = logical(sixgr.util.structGet( ...
    trackingCorrection, "CFOEstimateAvailable", false));
rx.EstimatedCFO_Hz = double(sixgr.util.structGet( ...
    trackingCorrection, "EstimatedCFO_Hz", NaN));
rx.EstimatedCommonFrequency_Hz = double(sixgr.util.structGet( ...
    syncState, "EstimatedCommonFrequency_Hz", NaN));
rx.PhysicalDoppler_Hz = double(sixgr.util.structGet( ...
    syncState, "PhysicalDoppler_Hz", NaN));
rx.CFOCorrectionApplied = logical(sixgr.util.structGet( ...
    trackingCorrection, "CFOCorrectionApplied", false));
rx.CFOCorrectionApplied_Hz = double(sixgr.util.structGet( ...
    trackingCorrection, "CFOCorrectionApplied_Hz", NaN));
rx.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet( ...
    syncState, "ResidualCFO_PostCorrection_Hz", NaN));
rx.ResidualCFO_EstimatedPostCorrection_Hz = double(sixgr.util.structGet( ...
    syncState, "ResidualCFO_EstimatedPostCorrection_Hz", NaN));
rx.ResidualCFOEstimateSource = char(string(sixgr.util.structGet( ...
    trackingCorrection, "ResidualCFOEstimateSource", "")));
rx.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet( ...
    syncState, "ResidualTimingError_PostCorrection_samples", NaN));
rx.PTRSConfiguredEnabled = logical(pdsch.EnablePTRS);
rx.PTRSCPECorrectionConfigured = logical(sixgr.util.structGet( ...
    cfg, "phy.pdsch.ptrs.enableCPECorrection", false));
rx.CPECorrectionApplied = logical(sixgr.util.structGet( ...
    canonical.PTRSCorrection,"Applied",false));
rx.CPECorrectedSymbols = double(sixgr.util.structGet( ...
    canonical.PTRSCorrection,"CorrectedSymbolCount",0));
rx.CPEMeanCorrection_deg = double(sixgr.util.structGet( ...
    canonical.PTRSCorrection,"MeanCPE_deg",NaN));
rx.CPECorrectionNAReason = char(string(sixgr.util.structGet( ...
    canonical.PTRSCorrection,"NAReason","")));
rx.PTRSCPECorrectionEnabled = rx.PTRSCPECorrectionConfigured;
rx.PTRSCPECorrectionApplied = rx.CPECorrectionApplied;
rx.PTRSCPECorrectionSymbols = rx.CPECorrectedSymbols;
rx.PTRSMeanCPE_deg = rx.CPEMeanCorrection_deg;
rx.PTRSCPECorrectionReason = rx.CPECorrectionNAReason;
rx.PTRSCPECorrectionStatus = char(string(sixgr.util.structGet( ...
    canonical.PTRSCorrection,"Status","")));
rx.PTRSReceiverEvidenceSource = ...
    "sixgr.pdsch.PDSCHReceiver.PTRSCorrection";
rx.ReceiverTrackingCorrectionSource = char(string(sixgr.util.structGet( ...
    trackingCorrection, "Source", "unavailable_receiver_tracking_state")));
rx.ReceiverTrackingCorrectionStatus = char(string(sixgr.util.structGet( ...
    trackingCorrection, "Status", "unavailable")));
rx.ReceiverTrackingCorrectionNAReason = char(string(sixgr.util.structGet( ...
    trackingCorrection, "NAReason", "")));
rx.ReceiverHestSINR_dB = rawEqualizerSINR;
rx.ReceiverHestSINRSource = ...
    "canonical_dmrs_estimate_and_equalizer";
rx.ReceiverHestSINRValueRole = ...
    "raw_equalizer_diagnostic_not_scheduling_authority";
rx.ReceiverHestSINRValueStatus = "OK";
rx.ReceiverHestSINRNAReason = "";
rx.PostEqSINR_dB = postEqSINR;
dmrsBoundApplied = logical(sixgr.util.structGet(canonical, ...
      "PostEqSINRDMRSResidualBoundApplied",false));
decisionBoundApplied = logical(sixgr.util.structGet(canonical, ...
      "PostEqSINRDecisionResidualBoundApplied",false));
if decisionBoundApplied
      rx.PostEqSINRSource = ...
          "canonical_decision_directed_post_equalization_residual_bounded_equalizer_sinr";
      rx.PostEqSINRValueStatus = "OK_DECISION_RESIDUAL_BOUNDED";
elseif dmrsBoundApplied
      rx.PostEqSINRSource = ...
          "canonical_dmrs_post_equalization_residual_bounded_equalizer_sinr";
      rx.PostEqSINRValueStatus = "OK_DMRS_RESIDUAL_BOUNDED";
else
      rx.PostEqSINRSource = "canonical_post_equalization_sinr";
      rx.PostEqSINRValueStatus = "OK";
end
rx.PostEqSINRValueRole = ...
    "measured_post_equalization_scheduling_input";
rx.PostEqSINRNAReason = "";
rx.PostEqSINRPerLayer_dB = sinr;
rx.PostEqSINRRawEqualizer_dB = rawEqualizerSINR;
rx.PostEqSINRRawEqualizerPerLayer_dB = rawEqualizerSINRPerLayer;
rx.PostEqSINRDMRSResidualBoundApplied = dmrsBoundApplied;
rx.PostEqSINRDecisionResidualBoundApplied = decisionBoundApplied;
rx.DMRSResidualPostEqSINRBoundEnabled = logical(sixgr.util.structGet( ...
      canonical,"DMRSResidualPostEqSINRBoundEnabled",false));
rx.DecisionDirectedPostEqSINRBoundEnabled = logical(sixgr.util.structGet( ...
      canonical,"DecisionDirectedPostEqSINRBoundEnabled",false));
rx.PostEqSINRDMRSResidual_dB = mean(double(sixgr.util.structGet( ...
      canonical,"DMRSPostEqualizationResidual.SINRdBPerLayer",NaN)),"omitnan");
rx.PostEqDecisionResidual_dB = mean(double(sixgr.util.structGet( ...
      canonical,"DecisionDirectedPostEqualizationResidual.SINRdBPerLayer",NaN)),"omitnan");
    covarianceApplied=logical(sixgr.util.structGet( ...
        canonical.EqualizationInfo,"InterferenceCovarianceAvailable",false));
    if covarianceApplied
        rx.EqualizerType = "MMSE-IRC";
        rx.EqualizerEquation = "unbiased_layer_LMMSE_with_measured_receive_covariance";
    else
        rx.EqualizerType = "MMSE";
        rx.EqualizerEquation = "unbiased_layer_LMMSE_with_scalar_noise";
    end
    rx.EqualizerRequestedType = "MMSE";
rx.EqualizerEngine = char(string(sixgr.util.structGet( ...
    canonical.EqualizationInfo,"EngineUsed","")));
    rx.EqualizerResultContract = "canonical_resource_selective_equalizer";
    rx.EqualizerCovarianceIncludesNoise = logical(sixgr.util.structGet( ...
        canonical.EqualizationInfo,"InterferenceCovarianceIncludesNoise",false));
rx.EqualizerNoiseAddedExactlyOnce = true;
rx.EqualizerUniqueSolveCount = double(sixgr.util.structGet( ...
    canonical.EqualizationInfo, "UniqueSolveCount", NaN));
rx.EqualizerSolveCount = double(sixgr.util.structGet( ...
    canonical.EqualizationInfo, "SolveCount", ...
    double(bundle.ResourcePlan.ExactDataRECount)));
rx.EqualizerCovarianceFactorizationCount = double(sixgr.util.structGet( ...
    canonical.EqualizationInfo, "CovarianceFactorizationCount", NaN));
rintInfo = sixgr.util.structGet(canonical, ...
    "InterferenceCovarianceInfo", struct());
rx.InterferenceCovarianceAvailable = logical(sixgr.util.structGet( ...
    rintInfo, "Available", false));
rx.InterferenceCovarianceSource = string(sixgr.util.structGet( ...
    rintInfo, "Source", "not_requested"));
rx.InterferenceCovarianceStatus = string(sixgr.util.structGet( ...
    rintInfo, "Status", "not_applicable"));
rx.InterferenceCovarianceIncludesNoise = logical(sixgr.util.structGet( ...
    canonical, "InterferenceCovarianceIncludesNoise", false));
rx.InterferenceCovarianceDomain = string(sixgr.util.structGet( ...
    rintInfo, "Domain", "not_applicable"));
resourceDiagnostics = localBuildPDSCHRxResourceDiagnostics( ...
    canonical.DataPortSymbols, channelEstimate, canonical.OFDMGrid, ...
    channelEstimate, dmrsInd, ...
    sixgr.util.structGet(canonical, "InterferenceCovariance", []), ...
    estimatedNoise);
rx = localRXMergeStructs(rx, resourceDiagnostics);
rx.EqualizedSymbolsForEvidence = canonical.LayerSymbols;
rx.LayerEqualizedSymbolsForEvidence = canonical.LayerSymbols;
rx.LayerEqualizedSymbols = canonical.LayerSymbols;
rx.EqualizedSymbolDomain = "layer";
rx.LayerSymbolOrder = ...
    sixgr.phy.resource.buildSymbolOrderingMap( ...
        carrier,pdschInd,"layer");
rx.DemapperLLRCount = sum(codewordLLRCount);
rx.RateRecoveredLLRCount = sum(cellfun(@numel,recLLR));
rx.RateRecoveredLLRCountPerCodeword = ...
    cellfun(@numel,recLLR);
rx.PDSCHRxSymbolsForEvidence = canonical.CodewordSymbols{1};
rx.RecLLR = recLLR{1};
rx.RateRecoveredLLR = recLLR{1};
rx.RecLLRCell = recLLR;
rx.RateRecoveredLLRCell = recLLR;
rx.RateRecoverInfoCell = recInfo;
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx, carrier, dmrsInd, ...
    dmrsAntInd, dmrsSym, dmrsInfo, llrCell, recLLR, recLLR, recInfo, ...
    activeIterations, parityChecks, cbCRCError, ...
    bundle.ReceiverConfig.Algorithm, false, ~logical(canonical.CRCPass));
rx.HARQSoftCombiningInfoPerCodeword = harqInfo;
rx.HARQSoftBuffer = harqSummary.SoftBuffer;
rx.HARQSoftBufferCell = harqSummary.SoftBufferCell;
rx.ChannelEstimateAttempted = true;
rx.ChannelEstimateAvailable = ~isempty(channelEstimate);
usesTrueChannel = logical(sixgr.util.structGet( ...
    canonical.ChannelEstimationInfo,"EstimatorUsesTrueChannel",false));
if usesTrueChannel
    rx.ChannelEstimateSource = "runtime_true_channel_grid_oracle";
    rx.ChannelEstimateMethod = "perfect";
else
    rx.ChannelEstimateSource = "pdsch_dmrs_channel_estimate";
    rx.ChannelEstimateMethod = ...
        char(string(canonical.ChannelEstimationMode));
end
rx.ChannelEstimateEngine = char(string(sixgr.util.structGet( ...
    canonical.ChannelEstimationInfo,"EngineUsed","")));
rx.ChannelEstimateInterpolationMethod = char(string( ...
    sixgr.util.structGet(canonical.ChannelEstimationInfo, ...
        "InterpolationMethod","")));
rx.ChannelEstimateEffectiveConvention = char(string( ...
    sixgr.util.structGet(canonical.ChannelEstimationInfo, ...
        "EffectiveChannelConvention","")));
rx.ChannelEstimatePilotRECount = numel(dmrsUnion);
rx.ChannelEstimatePilotResidualPower = mean( ...
    abs(canonical.DMRSResidual(:)).^2,"omitnan");
rx.ChannelEstimatePilotResidualNMSE_dB = localRXLinearToDb( ...
    double(canonical.Metrics.ChannelEstimateNMSE));
rx.ChannelEstimatePRGAware = ...
    bundle.LegacyPrecoder.NumPRG > 1;
rx.ChannelEstimatePRGCount = ...
    double(bundle.LegacyPrecoder.NumPRG);
rx.ChannelEstimateEstimatedPRGCount = ...
    double(bundle.LegacyPrecoder.NumPRG);
if isempty(bundle.PrecoderBundle)
    rx.ChannelEstimatePRGBundleSizeRB = NaN;
else
    rx.ChannelEstimatePRGBundleSizeRB = ...
        double(bundle.PrecoderBundle.PRGSize);
end
rx.ChannelEstimateExactFlatPRGEstimatorRequested = logical(sixgr.util.structGet( ...
    canonical.ChannelEstimationInfo, "ExactFlatPRGEstimatorRequested", false));
rx.ChannelEstimateExactFlatPRGEstimatorEligible = logical(sixgr.util.structGet( ...
    canonical.ChannelEstimationInfo, "ExactFlatPRGEstimatorEligible", false));
rx.ChannelEstimateExactFlatPRGEstimatorUsed = logical(sixgr.util.structGet( ...
    canonical.ChannelEstimationInfo, "ExactFlatPRGEstimatorUsed", false));
rx.ChannelEstimateExactFlatPRGEstimatorDisabledReason = char(string( ...
    sixgr.util.structGet(canonical.ChannelEstimationInfo, ...
        "ExactFlatPRGEstimatorDisabledReason", "not_requested_or_not_prg")));
% Backward-compatible field aliases for older result readers.  The
% canonical estimator is not AWGN-specific: it is a measured-DMRS LS
% estimator gated to an explicitly flat, rank-one STATIC-MIMO channel.
rx.ChannelEstimateExactAWGNPRGEstimatorRequested = ...
    rx.ChannelEstimateExactFlatPRGEstimatorRequested;
rx.ChannelEstimateExactAWGNPRGEstimatorEligible = ...
    rx.ChannelEstimateExactFlatPRGEstimatorEligible;
rx.ChannelEstimateExactAWGNPRGEstimatorUsed = ...
    rx.ChannelEstimateExactFlatPRGEstimatorUsed;
rx.ChannelEstimateExactAWGNPRGEstimatorDisabledReason = ...
    rx.ChannelEstimateExactFlatPRGEstimatorDisabledReason;
rx.ResourceExtractionAttempted = true;
rx.ResourceExtractionAvailable = ...
    ~isempty(canonical.DataPortSymbols);
rx.DMRSEPREDifference = dmrsPowerInfo;
rx.DMRSDataToDMRSEPREDifference_dB = ...
    double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
rx.DMRSPowerBoost_dB = ...
    double(dmrsPowerInfo.DMRSPowerBoost_dB);
rx.DMRSConfiguredPowerBoost_dB = ...
    double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
rx.DMRSRealizedDataToDMRSEPREDifference_dB = ...
    double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
rx.DMRSAmplitudeScale = ...
    double(dmrsPowerInfo.DMRSAmplitudeScale);
rx.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
rx.EqualizationAttempted = true;
rx.EqualizationAvailable = ~isempty(canonical.LayerSymbols);
rx.DLSCHDecodeAttempted = true;
rx.DLSCHDecodeAvailable = ~isempty(canonical.TransportBlock);
rx.LLRAvailable = ~isempty(llr);
rx.LLRFinite = all(isfinite(double(llr(:))));
rx.LLRScaleSource = ...
    "canonical_soft_demapper_noise_variance";
rx.LLRScalingConvention = ...
    "post_equalization_variance_only";
rx.DemapperNoiseVarianceConvention = ...
    "complex_symbol_variance";
rx.DemapperLLRDomain = "rate_matched_codeword";
rx.LLRDoubleWeightingGuard = true;
rx.LLRCSIWeightApplied = false;
rx.LLRCSIWeightStatus = ...
    "not_applied_canonical_single_variance_scaling";
rx.LLRCSIWeightInputKind = "none";
rx.LLRCSIWeightRawMedian = NaN;
rx.LLRCSIWeightMedianBeforeNormalization = NaN;
rx.LLRCSIWeightNormalizationScale = 1;
rx.LLRNoiseVariance = decoderNoise;
rx.LLRNoiseVarianceDomain = ...
    "unit_constellation_soft_demapper_input";
rx.LLRNoiseVarianceSource = "canonical_pdsch_soft_demapper";
rx.NoiseVarianceUnit = "normalized_complex_power";
rx.NoiseVarianceNormalization = ...
    "native_ofdm_grid_then_unit_constellation_equalizer_domains";
rx.SINRComputationMethod = "mmse";
rx.CodewordLLR = llr;
rx.DLSCHCodewordLLR = llr;
rx.CodewordLLRCell = llrCell;
rx.DLSCHCodewordLLRCell = llrCell;
rx.CodewordLLRInfo = struct( ...
    "NumCodewords",nCodewords, ...
    "CountPerCodeword",codewordLLRCount);
rx.LLRCSIInfoPerCodeword = repmat({struct( ...
    "Applied",false, ...
    "Convention","post_equalization_variance_only")}, ...
    1,nCodewords);
rx.BaseGraph = double(layouts{1}.BaseGraph);
rx.BaseGraphPerCodeword = cellfun( ...
    @(x) double(x.BaseGraph),layouts);
rx.DecodedCodeBlocks = decodedBlocks{1};
rx.DecodedCodeBlocksCell = decodedBlocks;
rx.ActiveIterations = activeIterations;
rx.ParityChecks = parityChecks;
rx.CodeBlockCRCError = cbCRCError;
rx.ChannelEstimate = channelEstimate;
rx.ChannelEstimation = canonical.ChannelEstimationInfo;
rx.RxGrid = canonical.OFDMGrid;
rx.Carrier = carrier;
rx.DMRSIndices = dmrsInd;
rx.DMRSSymbols = dmrsSym;
rx.PDSCH = pdsch;
pdschInfo = localRXMergeStructs(pdschInfo,kernelInfo);
rx.PDSCHInfo = pdschInfo;
rx.DMRSAntennaIndices = dmrsAntInd;
rx.PDSCHAntennaIndices = pdschAntInd;
rx.PDSCHIndices = pdschInd;
csirsReceiverPipelineTic = tic;
[csirsInd, csirsSym, csirsInfo, csirsObservation] = ...
    localObserveCSIRSRuntimeResource( ...
    carrier, cfg, canonical.OFDMGrid, opt, canonical.OFDMInfo);
rx.CSIRSIndices = csirsInd;
rx.CSIRSSymbols = csirsSym;
rx.CSIRSInfo = csirsInfo;
rx.CSIRS = opt.CSIRSConfig;
rx.PTRSIndices = ptrsInd;
rx.PTRSSymbols = ptrsSym;
rx.PTRSAntennaIndices = ptrsAntInd;
rx.PTRSAntennaSymbols = [];
rx.PTRSInfo = canonical.PTRSCorrection;
rx.CPECorrectionInfo = canonical.PTRSCorrection;
csirsChannelEstimationTic = tic;
[csirsHest, csirsNoiseVar, csirsEstimateInfo] = ...
    localEstimateCSIRSChannelForPMI( ...
    carrier, canonical.OFDMGrid, csirsInd, csirsSym, csirsInfo, ...
    cfg, logical(sixgr.util.structGet(cfg, "run.strictMode", false)), ...
    string(sixgr.util.structGet(cfg, "channel.model", "AWGN")), nPorts);
csirsChannelEstimationLatency_ms = 1e3 * toc(csirsChannelEstimationTic);
rx.CSIRSChannelEstimate = csirsHest;
rx.CSIRSNoiseVar = csirsNoiseVar;
rx.CSIRSChannelEstimation = csirsEstimateInfo;
rx.SelectedCSIRS = localSelectedCSIRSConfig( ...
    opt.CSIRSConfig, csirsInfo, csirsEstimateInfo);
rx.CSIChannelEstimateForPMI = csirsHest;
rx.CSIChannelNoiseVarForPMI = csirsNoiseVar;
rx.CSIChannelEstimateSource = string(sixgr.util.structGet( ...
    csirsEstimateInfo, "Source", "not_observed"));
if strlength(rx.CSIChannelEstimateSource) == 0
    rx.CSIChannelEstimateSource = "not_observed";
end
[csiMeasurementState, csiMeasurementInfo] = ...
    localBuildCSIMeasurementState(cfg, carrier, csirsHest, ...
    csirsNoiseVar, csirsEstimateInfo, canonical);
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
csirsObservation = localRelabelNormalizedCSIRSPower( ...
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
rx.CSI = localCalibrationCSI(canonical);
rx.EqualizerInfo = canonical.EqualizationInfo;
rx.InterferenceCovariance = sixgr.util.structGet( ...
    canonical, "InterferenceCovariance", []);
rx.InterferenceCovarianceInfo = rintInfo;
rx.PrecodeInfo = bundle.LegacyPrecoder;
rx.EqualizedSymbols = canonical.LayerSymbols;
rx.PDSCHRxSymbols = canonical.CodewordSymbols{1};
rx.MeasuredCodeBlockCRCCount = ...
    nnz(cellfun(@(x) double(x.NumCodeBlocks),layouts) > 1);
if rx.MeasuredCodeBlockCRCCount == 0
    rx.MeasuredCodeBlockCRCFailureRate = NaN;
else
    rx.MeasuredCodeBlockCRCFailureRate = ...
        mean(double(cbCRCError(:)));
end
rx.MeasuredCodeBlockDecodeCount = sum(cellfun( ...
    @(x) double(x.NumCodeBlocks),layouts));
rx.MeasuredCodeBlockDecodeErrorCount = ...
    sum(double(cbCRCError(:)));
rx.MeasuredCodeBlockDecodeFailureRate = ...
    rx.MeasuredCodeBlockDecodeErrorCount ...
    / max(rx.MeasuredCodeBlockDecodeCount,1);
rx.MeasuredCodeBlockDecodeErrorVector = ...
    "[" + strjoin(string(double(cbCRCError(:).')), " ") + "]";
strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
strictEvidence = sixgr.phy.dl.validatePDSCHReceiverEvidence( ...
    rx, "StrictMode", strictMode);
rx.StrictReceiverEvidenceOk = logical( ...
    strictEvidence.StrictReceiverEvidenceOk);
rx.StrictOk = logical(strictEvidence.StrictOk);
rx.TruthStatus = char(string(strictEvidence.TruthStatus));
rx.SINRValidationStatus = char(string( ...
    strictEvidence.SINRValidationStatus));
rx.SINRValidationReason = char(string( ...
    strictEvidence.SINRValidationReason));
rx.PostEqSINRReceiverDerived = logical( ...
    strictEvidence.PostEqSINRReceiverDerived);
rx.PostEqSINRAvailable = logical(strictEvidence.PostEqSINRAvailable);
rx.ConfiguredSNRLikeSourceRejected = logical( ...
    strictEvidence.ConfiguredSNRLikeSourceRejected);
if strictMode && ~logical(strictEvidence.StrictReceiverEvidenceOk)
    rx.ReceiverUsable = false;
    rx.DecodeUsable = false;
    if strlength(string(rx.FailureReason)) == 0
        rx.FailureReason = char(string(strictEvidence.FailureReason));
    else
        rx.FailureReason = char(string(rx.FailureReason) + "|" ...
            + string(strictEvidence.FailureReason));
    end
end
if hasPHYGrant
    rx.PHYGrant = phyGrant;
end

info = struct( ...
    "FacadeContractVersion","PDSCH_RxCompatibilityFacade/v3", ...
    "CanonicalDelegation",true, ...
    "DelegationTarget","sixgr.pdsch.PDSCHReceiver", ...
    "ExecutionProfile",char(executionProfile), ...
    "CarrierInfo",carrierInfo, ...
    "OFDM",canonical.OFDMInfo, ...
    "PDSCHInfo",pdschInfo, ...
    "Precoding",bundle.LegacyPrecoder, ...
    "ChannelEstimation",canonical.ChannelEstimationInfo, ...
    "DMRS",localRXCalibrationDMRSInfo(dmrsPowerInfo), ...
    "DMRSEPREDifference",dmrsPowerInfo, ...
    "PTRS",canonical.PTRSCorrection, ...
    "CPECorrection",canonical.PTRSCorrection, ...
    "NoiseVariance",struct( ...
        "Source","canonical_pdsch_receiver", ...
        "Value",decoderNoise), ...
    "OFDMNoiseTransform",sixgr.util.structGet( ...
        canonical.OFDMInfo,"NoiseTransform",struct()), ...
    "PreEqualizationNoiseVariance",estimatedNoise, ...
    "PostEqualizationNoiseVariance",decoderNoise, ...
    "Equalizer",canonical.EqualizationInfo, ...
    "CodingLayout",layouts{1}, ...
    "CodingLayouts",{layouts}, ...
    "CodewordLayerMapping",mapping, ...
    "CodewordLLRInfo",rx.CodewordLLRInfo, ...
    "DecodedBitLineagePerCodeword",{lineage}, ...
    "RateRecoverPerCodeword",{recInfo}, ...
    "DecodePerCodeword",{decoded}, ...
    "StrictReceiverEvidence",strictEvidence, ...
    "ResourcePlan",bundle.ResourcePlan, ...
    "StageTrace",canonical.StageTrace, ...
    "Source",char(ternaryPDSCHRXProfile(isSchedulerTruth, ...
        "canonical_pdsch_receiver_scheduler_truth_facade", ...
        "canonical_pdsch_receiver_calibration_facade")));
end

function value = ternaryPDSCHRXProfile(condition, trueValue, falseValue)
if condition
    value = string(trueValue);
else
    value = string(falseValue);
end
end

function indices = localCalibrationRXPortIndices(baseZero,nPorts,plane)
indices = double(baseZero(:)) + 1 ...
    + plane .* (0:(nPorts - 1));
end

function plans = localRequireCalibrationCodingPlans(raw,count)
if isempty(raw)
    error("sixgr:pdsch:CalibrationReceiverMissingCodingPlan", ...
        ("Calibration RX requires the immutable DLSCHCodingPlan " + ...
        "object(s) produced by the matching transmitter."));
end
if isa(raw,"sixgr.pdsch.DLSCHCodingPlan")
    plans = num2cell(reshape(raw,1,[]));
elseif iscell(raw)
    plans = reshape(raw,1,[]);
else
    error("sixgr:pdsch:CalibrationReceiverInvalidCodingPlan", ...
        "CodingPlan must contain immutable DLSCHCodingPlan objects.");
end
if numel(plans) ~= count
    error("sixgr:pdsch:CalibrationReceiverCodingPlanCountMismatch", ...
        "Calibration RX requires exactly %d coding plan(s).",count);
end
for cw = 1:count
    plan = plans{cw};
    if ~isa(plan,"sixgr.pdsch.DLSCHCodingPlan") ...
            || ~isscalar(plan) || ~logical(plan.Immutable) ...
            || strlength(string(plan.PlanID)) == 0 ...
            || strlength(string(plan.CodingLayoutHash)) == 0
        error("sixgr:pdsch:CalibrationReceiverInvalidCodingPlan", ...
            ("Calibration RX coding plan %d must be one immutable " + ...
            "DLSCHCodingPlan with a nonempty PlanID and layout hash."), ...
            cw-1);
    end
end
end

function localAssertOptionalCalibrationPlanVector( ...
        raw,expected,identifier,name)
if isempty(raw)
    return;
end
actual = double(raw(:).');
expected = double(expected(:).');
if numel(actual) ~= numel(expected) || any(~isfinite(actual)) ...
        || any(abs(actual-expected) > 1e-12)
    error(identifier, ...
        ("Calibration RX %s must exactly match the supplied immutable " + ...
        "coding plan(s)."),name);
end
end

function localAssertCalibrationCodingLayoutMatchesPlan(raw,plans)
if isempty(raw) || (isstruct(raw) && isscalar(raw) ...
        && isempty(fieldnames(raw)))
    return;
end
if iscell(raw)
    supplied = reshape(raw,1,[]);
elseif isstruct(raw) && numel(raw) > 1
    supplied = reshape(num2cell(raw),1,[]);
else
    supplied = {raw};
end
if numel(supplied) ~= numel(plans)
    error("sixgr:pdsch:CalibrationCodingLayoutCountMismatch", ...
        ["Legacy CodingLayout evidence contains %d codeword(s); the " ...
        "canonical resource plan contains %d."], ...
        numel(supplied),numel(plans));
end
for cw = 1:numel(plans)
    actual = supplied{cw};
    if ~(isstruct(actual) && isscalar(actual))
        error("sixgr:pdsch:CalibrationCodingLayoutInvalid", ...
            "CodingLayout codeword %d must be a scalar struct.",cw-1);
    end
    expected = plans{cw}.toCodingLayout();
    actualHash = string(sixgr.util.structGet( ...
        actual,"CodingLayoutHash",""));
    expectedHash = string(sixgr.util.structGet( ...
        expected,"CodingLayoutHash",""));
    if strlength(strtrim(actualHash)) > 0
        if actualHash ~= expectedHash
            error("sixgr:pdsch:CalibrationCodingLayoutMismatch", ...
                ["CodingLayout codeword %d hash '%s' differs from the " ...
                "canonical plan hash '%s'."], ...
                cw-1,actualHash,expectedHash);
        end
        continue;
    end
    actualA = double(sixgr.util.structGet(actual,"A", ...
        sixgr.util.structGet(actual,"TransportBlockSize",NaN)));
    actualE = double(sixgr.util.structGet(actual,"E", ...
        sixgr.util.structGet(actual,"RateMatchedBitCount",NaN)));
    actualRate = double(sixgr.util.structGet( ...
        actual,"TargetCodeRate",NaN));
    actualRV = double(sixgr.util.structGet(actual,"RV",NaN));
    actualLayers = double(sixgr.util.structGet( ...
        actual,"NumLayers",NaN));
    actualModulation = upper(strtrim(string( ...
        sixgr.util.structGet(actual,"Modulation",""))));
    requiredPresent = all(isfinite([actualA,actualE,actualRate, ...
        actualRV,actualLayers])) ...
        && strlength(actualModulation) > 0;
    if ~requiredPresent
        error("sixgr:pdsch:CalibrationCodingLayoutIncomplete", ...
            ["CodingLayout codeword %d must carry CodingLayoutHash or " ...
            "the exact A/E/rate/RV/modulation/layer contract."],cw-1);
    end
    mismatch = actualA ~= double(expected.A) ...
        || actualE ~= double(expected.E) ...
        || abs(actualRate-double(expected.TargetCodeRate)) > 1e-12 ...
        || actualRV ~= double(expected.RV) ...
        || actualLayers ~= double(expected.NumLayers) ...
        || actualModulation ~= upper(strtrim(string(expected.Modulation)));
    if mismatch
        error("sixgr:pdsch:CalibrationCodingLayoutMismatch", ...
            "CodingLayout codeword %d differs from the canonical plan.", ...
            cw-1);
    end
end
end

function [decoded,recLLR,recInfo,blocks,iterations,parity, ...
        cbError,lineage] = localCanonicalRXDecodeEvidence( ...
        decode,nCodewords)
if nCodewords == 1
    decoded = {decode};
else
    decoded = decode.Codewords;
end
recLLR = cell(1,nCodewords);
recInfo = cell(1,nCodewords);
blocks = cell(1,nCodewords);
lineage = cell(1,nCodewords);
iterations = [];
parity = [];
cbError = [];
for cw = 1:nCodewords
    item = decoded{cw};
    recLLR{cw} = double(item.HARQCombinedLLR);
    recInfo{cw} = item.RateRecoveryInfo;
    blocks{cw} = int8(item.DecodedCodeBlocks);
    iterations = [iterations, ...
        double(item.ActiveIterations(:).')]; %#ok<AGROW>
    parity = [parity, ...
        double(item.FinalParityChecks(:).')]; %#ok<AGROW>
    cbError = [cbError, ...
        logical(item.CodeBlockCRCError(:).')]; %#ok<AGROW>
    layout = item.CodingLayout;
    lineage{cw} = struct( ...
        "DemapperLLRCount", ...
            double(layout.RateMatchedBitCount), ...
        "RateRecoveredRows", ...
            double(layout.MotherCodeLength), ...
        "RateRecoveredCodeBlocks", ...
            double(layout.NumCodeBlocks), ...
        "Source", ...
            "canonical_dlsch_decoder_immutable_coding_plan");
end
end

function value = localCalibrationCSI(canonical)
count = numel(canonical.LayerSymbols);
sinr = double(canonical.Metrics. ...
    MeasuredPostEqualizationSINRdBPerLayer);
reliability = 1 ./ (1 + 10.^(-mean(sinr,"omitnan")/10));
value = reliability .* ones(count,1);
end

function value = localRXLinearToDb(value)
if ~(isscalar(value) && isfinite(value) && value >= 0)
    value = NaN;
elseif value == 0
    value = -Inf;
else
    value = 10*log10(value);
end
end

function value = localRXMergeStructs(primary,secondary)
value = primary;
names = fieldnames(secondary);
for idx = 1:numel(names)
    if ~isfield(value,names{idx})
        value.(names{idx}) = secondary.(names{idx});
    end
end
end

function info = localRXCalibrationDMRSInfo(powerInfo)
info = struct( ...
    "DataToDMRSEPREDifference_dB", ...
        double(powerInfo.DataToDMRSEPREDifference_dB), ...
    "DMRSPowerBoost_dB", ...
        double(powerInfo.DMRSPowerBoost_dB), ...
    "ConfiguredDMRSPowerBoost_dB", ...
        double(powerInfo.ConfiguredDMRSPowerBoost_dB), ...
    "RealizedDataToDMRSEPREDifference_dB", ...
        double(powerInfo.RealizedDataToDMRSEPREDifference_dB), ...
    "DMRSAmplitudeScale",double(powerInfo.DMRSAmplitudeScale), ...
    "DMRSPowerScale",double(powerInfo.DMRSPowerScale), ...
    "EPREConfigSource",char(string(powerInfo.Source)), ...
    "EPREScalePolicy",char(string(powerInfo.ScalePolicy)));
end

function [rx, info] = localDelegateCanonicalPDSCHReceiver( ...
        rxWaveform, cfg, opt, executionProfile, hasPHYGrant)
assignment = opt.Assignment;
if isempty(opt.ResourcePlan)
    error("sixgr:pdsch:MissingResourcePlan", ...
        "Assignment-owned PDSCH reception requires PDSCHResourcePlan.");
end
if ~isa(opt.Carrier, "nrCarrierConfig")
    error("sixgr:pdsch:MissingCanonicalCarrier", ...
        "Assignment-owned PDSCH reception requires an explicit nrCarrierConfig.");
end
if ~isa(opt.ReferenceSignalConfig, ...
        "sixgr.pdsch.PDSCHReferenceSignalConfig")
    error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
        ["Assignment-owned PDSCH reception requires an immutable " ...
        "PDSCHReferenceSignalConfig."]);
end
if isempty(fieldnames(opt.ReceiverConfig))
    error("sixgr:pdsch:IncompleteReceiverConfiguration", ...
        "Assignment-owned PDSCH reception requires explicit receiver configuration.");
end
if hasPHYGrant
    error("sixgr:pdsch:ConfiguredGrantNotAllowed", ...
        "A frozen PHYGrant cannot replace immutable assignment ownership.");
end
legacyOverridesPresent = ~isempty(opt.PDSCH) ...
    || ~isempty(opt.PDSCHIndices) ...
    || ~isempty(opt.TransportBlockSize) ...
    || ~isempty(opt.TargetCodeRate) ...
    || ~isempty(opt.RV) ...
    || ~isempty(opt.MaxIterations) ...
    || ~isempty(opt.Algorithm) ...
    || ~isempty(opt.PrecodingMatrix) ...
    || localRXFacadeHasStructOrCell(opt.CodingLayout) ...
    || ~isempty(opt.HARQSoftBufferLLR) ...
    || localRXFacadeHasStructOrCell(opt.HARQSoftBufferLayout);
if legacyOverridesPresent
    error("sixgr:pdsch:LegacyOverrideNotAllowed", ...
        "Assignment-owned PDSCH reception rejects legacy PDSCH, coding, rate, RV, TBS, precoder-matrix, and soft-buffer overrides.");
end
if ~isempty(opt.NoiseVar)
    error("sixgr:pdsch:LegacyOverrideNotAllowed", ...
        "Canonical receiver noise variance belongs in ReceiverConfig.");
end
if logical(opt.CompactOutput)
    error("sixgr:pdsch:CompactStrictOutputNotAllowed", ...
        "Canonical assignment-owned PDSCH reception must retain its complete stage evidence.");
end
if assignment.Profile ~= executionProfile
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        "Assignment profile '%s' does not match requested '%s'.", ...
        assignment.Profile, executionProfile);
end
assignmentDigest = assignment.validateForExecution();

sharedTiming = ~isempty(opt.TimingSearchWindowSamples);
if sharedTiming
    % Derive the acquisition reference from receiver-owned allocation and
    % immutable RS policy, not cfg's initial PRBs/NSCID or a TX reference.
    referenceData = opt.ReferenceSignalConfig.toStruct();
    opt.ReferenceSignalConfig.validateForExecution();
    pdsch = sixgr.pdsch.PDSCHConfigMaterializer.fromAssignment(assignment,referenceData);
    absoluteSlot = double(opt.Carrier.NFrame)*double(opt.Carrier.SlotsPerFrame) + ...
        double(opt.Carrier.NSlot);
    assert(absoluteSlot==double(assignment.get("PDSCHAbsoluteSlot")), ...
        'sixgr:phy:dl:AssignmentReceiveClockMismatch', ...
        'Capture acquisition and immutable PDSCH assignment must use the same absolute slot.');
    % The existing shared acquisition operates on the native IFFT clock.
    % Never silently apply its sample counts to a resampled capture.
    clockArgs = referenceData.OFDMOptions;
    clockNames = lower(string(clockArgs(1:2:end)));
    clockArgs(reshape([2*find(clockNames=="cyclicprefixfraction")-1; ...
        2*find(clockNames=="cyclicprefixfraction")],1,[])) = [];
    clockInfo = nrOFDMInfo(opt.Carrier,clockArgs{:});
    nativeInfo = nrOFDMInfo(opt.Carrier);
    assert(clockInfo.Nfft==nativeInfo.Nfft && clockInfo.SampleRate==nativeInfo.SampleRate && ...
        isequal(clockInfo.SymbolPhases,nativeInfo.SymbolPhases), ...
        'sixgr:phy:dl:AssignmentReceiveSampleClockUnsupported', ...
        'Shared assignment acquisition requires the native OFDM sample clock and symbol phase convention; custom captures need a matching acquisition contract.');
    [rxWaveform,trackingCorrection,timingResolution,syncState] = ...
        localApplyCalibrationReceiverTracking(rxWaveform,opt.Carrier,pdsch,cfg,opt);
    [measurementGrid,measurementOFDMInfo,measurementStatus] = ...
        localPreparePhysicalMeasurementGrid(opt.PhysicalMeasurementWaveform, ...
        opt.Carrier,trackingCorrection,timingResolution,referenceData.OFDMOptions{:});
    if ~isempty(opt.PhysicalMeasurementWaveform)
        assert(measurementStatus=="available_exact_pre_front_end_grid", ...
            'sixgr:phy:dl:InvalidAssignmentPhysicalMeasurement', ...
            'A supplied physical-plane capture must produce its actual aligned grid.');
    end
end

canonical = sixgr.pdsch.PDSCHReceiver( ...
    rxWaveform, assignment, opt.ResourcePlan, opt.Carrier, ...
    opt.ReferenceSignalConfig, opt.ReceiverConfig, ...
    "CodingPlans", opt.CodingPlan, ...
    "PrecoderBundle", opt.PrecoderBundle, ...
    "IntegrationContext", opt.IntegrationContext, ...
    "HARQManager", opt.HARQManager, ...
    "UseMexLDPC",logical(sixgr.util.structGet( ...
        cfg,"phy.ldpc.useMexBatchDecode",false)), ...
    "EnablePTRSCPECorrection", logical(sixgr.util.structGet( ...
        cfg, "phy.pdsch.ptrs.enableCPECorrection", false)), ...
    "EnableDMRSResidualPostEqSINRBound", logical(sixgr.util.structGet( ...
        cfg, "phy.pdsch.measurements.dmrsResidualPostEqSINRBoundEnabled", false)), ...
    "EnableDecisionDirectedPostEqSINRBound", logical(sixgr.util.structGet( ...
        cfg, "phy.pdsch.measurements.decisionDirectedPostEqSINRBoundEnabled", false)));
rx = canonical;
rx.FacadeContractVersion = "PDSCH_RxCompatibilityFacade/v2";
rx.CanonicalDelegation = true;
rx.DelegationTarget = "sixgr.pdsch.PDSCHReceiver";
rx.ExecutionProfile = char(executionProfile);
rx.StrictSchedulingOwnership = any(executionProfile == ...
    ["connected_strict","sps_strict","ra_si_strict"]);
rx.SchedulingOwnership = "immutable_pdsch_scheduling_assignment";
rx.AssignmentValidationDigest = assignmentDigest;
rx.IntegrationBinding = canonical.IntegrationBinding;
rx.Ok = logical(canonical.CRCPass);
rx.TBCRCPass = logical(canonical.CRCPass);
if sharedTiming
    rx.ReceiveTiming = timingResolution.ReceiveTiming;
    rx.TimingOffset = double(syncState.RawTimingEstimate_samples);
    rx.RawTimingEstimate_samples = rx.TimingOffset;
    rx.KnownTimingDelay_samples = double(syncState.KnownTimingDelay_samples);
    rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
    rx.TimingEstimateUsed = logical(timingResolution.EstimateUsed);
    rx.TimingEstimateSource = string(timingResolution.Source);
    rx.TimingEstimateStatus = string(timingResolution.Status);
    rx.TimingEstimateApplicationPolicy = string(timingResolution.ApplicationPolicy);
    rx.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
    rx.SynchronizationState = syncState;
    rx.ReceiverTrackingCorrection = trackingCorrection;
    rx.EstimatedCFO_Hz = double(trackingCorrection.EstimatedCFO_Hz);
    rx.CFOCorrectionApplied = logical(trackingCorrection.CFOCorrectionApplied);
    rx.CFOCorrectionApplied_Hz = double(trackingCorrection.CFOCorrectionApplied_Hz);
    rx.CFOEstimateSource = string(trackingCorrection.Source);
    rx.CFOEstimateStatus = string(trackingCorrection.Status);
    rx.ResidualCFOEstimate_Hz = double(trackingCorrection.ResidualCFOEstimate_Hz);
    rx.PhysicalMeasurementGrid = measurementGrid;
    rx.PhysicalMeasurementOFDMInfo = measurementOFDMInfo;
    rx.PhysicalMeasurementGridStatus = measurementStatus;
    rx.PhysicalMeasurementReferencePlane = string(opt.PhysicalMeasurementReferencePlane);
    rx.PhysicalMeasurementSource = string(opt.PhysicalMeasurementSource);
end
rx.PTRSConfiguredEnabled = logical(opt.ReferenceSignalConfig.get("EnablePTRS"));
rx.PTRSCPECorrectionConfigured = logical(sixgr.util.structGet( ...
    cfg, "phy.pdsch.ptrs.enableCPECorrection", false));
rx.PTRSCPECorrectionApplied = logical(sixgr.util.structGet( ...
    canonical.PTRSCorrection, "Applied", false));
rx.PTRSCPECorrectionEnabled = rx.PTRSCPECorrectionConfigured;
rx.PTRSCPECorrectionSymbols = double(sixgr.util.structGet( ...
    canonical.PTRSCorrection, "CorrectedSymbolCount", 0));
rx.PTRSMeanCPE_deg = double(sixgr.util.structGet( ...
    canonical.PTRSCorrection, "MeanCPE_deg", NaN));
rx.PTRSCPECorrectionReason = char(string(sixgr.util.structGet( ...
    canonical.PTRSCorrection, "NAReason", "")));
rx.PTRSCPECorrectionStatus = char(string(sixgr.util.structGet( ...
    canonical.PTRSCorrection, "Status", "")));
rx.PTRSReceiverEvidenceSource = ...
    "sixgr.pdsch.PDSCHReceiver.PTRSCorrection";

info = struct( ...
    "FacadeContractVersion", "PDSCH_RxCompatibilityFacade/v2", ...
    "CanonicalDelegation", true, ...
    "DelegationTarget", "sixgr.pdsch.PDSCHReceiver", ...
    "ExecutionProfile", executionProfile, ...
    "AssignmentValidationDigest", assignmentDigest, ...
    "IntegrationBinding", canonical.IntegrationBinding, ...
    "ResourcePlan", opt.ResourcePlan, ...
    "StageTrace", canonical.StageTrace, ...
    "OFDM", canonical.OFDMInfo, ...
    "Source", "canonical_pdsch_receiver_facade");
if sharedTiming
    info.ReceiveTiming = rx.ReceiveTiming;
    info.SynchronizationState = rx.SynchronizationState;
    info.PhysicalMeasurementGridStatus = rx.PhysicalMeasurementGridStatus;
end
end

function tf = localRXFacadeHasStructOrCell(value)
if isstruct(value)
    tf = ~isempty(fieldnames(value));
else
    tf = ~isempty(value);
end
end

function profile = localResolveRXExecutionProfile(cfg, explicitProfile, assignment)
profile = lower(strtrim(string(explicitProfile)));
if strlength(profile) == 0
    profile = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.pdsch.executionProfile", ...
        sixgr.util.structGet(cfg, "run.pdschExecutionProfile", "")))));
end
if strlength(profile) == 0 && ...
        isa(assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    profile = assignment.Profile;
end
if strlength(profile) == 0
    error("sixgr:pdsch:MissingExecutionProfile", ...
        ["PDSCH reception requires an explicit ExecutionProfile, " ...
        "cfg.phy.pdsch.executionProfile, cfg.run.pdschExecutionProfile, " ...
        "or an immutable assignment-owned profile."]);
end
if ~any(profile == ...
        ["connected_strict","sps_strict","ra_si_strict","scheduler_truth","phy_calibration"])
    error("sixgr:pdsch:UnsupportedExecutionProfile", ...
        "Unsupported PDSCH execution profile '%s'.", profile);
end
end

function [Hest, nVar, estInfo] = localEstimatePRGBundledPDSCHChannel( ...
        carrier, pdsch, rxGrid, dmrsInd, dmrsSym, dmrsInfo, prec, cfg, ...
        useFastChEstMex, strictMode, channelModelToken, numTxPorts)
% Estimate a discontinuously precoded effective channel independently in
% each PRG. A whole-grid interpolation is not valid at a PRG boundary:
% even when the physical channel is flat, H*W changes discontinuously with
% the PRG precoder. Each estimate still comes exclusively from received
% DM-RS evidence and uses the ordinary resource-selective truth estimator.
[prgSet, prgBundleSizeRB, partitionInfo] = ...
    localResolvePDSCHPRGPartition(carrier, prec, cfg);
estimationMethod = localResolveChannelEstimationMethod(cfg);
exactAWGNPolicy = localResolveExactAWGNPRGEstimatorPolicy( ...
    cfg, channelModelToken, prec, estimationMethod);

K = size(rxGrid, 1);
L = size(rxGrid, 2);
nPRG = round(double(prec.NumPRG));
activePRB = round(double(pdsch.PRBSet(:))) + 1;
if isempty(activePRB) || any(~isfinite(activePRB)) || ...
        any(activePRB < 1 | activePRB > numel(prgSet))
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:BadPRBSet", ...
        "PDSCH PRBSet must resolve to carrier-relative PRBs in [0,%d].", ...
        numel(prgSet) - 1);
end
activePRG = unique(double(prgSet(activePRB)), "stable");

Hest = [];
estimatedMask = false(1, nPRG);
perPRGInfo = cell(1, nPRG);
perPRGNoiseVar = NaN(1, nPRG);
perPRGPilotCount = zeros(1, nPRG);
perPRGPilotResidualPower = NaN(1, nPRG);
perPRGPilotSignalPower = NaN(1, nPRG);

for ii = 1:numel(activePRG)
    prg = activePRG(ii);
    prb = find(double(prgSet(:)) == prg);
    subcarriers = reshape((12 .* (prb(:) - 1)) + (1:12), [], 1);
    [prgDMRSInd, prgDMRSSym] = localSelectPDSCHPRGReferences( ...
        dmrsInd, dmrsSym, subcarriers, K, L, max(1, double(prec.NumLayers)));
    if isempty(prgDMRSInd)
        error("sixgr:phy:dl:PDSCHPRGChannelEstimate:MissingPRGDMRS", ...
            ["Active PDSCH PRG %d has no DM-RS evidence. Truth reception " ...
            "cannot interpolate an effective channel from another precoder bundle."], ...
            prg);
    end

    if logical(exactAWGNPolicy.Use)
        % This is not a scalar full-grid shortcut: it estimates one
        % independent effective coefficient per PRG and receive antenna,
        % then fills only that PRG. It is exact only for explicit flat
        % AWGN with one layer and therefore fails closed outside that gate.
        [hPRG, nVarPRG, infoPRG] = localEstimateExactAWGNPRGChannel( ...
            rxGrid, prgDMRSInd, prgDMRSSym, subcarriers, ...
            channelModelToken, prec, prg);
    else
        [hPRG, nVarPRG, infoPRG] = sixgr.phy.rx.channelEstimate( ...
            carrier, rxGrid, prgDMRSInd, prgDMRSSym, ...
            "CDMLengths", sixgr.util.structGet(dmrsInfo, "CDMLengths", []), ...
            "UseFastMex", false, ...
            "StrictMode", strictMode, ...
            "ChannelModel", channelModelToken, ...
            "ExpectedTxPorts", numTxPorts, ...
            "Method", estimationMethod, ...
            "Config", cfg, ...
            "ContextLabel", "PDSCH_Rx_PRG_" + string(prg));
    end

    if isempty(Hest)
        Hest = zeros(size(hPRG), "like", hPRG);
    elseif ~isequal(size(Hest), size(hPRG))
        error("sixgr:phy:dl:PDSCHPRGChannelEstimate:EstimatorShapeMismatch", ...
            "PRG %d channel-estimate shape %s does not match %s.", ...
            prg, mat2str(size(hPRG)), mat2str(size(Hest)));
    end
    Hest(subcarriers, :, :, :) = hPRG(subcarriers, :, :, :);
    estimatedMask(prg) = true;
    perPRGInfo{prg} = infoPRG;
    perPRGNoiseVar(prg) = double(nVarPRG);
    perPRGPilotCount(prg) = double(sixgr.util.structGet( ...
        infoPRG, "PilotRECount", numel(prgDMRSInd)));
    perPRGPilotResidualPower(prg) = double(sixgr.util.structGet( ...
        infoPRG, "PilotResidualPower", NaN));
    perPRGPilotSignalPower(prg) = double(sixgr.util.structGet( ...
        infoPRG, "PilotSignalPower", NaN));
end

if any(~estimatedMask(activePRG))
    missing = activePRG(~estimatedMask(activePRG));
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:IncompletePRGEstimate", ...
        "No truth channel estimate was produced for active PDSCH PRG(s) %s.", ...
        mat2str(missing));
end

nVar = localWeightedFiniteMean(perPRGNoiseVar, perPRGPilotCount);
if ~isfinite(nVar)
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:NoiseVarianceUnavailable", ...
        "Per-PRG channel estimation did not produce a finite noise variance.");
end

firstPRG = activePRG(1);
estInfo = perPRGInfo{firstPRG};
pilotResidualPower = localWeightedFiniteMean( ...
    perPRGPilotResidualPower, perPRGPilotCount);
pilotSignalPower = localWeightedFiniteMean( ...
    perPRGPilotSignalPower, perPRGPilotCount);
pilotResidualNMSEdB = NaN;
if isfinite(pilotResidualPower) && isfinite(pilotSignalPower)
    pilotResidualNMSEdB = 10 .* log10(max( ...
        pilotResidualPower ./ max(pilotSignalPower, eps), eps));
end
[pilotMask, pilotLinear] = localPDSCHReferenceMask(dmrsInd, K, L, ...
    max(1, double(prec.NumLayers)));

estInfo.ContextLabel = "PDSCH_Rx_PRG_stitched";
if logical(exactAWGNPolicy.Use)
    estInfo.EngineUsed = "exact_awgn_ls_per_prg_stitched";
    interpolationMethod = "constant_within_each_prg_from_prg_local_dmrs_ls";
else
    estInfo.EngineUsed = "nrChannelEstimate_per_prg_stitched";
    interpolationMethod = "within_prg_only:" + string( ...
        sixgr.util.structGet(estInfo, "InterpolationMethod", "nrChannelEstimate_default"));
end
estInfo.HestSize = size(Hest);
estInfo.NoiseVar = double(nVar);
estInfo.PilotMask = pilotMask;
estInfo.PilotMaskLinearIndices = double(pilotLinear(:));
estInfo.PilotRECount = double(sum(perPRGPilotCount(activePRG)));
estInfo.PilotResidualPower = double(pilotResidualPower);
estInfo.PilotSignalPower = double(pilotSignalPower);
estInfo.PilotResidualNMSE_dB = double(pilotResidualNMSEdB);
estInfo.InterpolationMethod = interpolationMethod;
estInfo.EffectiveChannelConvention = ...
    "resource_grid_rx_antenna_by_dmrs_port_after_precoding_stitched_within_each_prg";
estInfo.PRGAware = true;
estInfo.PRGCount = double(nPRG);
estInfo.ActivePRG = double(activePRG(:).');
estInfo.EstimatedPRGCount = double(nnz(estimatedMask));
estInfo.EstimatedPRGMask = logical(estimatedMask);
estInfo.PRGBundleSizeRB = double(prgBundleSizeRB);
estInfo.PRGSet = double(prgSet(:).');
estInfo.PRGPartitionSource = char(string(partitionInfo.Source));
estInfo.PRGBundleSizeCandidatesRB = double(partitionInfo.BundleSizeCandidatesRB);
estInfo.PerPRGNoiseVar = double(perPRGNoiseVar);
estInfo.PerPRGPilotRECount = double(perPRGPilotCount);
estInfo.PerPRGPilotResidualPower = double(perPRGPilotResidualPower);
estInfo.PerPRGDetails = perPRGInfo;
estInfo.ExactAWGNPRGEstimatorRequested = logical(exactAWGNPolicy.Requested);
estInfo.ExactAWGNPRGEstimatorEligible = logical(exactAWGNPolicy.Eligible);
estInfo.ExactAWGNPRGEstimatorUsed = logical(exactAWGNPolicy.Use);
estInfo.ExactAWGNPRGEstimatorDisabledReason = char(string(exactAWGNPolicy.DisabledReason));
estInfo.ExactAWGNPRGEstimatorConfigPath = char(string(exactAWGNPolicy.ConfigPath));
estInfo.ExactAWGNPRGCoefficientCount = double(nnz(estimatedMask) .* max(1, size(rxGrid, 3)));
estInfo.ScalarFastPathRequested = logical(useFastChEstMex);
estInfo.ScalarFastPathAllowed = false;
estInfo.ScalarFastPathUsed = false;
estInfo.ScalarFastPathDisabledReason = ...
    "A single full-grid scalar cannot represent a PRG-discontinuous effective channel";
end

function policy = localResolveExactAWGNPRGEstimatorPolicy(cfg, channelModelToken, prec, estimationMethod)
configPath = "phy.pdsch.dmrs.useExactAWGNPRGEstimator";
rawRequested = sixgr.util.structGet(cfg, char(configPath), true);
if ~((islogical(rawRequested) || isnumeric(rawRequested)) && ...
        isscalar(rawRequested) && isfinite(double(rawRequested)))
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorInvalid", ...
        "%s must be a finite logical or numeric scalar.", char(configPath));
end
requested = logical(rawRequested);
explicitFlatAWGN = localIsExplicitFlatChannel(channelModelToken);
singleLayer = round(double(sixgr.util.structGet(prec, "NumLayers", NaN))) == 1;
leastSquares = any(lower(strtrim(string(estimationMethod))) == ...
    ["ls","least_squares","least-squares"]);
eligible = explicitFlatAWGN && singleLayer && leastSquares;

reason = "";
if ~requested
    reason = "disabled_by_config";
elseif ~explicitFlatAWGN
    reason = "requires_explicit_awgn_flat_channel";
elseif ~singleLayer
    reason = "requires_exactly_one_pdsch_layer";
elseif ~leastSquares
    reason = "requires_ls_channel_estimation_method";
end
policy = struct( ...
    "ConfigPath", configPath, ...
    "Requested", logical(requested), ...
    "Eligible", logical(eligible), ...
    "Use", logical(requested && eligible), ...
    "DisabledReason", reason);
end

function [Hest, nVar, info] = localEstimateExactAWGNPRGChannel( ...
        rxGrid, refInd, refSym, subcarriers, channelModelToken, prec, prg)
if ~localIsExplicitFlatChannel(channelModelToken) || ...
        round(double(sixgr.util.structGet(prec, "NumLayers", NaN))) ~= 1
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorIneligible", ...
        ["The exact per-PRG coefficient estimator is restricted to explicit " ...
        "flat AWGN and exactly one PDSCH layer."]);
end
if ~isvector(refInd) || ~isvector(refSym) || numel(refInd) ~= numel(refSym)
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorReferenceShape", ...
        "The one-layer exact AWGN PRG estimator requires aligned vector DM-RS indices and symbols.");
end

rxRef = nrExtractResources(refInd, rxGrid);
ref = refSym(:);
if isvector(rxRef)
    rxRef = rxRef(:);
end
if size(rxRef, 1) ~= numel(ref)
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorReferenceShape", ...
        "Extracted DM-RS observations (%d) do not match reference symbols (%d).", ...
        size(rxRef, 1), numel(ref));
end
validReference = isfinite(real(ref)) & isfinite(imag(ref)) & abs(ref) > eps;
validObservation = all(isfinite(real(rxRef)) & isfinite(imag(rxRef)), 2);
keep = validReference & validObservation;
ref = ref(keep);
rxRef = rxRef(keep, :);
if isempty(ref)
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorNoEvidence", ...
        "PRG %d has no finite nonzero DM-RS observations.", prg);
end

denominator = sum(abs(ref).^2);
if ~(isfinite(denominator) && denominator > 0)
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorNoEvidence", ...
        "PRG %d has zero or non-finite DM-RS reference energy.", prg);
end
h = (conj(ref).' * rxRef) ./ denominator;
residual = rxRef - ref * h;
degreesOfFreedom = numel(residual) - numel(h);
if degreesOfFreedom > 0
    nVar = sum(abs(residual(:)).^2) ./ degreesOfFreedom;
else
    nVar = mean(abs(residual(:)).^2);
end
nVar = double(real(nVar));
if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
    error("sixgr:phy:dl:PDSCHExactAWGNPRGEstimatorNoiseVariance", ...
        "PRG %d produced an invalid pilot-residual noise variance.", prg);
end

K = size(rxGrid, 1);
L = size(rxGrid, 2);
R = max(1, size(rxGrid, 3));
Hest = complex(zeros(K, L, R, "like", rxGrid));
for rr = 1:R
    Hest(subcarriers, :, rr) = cast(h(rr), "like", rxGrid);
end
pilotResidualPower = mean(abs(residual(:)).^2);
pilotSignalPower = mean(abs(ref * h).^2, "all");
pilotResidualNMSEdB = 10 .* log10(max( ...
    double(pilotResidualPower) ./ max(double(pilotSignalPower), eps), eps));

info = struct( ...
    "ContextLabel", "PDSCH_Rx_PRG_" + string(prg), ...
    "ChannelModel", char(string(channelModelToken)), ...
    "ExpectedTxPorts", double(sixgr.util.structGet(prec, "NumPorts", NaN)), ...
    "NumRxAnt", double(R), ...
    "Method", "LS", ...
    "EngineUsed", "exact_awgn_ls_per_prg", ...
    "HestSize", size(Hest), ...
    "NoiseVar", double(nVar), ...
    "PilotRECount", double(numel(ref)), ...
    "PilotResidualPower", double(pilotResidualPower), ...
    "PilotSignalPower", double(pilotSignalPower), ...
    "PilotResidualNMSE_dB", double(pilotResidualNMSEdB), ...
    "InterpolationMethod", "constant_within_prg_from_prg_local_dmrs_ls", ...
    "EffectiveChannelConvention", ...
        "resource_grid_rx_antenna_by_effective_layer_after_precoding_constant_within_prg", ...
    "ExactAWGNPRGEstimatorUsed", true, ...
    "PerPRGScalarCoefficient", true, ...
    "EstimatedCoefficientCount", double(numel(h)), ...
    "EstimatedCoefficients", h, ...
    "ScalarFastPathRequested", false, ...
    "ScalarFastPathAllowed", false, ...
    "ScalarFastPathUsed", false, ...
    "ScalarFastPathDisabledReason", ...
        "Estimator is resource-selective per PRG and is not a full-grid scalar shortcut");
end

function [prgSet, bundleSizeRB, info] = localResolvePDSCHPRGPartition(carrier, prec, cfg)
if exist("nrPRGInfo", "file") ~= 2
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:Missing5G", ...
        "nrPRGInfo is required to resolve explicit PDSCH PRG boundaries.");
end
nPRG = round(double(prec.NumPRG));
if ~(isscalar(nPRG) && isfinite(nPRG) && nPRG > 1)
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:BadPRGCount", ...
        "PRG-aware estimation requires an explicit precoder with more than one PRG page.");
end

hintPaths = [ ...
    "phy.pdsch.prbBundleSize", ...
    "phy.pdsch.prgBundleSizeRB", ...
    "phy.mimo.precoderPRGSizeRBs"];
hints = zeros(1, 0);
for ii = 1:numel(hintPaths)
    raw = sixgr.util.structGet(cfg, hintPaths(ii), []);
    value = localNumericPRGBundleSize(raw);
    if isfinite(value)
        hints(end+1) = value; %#ok<AGROW>
    end
end
hints = unique(hints, "stable");
if numel(hints) > 1
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:ConflictingPRGSize", ...
        "Configured PDSCH PRG bundle-size hints conflict: %s.", mat2str(hints));
end

if ~isempty(hints)
    bundleSizeRB = hints(1);
    prgInfo = nrPRGInfo(carrier, bundleSizeRB);
    if double(prgInfo.NPRG) ~= nPRG
        error("sixgr:phy:dl:PDSCHPRGChannelEstimate:PRGCountMismatch", ...
            ["Configured PDSCH PRG bundle size %d RB gives %d PRGs, but " ...
            "the explicit precoder contains %d pages."], ...
            bundleSizeRB, double(prgInfo.NPRG), nPRG);
    end
    prgSet = double(prgInfo.PRGSet(:));
    source = "validated_config_hint";
    candidateSizes = bundleSizeRB;
else
    candidateSizes = zeros(1, 0);
    candidateSets = cell(1, 0);
    for candidate = [2 4]
        candidateInfo = nrPRGInfo(carrier, candidate);
        if double(candidateInfo.NPRG) == nPRG
            candidateSizes(end+1) = candidate; %#ok<AGROW>
            candidateSets{end+1} = double(candidateInfo.PRGSet(:)); %#ok<AGROW>
        end
    end
    if isempty(candidateSets)
        error("sixgr:phy:dl:PDSCHPRGChannelEstimate:UnresolvablePRGPartition", ...
            ["The explicit precoder has %d pages, which matches neither " ...
            "the 2-RB nor 4-RB nrPRGInfo partition for this carrier."], nPRG);
    end
    prgSet = candidateSets{1};
    for ii = 2:numel(candidateSets)
        if ~isequal(prgSet, candidateSets{ii})
            error("sixgr:phy:dl:PDSCHPRGChannelEstimate:AmbiguousPRGPartition", ...
                ["The explicit precoder page count matches multiple distinct " ...
                "standards PRG partitions. Configure phy.pdsch.prbBundleSize explicitly."]);
        end
    end
    bundleSizeRB = candidateSizes(1);
    source = "inferred_from_precoder_page_count_and_nrPRGInfo";
end

if numel(prgSet) ~= double(carrier.NSizeGrid) || ...
        ~isequal(unique(prgSet(:)).', 1:nPRG)
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:InvalidPRGPartition", ...
        "Resolved PRGSet must map every carrier PRB exactly onto PRG pages 1:%d.", nPRG);
end
info = struct( ...
    "Source", source, ...
    "BundleSizeCandidatesRB", double(candidateSizes), ...
    "PRGCount", double(nPRG));
end

function value = localNumericPRGBundleSize(raw)
value = NaN;
if isnumeric(raw) || islogical(raw)
    raw = double(raw);
    if isscalar(raw) && isfinite(raw)
        value = raw;
    end
elseif ischar(raw) || isstring(raw)
    token = strtrim(string(raw));
    if isscalar(token)
        value = str2double(token);
    end
end
if isfinite(value)
    value = round(double(value));
    if ~ismember(value, [2 4])
        error("sixgr:phy:dl:PDSCHPRGChannelEstimate:BadPRGSize", ...
            "PDSCH PRG bundle size must be 2 or 4 RB; got %g.", value);
    end
end
end

function [refIndOut, refSymOut] = localSelectPDSCHPRGReferences( ...
        refInd, refSym, subcarriers, K, L, nPorts)
if ~isnumeric(refInd) || ~isnumeric(refSym) || ...
        ~isequal(size(refInd), size(refSym))
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:ReferenceShapeMismatch", ...
        "PDSCH DM-RS indices and symbols must have identical numeric shapes.");
end
indices = double(refInd);
if any(~isfinite(indices(:)) | indices(:) < 1 | ...
        indices(:) > double(K) * double(L) * double(max(1, nPorts)))
    error("sixgr:phy:dl:PDSCHPRGChannelEstimate:BadReferenceIndex", ...
        "PDSCH DM-RS indices are outside the layer-domain carrier grid.");
end
[k, ~, ~] = ind2sub([K L max(1, nPorts)], indices);
membership = ismember(double(k), double(subcarriers(:)));

if ~isvector(refInd) && size(refInd, 2) > 1
    firstPortMembership = membership(:, 1);
    if any(membership ~= firstPortMembership, "all")
        error("sixgr:phy:dl:PDSCHPRGChannelEstimate:PortReferencePartitionMismatch", ...
            "PDSCH DM-RS ports do not share a consistent PRG partition.");
    end
    refIndOut = refInd(firstPortMembership, :);
    refSymOut = refSym(firstPortMembership, :);
else
    refIndOut = refInd(membership);
    refSymOut = refSym(membership);
end
end

function [mask, linear] = localPDSCHReferenceMask(refInd, K, L, nPorts)
indices = double(refInd(:));
[k, l, ~] = ind2sub([K L max(1, nPorts)], indices);
linear = unique(sub2ind([K L], k, l), "stable");
mask = false(K, L);
mask(linear) = true;
end

function value = localWeightedFiniteMean(values, weights)
values = double(values(:));
weights = double(weights(:));
valid = isfinite(values) & isfinite(weights) & weights > 0;
if ~any(valid)
    value = NaN;
    return;
end
value = sum(values(valid) .* weights(valid)) ./ sum(weights(valid));
end

function method = localResolveChannelEstimationMethod(cfg)
method = char(string(sixgr.util.structGet(cfg, "phy.channelEstimation.method", ...
    sixgr.util.structGet(cfg, "phy.rx.channelEstimationMethod", "LS"))));
if isempty(strtrim(method))
    method = 'LS';
end
end

function [eqSymOut, info] = localCorrectEqualizedPDSCHCPEFromPTRS(eqSym, pdschInd, rxGrid, hEst, ...
        ptrsInd, ptrsSym, carrier, nVar, equalizerAlg, Rint, RIncludesNoise, enabled)
% Estimate PTRS common phase after channel compensation, then rotate PDSCH.
info = struct('Enabled', false, 'NumSymbolsCorrected', 0, ...
    'MeanCPE_deg', NaN, 'NAReason', "");
eqSymOut = eqSym;
if ~logical(enabled)
    info.NAReason = "ptrs_cpe_correction_disabled_by_config";
    return;
end
if isempty(eqSym) || isempty(pdschInd) || isempty(rxGrid) || isempty(hEst)
    info.NAReason = "missing_pdsch_equalized_symbols_or_channel_estimate";
    return;
end
if isempty(ptrsInd) || isempty(ptrsSym)
    info.NAReason = "ptrs_unavailable";
    return;
end

try
    [rxPTRS, hPTRS] = nrExtractResources(ptrsInd, rxGrid, hEst);
catch ME
    info.NAReason = "ptrs_resource_extraction_failed:" + string(ME.identifier);
    return;
end
if isempty(rxPTRS) || isempty(hPTRS)
    info.NAReason = "ptrs_resource_extraction_empty";
    return;
end

try
    [eqPTRS, ~, ~] = sixgr.phy.rx.mimoDetect(rxPTRS, hPTRS, nVar, ...
        "Algorithm", equalizerAlg, "Rint", Rint, "RIncludesNoise", RIncludesNoise);
catch ME
    info.NAReason = "ptrs_equalization_failed:" + string(ME.identifier);
    return;
end

refPTRS = ptrsSym(:);
eqPTRS = localSelectPTRSObservation(eqPTRS, refPTRS);
n = min(numel(eqPTRS), numel(refPTRS));
if n <= 0
    info.NAReason = "ptrs_equalized_symbol_count_mismatch";
    return;
end
eqPTRS = eqPTRS(1:n);
refPTRS = refPTRS(1:n);

dims = size(rxGrid);
if numel(dims) < 2
    info.NAReason = "rx_grid_not_resource_grid";
    return;
end
K = dims(1);
L = dims(2);
P = max(1, size(rxGrid, 3));
try
    [~, ptrsL, ~] = ind2sub([K L P], double(ptrsInd(:)));
    [~, dataL, ~] = ind2sub([K L P], double(pdschInd(:)));
catch ME
    info.NAReason = "ptrs_or_pdsch_symbol_index_decode_failed:" + string(ME.identifier);
    return;
end
ptrsL = ptrsL(1:min(numel(ptrsL), n));
eqPTRS = eqPTRS(1:numel(ptrsL));
refPTRS = refPTRS(1:numel(ptrsL));

valid = isfinite(real(eqPTRS)) & isfinite(imag(eqPTRS)) & ...
    isfinite(real(refPTRS)) & isfinite(imag(refPTRS)) & abs(refPTRS) > 0 & ...
    ptrsL >= 1 & ptrsL <= L;
if ~any(valid)
    info.NAReason = "no_valid_ptrs_cpe_samples";
    return;
end
eqPTRS = eqPTRS(valid);
refPTRS = refPTRS(valid);
ptrsL = ptrsL(valid);

cpeVec = NaN(L, 1);
for lSym = unique(ptrsL(:)).'
    mask = ptrsL == lSym;
    if ~any(mask)
        continue;
    end
    cpe = angle(sum(eqPTRS(mask) .* conj(refPTRS(mask)), "omitnan"));
    if isfinite(cpe)
        cpeVec(lSym) = cpe;
    end
end
finiteMask = isfinite(cpeVec);
if ~any(finiteMask)
    info.NAReason = "no_finite_ptrs_cpe_estimates";
    return;
end

cpeInterp = cpeVec;
finiteIdx = find(finiteMask);
unwrapped = unwrap(double(cpeVec(finiteMask)));
if numel(finiteIdx) == 1
    cpeInterp(:) = unwrapped(1);
else
    cpeInterp(:) = interp1(double(finiteIdx), unwrapped, (1:L).', "linear", "extrap");
end

dataL = dataL(1:min(numel(dataL), size(eqSymOut, 1)));
for row = 1:numel(dataL)
    lSym = dataL(row);
    if lSym >= 1 && lSym <= L && isfinite(cpeInterp(lSym))
        eqSymOut(row, :) = eqSymOut(row, :) .* cast(exp(-1j * cpeInterp(lSym)), "like", eqSymOut);
    end
end

info.Enabled = true;
info.NumSymbolsCorrected = double(numel(unique(dataL(dataL >= 1 & dataL <= L))));
info.MeanCPE_deg = rad2deg(mean(abs(cpeVec(finiteMask)), "omitnan"));
info.NAReason = "";
end

function obs = localSelectPTRSObservation(eqPTRS, refPTRS)
if isempty(eqPTRS)
    obs = complex(zeros(0, 1));
    return;
end
if isvector(eqPTRS)
    obs = eqPTRS(:);
    return;
end
if size(eqPTRS, 1) ~= numel(refPTRS)
    obs = eqPTRS(:);
    return;
end
refPTRS = refPTRS(:);
metric = zeros(1, size(eqPTRS, 2));
for col = 1:size(eqPTRS, 2)
    candidate = eqPTRS(:, col);
    metric(col) = abs(sum(candidate(:) .* conj(refPTRS), "omitnan"));
end
[~, bestCol] = max(metric);
if isempty(bestCol) || ~isfinite(metric(bestCol))
    bestCol = 1;
end
obs = eqPTRS(:, bestCol);
end

function [ptrsInd, ptrsSym, info] = localResolvePDSCHPTRS(carrier, pdsch, cfg)
ptrsInd = [];
ptrsSym = [];
info = struct("Available", false, "Enabled", false, "Source", "not_requested", ...
    "NAReason", "");
enabled = logical(sixgr.util.structGet(cfg, "phy.pdsch.enablePTRS", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enable", ...
    sixgr.util.structGet(cfg, "pdsch6gr.EnablePTRS", false))));
info.Enabled = enabled;
if ~enabled
    info.NAReason = "ptrs_disabled_by_config";
    return;
end
try
    ptrsInd = nrPDSCHPTRSIndices(carrier, pdsch, "IndexStyle", "index");
    ptrsSym = nrPDSCHPTRS(carrier, pdsch);
    info.Available = ~isempty(ptrsInd) && ~isempty(ptrsSym);
    info.Source = "nrPDSCHPTRS_runtime_symbols";
    if ~info.Available
        info.NAReason = "toolbox_returned_empty_ptrs";
    end
catch ME
    ptrsInd = [];
    ptrsSym = [];
    info.Available = false;
    info.Source = "nrPDSCHPTRS_unavailable";
    info.NAReason = string(ME.identifier);
end
end

function [alg, requested] = localResolveEqualizerAlgorithm(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    requested = string(sixgr.util.structGet(cfg, "phy.pusch.equalizer", ...
        sixgr.util.structGet(cfg, "phy.rx.equalizer", ...
        sixgr.util.structGet(cfg, "phy.equalization.algorithm", ...
        sixgr.util.structGet(cfg, "phy.rx.algorithm", "MMSE")))));
else
    requested = string(sixgr.util.structGet(cfg, "phy.pdsch.equalizer", ...
        sixgr.util.structGet(cfg, "phy.rx.equalizer", ...
        sixgr.util.structGet(cfg, "phy.equalization.algorithm", ...
        sixgr.util.structGet(cfg, "phy.rx.algorithm", "MMSE")))));
end
requested = upper(strtrim(requested));
if strlength(requested) == 0
    requested = "MMSE";
end
if contains(requested, "IRC")
    alg = "IRC";
elseif contains(requested, "ZF")
    alg = "ZF";
else
    alg = "MMSE";
end
end

function [Rint, info, includesNoise] = localResolvePDSCHInterferenceCovariance(opt, carrier, ...
        pdschInd, cfg, appliedTimingCorrection, nVar, rxGrid, hEst, dmrsInd, dmrsSym)
includesNoise = false;
[Rint, info] = sixgr.phy.rx.estimateContributionGridCovariance(opt.InterferenceContributionTensor, ...
    carrier, pdschInd, appliedTimingCorrection, opt.InterferenceContributionSource, ...
    opt.InterferenceContributionDomain, "pdsch", ...
    "EstimatorMode", sixgr.util.structGet(cfg, ...
        "phy.equalization.ircCovarianceEstimation", ...
        "per_prb_symbol_contribution_sample_covariance"), ...
    "FrequencyWindowPRBs", sixgr.util.structGet(cfg, ...
        "phy.equalization.ircCovarianceFrequencyWindowPRBs", 1), ...
    "TimeWindowSymbols", sixgr.util.structGet(cfg, ...
        "phy.equalization.ircCovarianceTimeWindowSymbols", 1), ...
    "ShrinkageFactor", sixgr.util.structGet(cfg, ...
        "phy.equalization.ircCovarianceShrinkageFactor", 0.05), ...
    "MinimumSamples", sixgr.util.structGet(cfg, ...
        "phy.equalization.ircCovarianceMinimumSamples", 4));
if logical(info.Available)
    return;
end

[Rint, info, includesNoise] = localResolveProvidedInterferenceCovariance(opt.InterferenceCovariance, ...
    opt.InterferenceCovarianceSource, opt.InterferenceCovarianceIncludesNoise, max(1, size(rxGrid, 3)));
if logical(info.Available)
    return;
end

[Rint, info] = sixgr.phy.rx.estimateInterferenceCovarianceIRC(rxGrid, hEst, dmrsInd, dmrsSym, nVar);
includesNoise = true;
info.CovarianceIncludesNoise = true;
info.Domain = "dmrs_pilot_residual_receive_antenna_covariance";
if ~isfield(info, "NAReason")
    info.NAReason = "";
end
end

function diag = localBuildPDSCHRxResourceDiagnostics(rxSym, hestSym, rxGrid, hEst, dmrsInd, Rint, nVar)
diag = struct( ...
    "MeasuredPDSCHRxResourcePower", localMeanComplexPower(rxSym), ...
    "MeasuredPDSCHHestResourcePower", localMeanComplexPower(hestSym), ...
    "MeasuredPDSCHHestFiniteFraction", localFiniteComplexFraction(hestSym), ...
    "MeasuredDMRSRxResourcePower", NaN, ...
    "MeasuredDMRSHestResourcePower", NaN, ...
    "MeasuredInterferenceCovarianceTrace", localCovarianceTraceMean(Rint), ...
    "MeasuredPreEqualizationNoiseVariance", double(nVar));
if isempty(dmrsInd)
    return;
end
try
    dmrsRx = nrExtractResources(dmrsInd, rxGrid);
    diag.MeasuredDMRSRxResourcePower = localMeanComplexPower(dmrsRx);
catch
end
try
    dmrsHest = nrExtractResources(dmrsInd, hEst);
    diag.MeasuredDMRSHestResourcePower = localMeanComplexPower(dmrsHest);
catch
end
end

function p = localMeanComplexPower(x)
p = NaN;
if isempty(x) || ~isnumeric(x)
    return;
end
v = x(:);
mask = isfinite(real(v)) & isfinite(imag(v));
if ~any(mask)
    return;
end
p = double(mean(abs(double(v(mask))).^2, "omitnan"));
end

function f = localFiniteComplexFraction(x)
f = NaN;
if isempty(x) || ~isnumeric(x)
    return;
end
v = x(:);
if isempty(v)
    return;
end
f = double(mean(isfinite(real(v)) & isfinite(imag(v))));
end

function tr = localCovarianceTraceMean(R)
tr = NaN;
if isempty(R) || ~isnumeric(R)
    return;
end
if ismatrix(R) && size(R, 1) == size(R, 2)
    tr = double(real(trace(double(R))) / max(1, size(R, 1)));
    return;
end
if ndims(R) == 3 && size(R, 2) == size(R, 3)
    vals = NaN(size(R, 1), 1);
    for ii = 1:size(R, 1)
        vals(ii) = real(trace(double(squeeze(R(ii, :, :))))) / max(1, size(R, 2));
    end
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        tr = double(mean(vals, "omitnan"));
    end
end
end

function [Rint, info, includesNoise] = localResolveProvidedInterferenceCovariance(Rprovided, source, includesNoiseInput, nRx)
Rint = [];
includesNoise = logical(includesNoiseInput);
info = struct("Available", false, ...
    "Source", "provided_interference_covariance_unavailable", ...
    "Status", "unavailable", ...
    "NAReason", "no_provided_interference_covariance", ...
    "Domain", "receive_antenna_covariance", ...
    "CovarianceIncludesNoise", includesNoise, ...
    "NumSamples", NaN);
if isempty(Rprovided)
    return;
end
R = double(Rprovided);
if ~ismatrix(R) || size(R, 1) ~= nRx || size(R, 2) ~= nRx
    info.NAReason = "provided_covariance_dimension_mismatch";
    return;
end
R = (R + R') ./ 2;
if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
    info.NAReason = "provided_covariance_nonfinite";
    return;
end
Rint = R;
src = strtrim(string(source));
if strlength(src) == 0
    src = "provided_interference_covariance";
end
info.Available = true;
info.Source = char(src);
info.Status = "OK";
info.NAReason = "";
info.NumRxAnt = double(nRx);
end

function [Rint, info] = localEstimateDMRSInterferenceCovariance(rxGrid, hEst, dmrsInd, dmrsSym, nVar)
Rint = [];
info = struct("Available", false, "Source", "dmrs_residual_covariance_unavailable", ...
    "Status", "NOT_AVAILABLE", "NumSamples", 0);
if isempty(rxGrid) || isempty(hEst) || isempty(dmrsInd) || isempty(dmrsSym)
    return;
end
try
    [rxRef, hRef] = nrExtractResources(dmrsInd, rxGrid, hEst);
catch
    info.Status = "dmrs_resource_extraction_failed";
    return;
end
if isempty(rxRef) || isempty(hRef)
    return;
end
if ndims(hRef) == 2
    hRef = reshape(hRef, size(hRef,1), size(hRef,2), 1);
end
nRE = min([size(rxRef, 1), size(hRef, 1), numel(dmrsSym)]);
if nRE < 2
    info.Status = "insufficient_dmrs_residual_samples";
    return;
end
nRx = size(rxRef, 2);
nLayer = size(hRef, 3);
residual = complex(zeros(nRE, nRx));
dmrsSym = dmrsSym(:);
for k = 1:nRE
    Hk = squeeze(hRef(k, :, :));
    if isvector(Hk)
        Hk = reshape(Hk, nRx, nLayer);
    end
    sk = repmat(dmrsSym(k), nLayer, 1);
    residual(k, :) = double(rxRef(k, :)) - (Hk * sk).';
end
residual = residual(all(isfinite(real(residual)) & isfinite(imag(residual)), 2), :);
if size(residual, 1) < 2
    info.Status = "dmrs_residual_not_finite";
    return;
end
R = (residual' * residual) ./ max(1, size(residual, 1));
R = (R + R') ./ 2;
noiseFloor = max(double(nVar), eps);
R = R + noiseFloor * eye(size(R, 1));
if any(~isfinite(R(:))) || rcond(double(R)) < 1e-12
    info.Status = "dmrs_residual_covariance_singular";
    return;
end
Rint = R;
info.Available = true;
info.Source = "dmrs_residual_interference_plus_noise_covariance";
info.Status = "OK";
info.NumSamples = double(size(residual, 1));
end

function tracking = localResolveReceiverTrackingCorrection(explicitState, cfg)
tracking = struct( ...
    "TRSProcessed", false, ...
    "TimingEstimateAvailable", false, ...
    "TimingEstimate_samples", NaN, ...
    "TimingCorrectionApplied", false, ...
    "CFOEstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, ...
    "EstimatedCommonFrequency_Hz", NaN, ...
    "PhysicalDoppler_Hz", NaN, ...
    "CFOCorrectionApplied", false, ...
    "CFOCorrectionApplied_Hz", NaN, ...
    "ResidualCFOEstimate_Hz", NaN, ...
    "Source", "unavailable_receiver_tracking_state", ...
    "Status", "unavailable", ...
    "NAReason", "no_receiver_tracking_state", ...
    "CFONAReason", "", ...
    "TrackingState", "", ...
    "AgeSlots", NaN, ...
    "KnownTimingDelay_samples", NaN, ...
    "MeasurementDirection", "", ...
    "ConsumerDirection", "DL", ...
    "DirectionCompatible", true, ...
    "AuthorityStatus", "legacy_untagged_tracking_state");

raw = explicitState;
usingRuntimeUserContext = isempty(raw);
if usingRuntimeUserContext
    raw = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
end
if ~(isstruct(raw) && ~isempty(fieldnames(raw)))
    return;
end

processed = localFirstLogical(raw, ["TRSProcessed","RuntimeTRSProcessed"], false);
tracking.TRSProcessed = logical(processed);
tracking.TrackingState = char(localFirstString(raw, ["TrackingState","RuntimeTRSTrackingStateAfter"], ""));
tracking.AgeSlots = double(localFirstFinite(raw, ["TRSAgeSlots","RuntimeTRSAgeSlots"], NaN));
tracking.Source = localFirstString(raw, ["RuntimeTRSRuntimeEvidenceSource","RuntimeEvidenceSource","TrackingEstimateSource"], ...
    "trs_receiver_tracking_state");
if ~processed
    tracking.NAReason = "trs_tracking_state_not_processed";
    return;
end

measurementDirection = upper(strtrim(localFirstString(raw, ...
    ["TrackingMeasurementDirection","RuntimeTRSMeasurementDirection"], "")));
consumerDirection = upper(strtrim(localFirstString(raw, ...
    ["TrackingConsumerDirection","RuntimeReceiverTrackingConsumerDirection"], "DL")));
directionCompatibilityDeclared = localFirstLogical(raw, ...
    ["TrackingDirectionCompatible","RuntimeReceiverTrackingDirectionCompatible"], true);
authorityStatus = localFirstString(raw, ...
    ["TrackingAuthorityStatus","RuntimeReceiverTrackingAuthorityStatus"], ...
    "legacy_untagged_tracking_state");
authorityReason = localFirstString(raw, ...
    ["TrackingAuthorityReason","RuntimeReceiverTrackingAuthorityReason"], "");
tracking.MeasurementDirection = char(measurementDirection);
tracking.ConsumerDirection = char(consumerDirection);
tracking.DirectionCompatible = logical(directionCompatibilityDeclared);
tracking.AuthorityStatus = char(authorityStatus);
if (~directionCompatibilityDeclared) || ...
        (strlength(measurementDirection) > 0 && measurementDirection ~= "DL") || ...
        (strlength(consumerDirection) > 0 && consumerDirection ~= "DL")
    tracking.Status = "rejected_cross_direction_receiver_state";
    if strlength(strtrim(authorityReason)) > 0
        tracking.NAReason = char(authorityReason);
    else
        tracking.NAReason = "measurement_and_dl_receiver_directions_differ";
    end
    return;
end

stateTokens = [ ...
    localFirstString(raw, ["TrackingState","RuntimeTRSTrackingStateAfter"], ""), ...
    localFirstString(raw, ["TRSValidityState","RuntimeTRSValidityState"], ""), ...
    localFirstString(raw, ["ChannelTrackingFreshnessState","RuntimeTRSChannelTrackingFreshnessState"], "")];
stateTokensLower = lower(stateTokens);
if any(contains(stateTokensLower, "stale") | contains(stateTokensLower, "expired") | ...
        contains(stateTokensLower, "invalid") | contains(stateTokensLower, "fail") | ...
        contains(stateTokensLower, "inactive"))
    tracking.NAReason = "trs_tracking_state_stale_or_invalid";
    return;
end

timingAvailable = localFirstLogical(raw, ["TimingEstimateAvailable","RuntimeTRSTimingEstimateAvailable"], false);
timingSamples = localFirstFinite(raw, ["TimingEstimate_samples","RuntimeTRSTimingEstimate_samples","EstimatedTimingOffset_samples"], NaN);
cfoAvailable = localFirstLogical(raw, ["CFOEstimateAvailable","RuntimeTRSCFOEstimateAvailable"], false);
allowRuntimeCommonAsCFO = logical(sixgr.util.structGet(cfg, ...
    "phy.rx.applyRuntimeTRSCommonFrequencyAsCFO", false));
[cfoHz,tracking.FrequencyEstimateDomain] = sixgr.phy.rx.resolveTrackingFrequencyEstimate( ...
    raw,usingRuntimeUserContext,allowRuntimeCommonAsCFO);
commonHz = localFirstFinite(raw, ["EstimatedCommonFrequency_Hz","RuntimeTRSEstimatedCommonFrequency_Hz", ...
    "EstimatedCommonPhaseFrequency_Hz"], NaN);
physicalDopplerHz = localFirstFinite(raw, ["PhysicalDoppler_Hz","RuntimeTRSPhysicalDoppler_Hz", ...
    "EstimatedDopplerHz","LastEstimatedTRSDopplerHz","RuntimeLastEstimatedTRSDopplerHz"], NaN);

tracking.TimingEstimateAvailable = logical(timingAvailable && isfinite(timingSamples));
tracking.TimingEstimate_samples = double(timingSamples);
tracking.CFOEstimateAvailable = logical(cfoAvailable && isfinite(cfoHz));
tracking.EstimatedCFO_Hz = double(cfoHz);
tracking.EstimatedCommonFrequency_Hz = double(commonHz);
tracking.PhysicalDoppler_Hz = double(physicalDopplerHz);
tracking.KnownTimingDelay_samples = localFirstFinite(raw, ["KnownTimingDelay_samples","RuntimeKnownTimingDelay_samples"], NaN);
if tracking.TimingEstimateAvailable || tracking.CFOEstimateAvailable
    tracking.Status = "available";
    tracking.NAReason = "";
else
    tracking.NAReason = "trs_tracking_state_has_no_timing_or_cfo_estimate";
end
end

function tf = localRuntimeAlignedTimingBypass(cfg)
runtimeAligned = logical(sixgr.util.structGet(cfg, ...
    "lls6g.receiverSync.RuntimeWaveformSampleAligned", false));
injectedTiming = localResolveInjectedTimingOffsetSamples(cfg);
hasInjectedTiming = isfinite(injectedTiming) && abs(double(injectedTiming)) > 1e-9;
% A zero-delay AWGN path and a fading path with an explicitly trimmed
% filter delay are both aligned producer outputs.  Requiring a nonzero
% trim made the behavior channel-profile dependent and allowed a second
% timing correction in the coupled FDD/TDD runtime.
tf = runtimeAligned && ~hasInjectedTiming;
end

function value = localFirstFiniteValue(varargin)
value = NaN;
for k = 1:nargin
    candidate = double(varargin{k});
    if ~isempty(candidate) && isfinite(candidate(1))
        value = candidate(1);
        return;
    end
end
end

function y = localApplyFrequencyCorrection(x, sampleRateHz, correctionHz)
if ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0 && isfinite(double(correctionHz)))
    y = x;
    return;
end
n = (0:size(x, 1)-1).';
rot = exp(1j * 2 * pi * (double(correctionHz) / double(sampleRateHz)) * n);
y = x .* cast(rot, "like", x);
end

function [rxGrid, ofdmInfo, tracking] = localApplyEstimatedCFOAndRedemodulate( ...
    carrier, rxWave, sampleRateHz, rxGrid, ofdmInfo, tracking, cfg)
enabled = logical(sixgr.util.structGet(cfg, "phy.rx.cfoCorrectionEnabled", ...
    sixgr.util.structGet(cfg, "phy.impairments.cfoCorrectionEnabled", false)));
if ~enabled
    if logical(sixgr.util.structGet(tracking, "CFOEstimateAvailable", false))
        tracking.CFONAReason = "cfo_correction_disabled_by_config";
    end
    return;
end
if logical(sixgr.util.structGet(tracking, "CFOCorrectionApplied", false))
    tracking = localEstimateResidualCFOAfterCorrection(rxWave, ofdmInfo, sampleRateHz, tracking, ...
        "cyclic_prefix_post_tracking_correction");
    return;
end
estimatedCFOHz = double(sixgr.util.structGet(tracking, "EstimatedCFO_Hz", NaN));
if ~(logical(sixgr.util.structGet(tracking, "CFOEstimateAvailable", false)) && ...
        isfinite(estimatedCFOHz) && isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
if localSuppressBlindCFOCorrectionForRuntimeAligned(cfg, tracking)
    tracking.CFOCorrectionApplied = false;
    tracking.CFOCorrectionApplied_Hz = NaN;
    tracking.Status = "available_measurement_only";
    tracking.CFONAReason = "runtime_aligned_zero_injected_cfo_blind_correction_suppressed";
    return;
end
correctedWave = localApplyFrequencyCorrection(rxWave, sampleRateHz, -estimatedCFOHz);
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, correctedWave);
tracking.CFOCorrectionApplied = true;
tracking.CFOCorrectionApplied_Hz = estimatedCFOHz;
tracking.Status = "available_corrected";
tracking.NAReason = "";
tracking.CFONAReason = "";
tracking = localEstimateResidualCFOAfterCorrection(correctedWave, ofdmInfo, sampleRateHz, tracking, ...
    "cyclic_prefix_post_receiver_correction");
end

function tf = localSuppressBlindCFOCorrectionForRuntimeAligned(cfg, tracking)
runtimeAligned = logical(sixgr.util.structGet(cfg, ...
    "lls6g.receiverSync.RuntimeWaveformSampleAligned", false));
forceBlindCorrection = logical(sixgr.util.structGet(cfg, ...
    "phy.rx.applyBlindCFOCorrectionOnAlignedRuntimeWaveform", false));
injectedCFOHz = localResolveInjectedCFOHz(cfg);
hasInjectedCFO = isfinite(injectedCFOHz) && abs(double(injectedCFOHz)) > 1e-9;
source = lower(strtrim(string(sixgr.util.structGet(tracking, "Source", ""))));
sourceIsBlindEstimator = any(contains(source, ["cyclic_prefix", "dmrs_reference_symbol_phase_slope", "reference_symbol_phase_slope"]));
tf = runtimeAligned && ~forceBlindCorrection && ~hasInjectedCFO && sourceIsBlindEstimator;
end

function tracking = localEstimateResidualCFOAfterCorrection(rxWave, ofdmInfo, sampleRateHz, tracking, source)
tracking.ResidualCFOEstimate_Hz = NaN;
tracking.ResidualCFOEstimateSource = string(source);
if ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
try
    [residualHz, residualInfo] = sixgr.phy.rx.estimateCFOFromCyclicPrefix(rxWave, ofdmInfo, sampleRateHz);
    if logical(sixgr.util.structGet(residualInfo, "EstimateAvailable", false)) && isfinite(double(residualHz))
        tracking.ResidualCFOEstimate_Hz = double(residualHz);
    end
catch
    tracking.ResidualCFOEstimateSource = string(source) + "_failed";
end
end

function y = localApplyTimingCorrection(x, timingOffset)
timingOffset = double(timingOffset);
if ~isfinite(timingOffset) || abs(timingOffset) < 1e-9
    y = x;
    return;
end
y = sixgr.util.applyFractionalSampleDelay(x, -timingOffset);
end

function maxCorrection = localMaxTimingCorrectionSamples(carrier)
% nrTimingEstimate returns the absolute waveform acquisition offset. In a
% fading replay this can include channel-object filter/group delay, so the
% data receiver must not clamp the applied shift to one CP length.
maxCorrection = inf;
end

function delay = localResolveKnownTimingDelaySamples(cfg, tracking, sampleRateHz)
delay = double(sixgr.util.structGet(tracking, "KnownTimingDelay_samples", NaN));
if isfinite(delay)
    return;
end
delay = double(sixgr.util.structGet(cfg, "phy.rx.knownTimingDelay_samples", NaN));
if isfinite(delay)
    return;
end
filterDelay = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelFilterDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelFilterDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelTrimSamples", 0))));
if ~isfinite(filterDelay)
    filterDelay = 0;
end
pathDelay = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelPathDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelPathDelay_samples", NaN)));
if ~isfinite(pathDelay)
    padSamples = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelPadSamples", ...
        sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelPadSamples", NaN)));
    trimSamples = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelTrimSamples", ...
        sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelTrimSamples", filterDelay)));
    if isfinite(padSamples) && isfinite(trimSamples)
        pathDelay = max(0, padSamples - trimSamples);
    else
        pathDelay = 0;
    end
end
propDelay_s = double(sixgr.util.structGet(cfg, "channel.propagationDelay_s", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingPropagationDelay_s", NaN)));
propDelaySamples = 0;
if isfinite(propDelay_s) && isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0
    propDelaySamples = max(0, double(propDelay_s) * double(sampleRateHz));
end
delay = max(0, double(filterDelay)) + max(0, double(pathDelay)) + double(propDelaySamples);
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "rf.cfo_Hz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0))));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "rf.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0))));
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function fs = localCarrierSampleRateHz(carrier)
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
fs = double(sampling.SampleRateHz);
end

function value = localFirstLogical(s, names, defaultValue)
value = logical(defaultValue);
for i = 1:numel(names)
    name = char(names(i));
    if isfield(s, name)
        raw = s.(name);
        if ~isempty(raw)
            value = logical(raw(1));
            return;
        end
    end
end
end

function value = localFirstFinite(s, names, defaultValue)
value = double(defaultValue);
for i = 1:numel(names)
    name = char(names(i));
    if isfield(s, name)
        raw = double(s.(name));
        raw = raw(isfinite(raw));
        if ~isempty(raw)
            value = raw(1);
            return;
        end
    end
end
end

function value = localFirstString(s, names, defaultValue)
value = string(defaultValue);
for i = 1:numel(names)
    name = char(names(i));
    if isfield(s, name)
        raw = string(s.(name));
        if ~isempty(raw) && strlength(strtrim(raw(1))) > 0
            value = raw(1);
            return;
        end
    end
end
end

function evidence = localReceiverHestSINR(hEst, nVar, cfg, direction, rxGrid, refInd, refSym)
evidence = struct( ...
    "Value", NaN, ...
    "Source", "unavailable_receiver_hest_csi_feedback_failed", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "receiver_hest_csi_feedback_metric_not_available");
if isempty(hEst)
    evidence.NAReason = "receiver_hest_grid_empty";
    return;
end
try
    args = {"Direction", direction};
    if ~isempty(rxGrid) && ~isempty(refInd) && ~isempty(refSym)
        args = [args, {"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym}];
    end
    csiMetric = sixgr.phy.dl.CSI_Feedback(hEst, nVar, cfg, args{:});
    sinr = double(sixgr.util.structGet(csiMetric, "PilotSINR_dB", ...
        sixgr.util.structGet(csiMetric, "ReferenceMeasuredSINR_dB", NaN)));
    if isfinite(sinr)
        evidence.Value = sinr;
        evidence.Source = char(string(sixgr.util.structGet(csiMetric, "PilotSINRSource", "receiver_hest_reference_signal_measurement")));
        evidence.ValueRole = "estimated";
        measurementStatus = string(sixgr.util.structGet(csiMetric, "ReferenceSINRValueStatus", "OK"));
        if contains(lower(measurementStatus), "dynamic_range_limited")
            evidence.ValueStatus = char(measurementStatus);
        else
            evidence.ValueStatus = "OK";
        end
        evidence.NAReason = "";
    end
catch ME
    evidence.NAReason = "receiver_hest_csi_feedback_failed:" + string(ME.identifier);
end
end

function [rxWaveform, tracking, timingResolution, syncState] = ...
        localApplyCalibrationReceiverTracking( ...
        rxWaveform, carrier, pdsch, cfg, opt)
tracking = localResolveReceiverTrackingCorrection( ...
    opt.ReceiverTrackingState, cfg);
sampleRateHz = localCarrierSampleRateHz(carrier);
knownTimingDelaySamples = localResolveKnownTimingDelaySamples( ...
    cfg, tracking, sampleRateHz);

% A calibration waveform is still a receiver waveform: a configured CFO
% must be estimated from received samples, not copied from the impairment
% configuration.  The UL truth receiver already owns this acquisition
% boundary.  Keep the DL calibration facade on the same measured contract
% so an FRC with nonzero frequency offset cannot silently execute with an
% unavailable tracking state.
if ~logical(tracking.CFOEstimateAvailable)
    cfoObservation = rxWaveform;
    if ~isempty(opt.TimingSearchWindowSamples)
        % CP and DM-RS frequency estimators require symbol-aligned input.
        % A shared capture begins at its receiver window, not necessarily
        % at the arriving slot. Acquire timing from received DM-RS first;
        % never substitute the channel delay or the configured CFO.
        assert(~logical(opt.FastAWGNPath) && ~logical(opt.SkipTimingEstimate) && ...
            ~localRuntimeAlignedTimingBypass(cfg), ...
            'sixgr:phy:dl:SharedPDSCHTimingBypassForbidden', ...
            'An unaligned shared capture requires measured DM-RS timing before frequency estimation.');
        [cfoObservation,~] = sixgr.phy.sync.alignULReferenceObservation( ...
            carrier,rxWaveform,nrPDSCHDMRSIndices(carrier,pdsch), ...
            nrPDSCHDMRS(carrier,pdsch),opt.TimingSearchWindowSamples);
    end
    tracking = localEstimateCalibrationReceiverCFO( ...
        cfoObservation, carrier, pdsch, cfg, sampleRateHz, tracking);
end

if logical(tracking.CFOEstimateAvailable) ...
        && isfinite(double(tracking.EstimatedCFO_Hz)) ...
        && isfinite(sampleRateHz) && sampleRateHz > 0
    rxWaveform = localApplyFrequencyCorrection( ...
        rxWaveform, sampleRateHz, -double(tracking.EstimatedCFO_Hz));
    tracking.CFOCorrectionApplied = true;
    tracking.CFOCorrectionApplied_Hz = ...
        double(tracking.EstimatedCFO_Hz);
elseif logical(tracking.CFOEstimateAvailable)
    tracking.CFONAReason = ...
        "receiver_tracking_cfo_estimate_present_but_sample_rate_unavailable";
end

rawTimingEstimate = NaN;
timingEstimateUsed = false;
timingEstimateSource = "unavailable";
if ~isempty(opt.TimingSearchWindowSamples)
    assert(~logical(opt.FastAWGNPath) && ~logical(opt.SkipTimingEstimate) && ...
        ~localRuntimeAlignedTimingBypass(cfg), ...
        'sixgr:phy:dl:SharedPDSCHTimingBypassForbidden', ...
        'An unaligned shared capture requires measured DM-RS timing, not an aligned/ideal timing bypass.');
    % Reference correlation uses the same OFDM primitive for both link
    % directions. Supply receiver-known DL DM-RS, never a channel delay or
    % transmitted data symbols, to the bounded capture extractor.
    indices=nrPDSCHDMRSIndices(carrier,pdsch);
    symbols=nrPDSCHDMRS(carrier,pdsch);
    [rxWaveform,receiveTiming]=sixgr.phy.sync.alignULReferenceObservation( ...
        carrier,rxWaveform,indices,symbols,opt.TimingSearchWindowSamples);
    rawTimingEstimate=receiveTiming.TimingOffsetSamples;
    timingEstimateSource=receiveTiming.TimingSource;
    knownTimingDelaySamples=0;
    timingResolution=sixgr.phy.sync.resolveTimingApplication(rawTimingEstimate, ...
        'EstimateUsed',true,'ApplicationMode','positive_crop_only','Source',timingEstimateSource);
    timingResolution.ApplicationPolicy='actual_capture_complete_slot_extraction_no_padding';
    timingResolution.ReceiveTiming=receiveTiming;
    tracking.TimingCorrectionApplied=true;
else
% RuntimeWaveformSampleAligned is a producer contract shared by FDD and
% TDD: the materialized channel delay has already been trimmed before this
% receiver boundary.  Preserve the TRS observation for audit, but do not
% shift the same waveform twice.  An explicitly injected YAML timing
% offset disables the bypass and exercises the receiver correction path.
if localRuntimeAlignedTimingBypass(cfg)
    timingEstimateSource = ...
        "runtime_aligned_waveform_no_timing_reacquisition";
elseif logical(tracking.TimingEstimateAvailable) ...
        && isfinite(double(tracking.TimingEstimate_samples))
    rawTimingEstimate = double(tracking.TimingEstimate_samples);
    timingEstimateUsed = true;
    timingEstimateSource = string(tracking.Source);
end

timingEstimateForCorrection = rawTimingEstimate;
if timingEstimateUsed && isfinite(rawTimingEstimate)
    knownDelayForCorrection = double(knownTimingDelaySamples);
    if isfinite(knownDelayForCorrection) ...
            && rawTimingEstimate > 0 ...
            && knownDelayForCorrection > rawTimingEstimate
        knownDelayForCorrection = rawTimingEstimate;
    end
    timingEstimateForCorrection = ...
        rawTimingEstimate - knownDelayForCorrection;
end
timingResolution = sixgr.phy.sync.resolveTimingApplication( ...
    timingEstimateForCorrection, ...
    "EstimateUsed", timingEstimateUsed, ...
    "ApplicationMode", "signed_waveform_shift", ...
    "SkipRequested", logical(opt.SkipTimingEstimate), ...
    "Source", timingEstimateSource, ...
    "MaxCorrectionSamples", localMaxTimingCorrectionSamples(carrier));
tracking.TimingCorrectionApplied = ...
    logical(timingResolution.EstimateUsed);
rxWaveform = localApplyTimingCorrection( ...
    rxWaveform, timingResolution.AppliedCorrection_samples);
end

% The residual estimator has the same CP-boundary prerequisite as the
% acquisition estimator. Measure the aligned, corrected samples actually
% passed to OFDM decoding, not the original delayed capture.
if logical(tracking.CFOCorrectionApplied)
    try
        [~, correctedOFDMInfo] = ...
            sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);
        tracking = localEstimateResidualCFOAfterCorrection( ...
            rxWaveform, correctedOFDMInfo, sampleRateHz, tracking, ...
            "cyclic_prefix_post_timing_and_frequency_correction");
    catch
        tracking.ResidualCFOEstimate_Hz = NaN;
        tracking.ResidualCFOEstimateSource = ...
            "cyclic_prefix_post_timing_and_frequency_correction_failed";
    end
end

syncState = sixgr.phy.sync.resolveSynchronizationState( ...
    "SampleRate_Hz", sampleRateHz, ...
    "InjectedCFO_Hz", localResolveInjectedCFOHz(cfg), ...
    "EstimatedCFO_Hz", double(sixgr.util.structGet( ...
        tracking, "EstimatedCFO_Hz", NaN)), ...
    "AppliedCFOCorrection_Hz", double(sixgr.util.structGet( ...
        tracking, "CFOCorrectionApplied_Hz", NaN)), ...
    "ResidualCFOEstimate_Hz", double(sixgr.util.structGet( ...
        tracking, "ResidualCFOEstimate_Hz", NaN)), ...
    "EstimatedCommonFrequency_Hz", double(sixgr.util.structGet( ...
        tracking, "EstimatedCommonFrequency_Hz", NaN)), ...
    "PhysicalDoppler_Hz", double(sixgr.util.structGet( ...
        tracking, "PhysicalDoppler_Hz", NaN)), ...
    "InjectedTimingOffset_samples", ...
        localResolveInjectedTimingOffsetSamples(cfg), ...
    "RawTimingEstimate_samples", rawTimingEstimate, ...
    "KnownTimingDelay_samples", knownTimingDelaySamples, ...
    "AppliedTimingCorrection_samples", ...
        double(timingResolution.AppliedCorrection_samples), ...
    "TimingEstimateUsed", logical(timingResolution.EstimateUsed), ...
    "TimingSource", timingEstimateSource, ...
    "FrequencySource", string(tracking.Source), ...
    "TrackingState", string(tracking.TrackingState), ...
    "TrackingAgeSlots", double(tracking.AgeSlots));
end

function tracking = localEstimateCalibrationReceiverCFO( ...
        rxWaveform, carrier, pdsch, cfg, sampleRateHz, tracking)
enabled = logical(sixgr.util.structGet(cfg, ...
    "phy.rx.cfoCorrectionEnabled", ...
    sixgr.util.structGet(cfg, ...
    "phy.impairments.cfoCorrectionEnabled", false)));
if ~enabled
    tracking.Status = "not_available";
    tracking.Source = "receiver_cfo_correction_disabled_by_config";
    tracking.NAReason = "cfo_correction_disabled_by_config";
    tracking.CFONAReason = tracking.NAReason;
    return;
end

method = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.impairments.cfoEstimationMethod", "cyclic_prefix"))));
estimateHz = NaN;
estimateAvailable = false;
estimateSource = method;
estimateStatus = "not_evaluated";
try
    [rxGrid, ofdmInfo] = ...
        sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);
    if any(method == ["dmrs_two_symbol", "dmrs", ...
            "reference_symbol_phase_slope"])
        dmrsIndices = nrPDSCHDMRSIndices(carrier, pdsch);
        dmrsSymbols = nrPDSCHDMRS(carrier, pdsch);
        [estimateHz, estimateInfo] = ...
            sixgr.phy.rx.estimateCFOFromReferenceSymbols( ...
            rxGrid, dmrsIndices, dmrsSymbols, carrier, sampleRateHz);
        estimateAvailable = logical(sixgr.util.structGet( ...
            estimateInfo, "EstimateAvailable", false));
        estimateSource = "pdsch_dmrs_reference_symbol_phase_slope";
        estimateStatus = string(sixgr.util.structGet( ...
            estimateInfo, "Status", "not_available"));
    elseif any(method == ["cyclic_prefix", "cp"])
        [estimateHz, estimateInfo] = ...
            sixgr.phy.rx.estimateCFOFromCyclicPrefix( ...
            rxWaveform, ofdmInfo, sampleRateHz);
        estimateAvailable = logical(sixgr.util.structGet( ...
            estimateInfo, "EstimateAvailable", false));
        estimateSource = "cyclic_prefix_cfo_estimator";
        estimateStatus = string(sixgr.util.structGet( ...
            estimateInfo, "Status", "not_available"));
    else
        estimateStatus = "unsupported_or_disabled_cfo_estimation_method";
    end
catch ME
    estimateStatus = "cfo_estimation_failed:" + string(ME.identifier);
end

if estimateAvailable && isfinite(double(estimateHz))
    tracking.CFOEstimateAvailable = true;
    tracking.EstimatedCFO_Hz = double(estimateHz);
    tracking.Source = char(estimateSource);
    tracking.Status = "available";
    tracking.NAReason = "";
    tracking.CFONAReason = "";
else
    tracking.CFOEstimateAvailable = false;
    tracking.EstimatedCFO_Hz = NaN;
    tracking.Source = char(estimateSource);
    tracking.Status = "not_available";
    tracking.NAReason = char(estimateStatus);
    tracking.CFONAReason = char(estimateStatus);
end
end

function [measurementGrid, measurementOFDMInfo, status] = ...
        localPreparePhysicalMeasurementGrid( ...
        measurementWaveform, carrier, tracking, timingResolution, varargin)
measurementGrid = [];
measurementOFDMInfo = struct();
status = "unavailable_missing_pre_front_end_measurement_waveform";
if isempty(measurementWaveform)
    return;
end
if size(measurementWaveform, 2) < 1 || ...
        any(~isfinite(real(measurementWaveform(:)))) || ...
        any(~isfinite(imag(measurementWaveform(:))))
    status = "unavailable_invalid_pre_front_end_measurement_waveform";
    return;
end

corrected = measurementWaveform;
sampleRateHz = localCarrierSampleRateHz(carrier);
cfoApplied = logical(sixgr.util.structGet( ...
    tracking, "CFOCorrectionApplied", false));
cfoCorrectionHz = double(sixgr.util.structGet( ...
    tracking, "CFOCorrectionApplied_Hz", NaN));
if cfoApplied
    if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && ...
            isfinite(cfoCorrectionHz))
        status = "unavailable_missing_applied_cfo_correction_contract";
        return;
    end
    corrected = localApplyFrequencyCorrection( ...
        corrected, sampleRateHz, -cfoCorrectionHz);
end

timingCorrection = double(sixgr.util.structGet( ...
    timingResolution, "AppliedCorrection_samples", NaN));
timingUsed = logical(sixgr.util.structGet( ...
    timingResolution, "EstimateUsed", false));
if timingUsed && ~isfinite(timingCorrection)
    status = "unavailable_missing_applied_timing_correction_contract";
    return;
end
if isfinite(timingCorrection)
    if isfield(timingResolution,'ReceiveTiming')
        count=timingResolution.ReceiveTiming.DemodulatedSampleCount;
        assert(timingCorrection>=0 && size(corrected,1)>=timingCorrection+count, ...
            'sixgr:phy:dl:IncompletePhysicalMeasurementTiming', ...
            'Antenna-plane measurement must retain the same actual complete slot as decoding.');
        corrected=corrected(timingCorrection+(1:count),:);
    else
        corrected = localApplyTimingCorrection(corrected, timingCorrection);
    end
end

try
    [measurementGrid, measurementOFDMInfo] = ...
        sixgr.phy.waveform.ofdmDemodulate(carrier, corrected, varargin{:});
    status = "available_exact_pre_front_end_grid";
catch ME
    measurementGrid = [];
    measurementOFDMInfo = struct( ...
        "ErrorIdentifier", string(ME.identifier), ...
        "ErrorMessage", string(ME.message));
    status = "unavailable_pre_front_end_ofdm_demodulation_failed";
end
end

function [csirsInd, csirsSym, csirsInfo, obs] = localObserveCSIRSRuntimeResource(carrier, cfg, rxGrid, opt, ofdmInfo)
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
    string(opt.PhysicalMeasurementSource));
obs.RuntimeMaterializationStatus = "runtime_observed";
obs.UpdateOutcome = "observed_after_ofdm_demodulation";
obs.RuntimeEvidenceSource = "sixgr.phy.dl.PDSCH_Rx:csirs_runtime_observation";
end

function obs = localMeasurePhysicalCSIRSRSP(obs, carrier, cfg, rxGrid, ...
        physicalGrid, csirsInfo, defaultConfig, ofdmInfo, ...
        physicalOFDMInfo, physicalGridStatus, physicalReferencePlane, ...
        physicalSource)
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
    physicalSource = "PDSCH_Rx_direct_receiver_waveform";
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
            carrier,configs{ordinal},physicalGrid);
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
obs.MeasurementPhysicalResourcesJSON = string(jsonencode(physicalResources));
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
        if isfield(measured,'SINR') && measured.SINR.Available
            obs.ReferenceMeasuredSINR_dB=measured.SINR.CSI_SINR_dB;
            obs.ReferenceMeasuredSINRSource=measured.SINR.Source;
            obs.ReferenceMeasuredSINRStatus="available";
            obs.ReferenceSINRMeasurementJSON=string(jsonencode(measured.SINR));
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

function obs = localRelabelNormalizedCSIRSPower(obs, cfg)
fixedNormalizedEsN0 = strcmpi(string(sixgr.util.structGet( ...
    cfg, "integration.run_mode", "")), "FIXED_SNR_SWEEP") && ...
    logical(sixgr.util.structGet(cfg, ...
    "integration.configured_snr_is_link_authority", false));
if ~fixedNormalizedEsN0
    return;
end
% The CSI-RS extraction is from the actual received OFDM waveform, but a
% configured Es/N0 run has no antenna-connector watt calibration. Preserve
% relative measurements and prevent the unit-Es numerical map from being
% exported as dBm.
obs.MeasurementRSRP_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSRP_dBm", NaN));
obs.MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(obs, "MeasurementRSRPPerReceiveAntenna_dBm", ""));
obs.MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(obs, "MeasurementRSRPPerResource_dBm", ""));
obs.MeasurementRSSI_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSSI_dBm", NaN));
obs.MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(obs, "MeasurementRSSIPerReceiveAntenna_dBm", ""));
obs.MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSRQNumeratorRSRP_dBm", NaN));
obs.MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSRQDenominatorRSSI_dBm", NaN));
obs.MeasurementRSRP_dBm = NaN;
obs.MeasurementRSRPPerReceiveAntenna_dBm = "";
obs.MeasurementRSRPPerResource_dBm = "";
obs.MeasurementRSRPPerResourceValues_dBm = [];
obs.MeasurementRSRPPerAntennaByResource_dBm = {};
obs.MeasurementRSSI_dBm = NaN;
obs.MeasurementRSSIPerReceiveAntenna_dBm = "";
obs.MeasurementRSRQNumeratorRSRP_dBm = NaN;
obs.MeasurementRSRQDenominatorRSSI_dBm = NaN;
obs.MeasurementPhysicalResources = {};
obs.MeasurementPhysicalResourcesJSON = "";
obs.MeasurementGridScaleToSqrtW = NaN;
obs.MeasurementReceiverGainCorrectionSource = ...
    "not_applicable_normalized_fixed_esn0";
obs.MeasurementSource = ...
    "actual_csirs_re_measurement_relative_to_unit_occupied_re_es";
obs.PowerReferencePlane = "normalized_fixed_esn0_unit_occupied_re_es";
obs.PhysicalMeasurementStatus = ...
    "available_normalized_fixed_esn0_not_absolute_dbm";
end

function [Hest, nVar, estInfo] = localEstimateCSIRSChannelForPMI(carrier, rxGrid, csirsInd, csirsSym, csirsInfo, cfg, strictMode, channelModelToken, numTxPorts)
Hest = [];
nVar = NaN;
resources = sixgr.util.structGet(csirsInfo, "Resources", []);
if numel(resources) > 1
    [Hest, nVar, estInfo] = localEstimateCSIRSResourceSetForPMI( ...
        carrier, rxGrid, resources, cfg, strictMode, channelModelToken);
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
    [Hest, nVar, chInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, csirsInd, csirsSym, ...
        "UseFastMex", false, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", expectedTxPorts, ...
        "CDMLengths", cdmLengths, ...
        "ContextLabel", "PDSCH_Rx_CSI_RS_PMI");
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
        localEstimateCSIRSResourceSetForPMI(carrier, rxGrid, resources, cfg, strictMode, channelModelToken)
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
        cfg, strictMode, channelModelToken, double(resource.NumPorts));
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

function mapping = localBuildPDSCHRxCodewordLayerContract(pdsch, rateMatchedBits, codingLayouts)
nLayers = localPositiveIntegerValue(localObjectValue(pdsch, "NumLayers", 1), "PDSCH.NumLayers");
nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers);
localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);
rateMatchedBits = double(rateMatchedBits);
if numel(rateMatchedBits) == 1 && nCodewords > 1
    rateMatchedBits = repmat(rateMatchedBits, 1, nCodewords);
end
if numel(rateMatchedBits) ~= nCodewords || any(~isfinite(rateMatchedBits) | rateMatchedBits <= 0 | abs(rateMatchedBits - round(rateMatchedBits)) > 1e-9)
    error("sixgr:phy:dl:PDSCHBadRateMatchedBitCount", "PDSCH RX requires a positive integer G for the codeword contract.");
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
layoutBits = zeros(1, nCodewords);
for c = 1:nCodewords
    layoutBits(c) = double(codingLayouts{c}.RateMatchedBitCount);
end
layerCountPerCodeword = localLayerCountPerCodeword(nLayers, nCodewords);
[codewordIndexByLayer, layerIndexWithinCodeword] = localCodewordLayerIndexMap(layerCountPerCodeword);
mapping = struct();
mapping.ContractVersion = "PDSCHCodewordLayer/v2";
mapping.Direction = "DL";
mapping.MappingStandard = "3GPP_TS_38_211_codeword_to_layer_mapping";
mapping.MappingEngine = "nrPDSCH_internal_nrLayerMap";
mapping.InverseEngine = "nrPDSCHDecode_internal_nrLayerDemap";
mapping.SupportedScope = "single_codeword_ranks_1_to_4_and_two_codeword_ranks_5_to_8";
mapping.UnsupportedScope = "";
mapping.NumCodewords = double(nCodewords);
mapping.ActualNumCodewords = NaN;
mapping.NumLayers = double(nLayers);
mapping.GrantNumLayers = double(nLayers);
mapping.CodewordIndexByLayer = double(codewordIndexByLayer);
mapping.CodewordIndexBase = 0;
mapping.LayerIndexWithinCodeword = double(layerIndexWithinCodeword);
mapping.LayerCountPerCodeword = double(layerCountPerCodeword);
mapping.RateMatchedBitCountPerCodeword = double(round(rateMatchedBits));
mapping.CodingLayoutRateMatchedBitCountPerCodeword = double(layoutBits);
mapping.DemapperLLRCountPerCodeword = NaN(1, nCodewords);
mapping.TotalDemapperLLRCount = NaN;
mapping.ActualLayerColumns = NaN;
mapping.ActualLayersEqualGrantLayers = false;
mapping.Equation = "port_observations_to_equalized_layers_S_hat_to_codeword_LLRs_by_inverse_TS38211_7_3_1_3";
end

function [llrCell, info] = localNormalizePDSCHCodewordLLR(llrRaw, mapping)
if iscell(llrRaw)
    llrCell = reshape(llrRaw, 1, []);
    sourceWasCell = true;
else
    llrCell = {llrRaw};
    sourceWasCell = false;
end
expected = double(mapping.NumCodewords);
if numel(llrCell) ~= expected
    error("sixgr:phy:dl:PDSCHDecodedCodewordCountMismatch", ...
        "nrPDSCHDecode returned %d codeword LLR stream(s), but the grant expects %d.", numel(llrCell), expected);
end
for c = 1:numel(llrCell)
    llrCell{c} = double(llrCell{c}(:));
end
info = struct( ...
    "ContractVersion", "PDSCHCodewordLLR/v1", ...
    "SourceWasCell", logical(sourceWasCell), ...
    "ExpectedNumCodewords", double(expected), ...
    "ActualNumCodewords", double(numel(llrCell)), ...
    "LLRCountPerCodeword", double(cellfun(@numel, llrCell)));
end

function [llrCellOut, infoCell] = localApplyCSIToPDSCHCodewordLLRCell(llrCellIn, csi, modScheme, postEqSINR_dB, mapping, nVarForDecode, nVarDecodeInfo)
llrCellOut = llrCellIn;
infoCell = cell(size(llrCellIn));
mods = localNormalizeModulationCell(modScheme, numel(llrCellIn));
csiCell = localDemapCSIByCodeword(csi, mapping);
for c = 1:numel(llrCellIn)
    infoCell{c} = localPDSCHPostEqVarianceLLRInfo(llrCellIn{c}, csiCell{c}, mods{c}, ...
        postEqSINR_dB, nVarForDecode, nVarDecodeInfo);
end
end

function info = localPDSCHPostEqVarianceLLRInfo(llrIn, csi, modScheme, postEqSINR_dB, nVarForDecode, nVarDecodeInfo)
rawCSI = double(csi(:));
rawCSI = rawCSI(isfinite(rawCSI));
if isempty(rawCSI)
    rawMedian = NaN;
else
    rawMedian = median(rawCSI, "omitnan");
end
inputMean = mean(abs(double(llrIn(:))), "omitnan");
source = "nrPDSCHDecode_post_equalization_noise_variance_only";
noiseSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "post_equalization_decoder_noise_variance")));
info = struct( ...
    "ContractVersion", "PDSCHDemapperLLRScaling/v1", ...
    "Convention", "post_equalization_variance_only", ...
    "NoiseVarianceConvention", "post_equalized_symbol_variance_passed_to_nrPDSCHDecode", ...
    "Source", source, ...
    "NoiseVarianceSource", noiseSource, ...
    "OutputDomain", "rate_matched_codeword_llr", ...
    "Applied", false, ...
    "Status", "not_applied_post_equalization_variance_convention", ...
    "Reason", "nrPDSCHDecode already consumed the effective post-equalization noise variance; applying CSI again would double-count reliability.", ...
    "InputKind", "not_used_for_second_weighting", ...
    "NoSecondCSIWeighting", true, ...
    "DemapperOutputAlreadyWeightedByNoiseVariance", true, ...
    "Modulation", char(string(modScheme)), ...
    "LLRCount", double(numel(llrIn)), ...
    "NoiseVariance", double(nVarForDecode), ...
    "PostEqSINR_dB", double(postEqSINR_dB), ...
    "RawCSIMedian", double(rawMedian), ...
    "WeightMedianBeforeNormalization", 1, ...
    "NormalizationScale", 1, ...
    "InputLLRMeanAbs", double(inputMean), ...
    "OutputLLRMeanAbs", double(inputMean));
end

function mapping = localFinalizePDSCHRxCodewordLayerContract(mapping, llrCell, eqSym)
counts = double(cellfun(@numel, llrCell));
expected = double(mapping.RateMatchedBitCountPerCodeword);
if numel(counts) ~= double(mapping.NumCodewords)
    error("sixgr:phy:dl:PDSCHDecodedCodewordCountMismatch", ...
        "PDSCH RX finalized %d codeword LLR stream(s), but the mapping contract expects %d.", ...
        numel(counts), round(double(mapping.NumCodewords)));
end
if any(counts(:).' ~= expected(:).')
    error("sixgr:phy:dl:PDSCHCodewordLLRCountContract", ...
        "PDSCH demapper LLR counts %s do not match per-codeword G %s.", mat2str(counts), mat2str(expected));
end
if isempty(eqSym)
    nCols = 0;
else
    if isvector(eqSym)
        nCols = 1;
    else
        nCols = size(eqSym, 2);
    end
end
mapping.ActualNumCodewords = double(numel(llrCell));
mapping.DemapperLLRCountPerCodeword = double(counts);
mapping.TotalDemapperLLRCount = double(sum(counts));
mapping.ActualLayerColumns = double(nCols);
mapping.ActualLayersEqualGrantLayers = logical(nCols == double(mapping.NumLayers));
end

function decode = localDecodePDSCHCodewords(llrCell, codingLayouts, trBlkSize, targetCodeRate, rv, modulationPerCodeword, numLayers, cfg, maxIter, alg, softBuffers, softLayouts)
nCodewords = numel(llrCell);
recLLRCell = cell(1, nCodewords);
recLLRBatchCell = cell(1, nCodewords);
rateRecoverInfoCell = cell(1, nCodewords);
harqInfoCell = cell(1, nCodewords);
harqSoftBufferCell = cell(1, nCodewords);
decodedCodeBlocksCell = cell(1, nCodewords);
ldpcSegCell = cell(1, nCodewords);
tbCrcCell = cell(1, nCodewords);
tbCell = cell(1, nCodewords);
crcPass = false(1, nCodewords);
crcError = true(1, nCodewords);
cbCrcCell = cell(1, nCodewords);
activeIterCell = cell(1, nCodewords);
parityCell = cell(1, nCodewords);
lineageCell = cell(1, nCodewords);
decodeLatency = zeros(1, nCodewords);
useMexAny = false;

for cw = 1:nCodewords
    layout = codingLayouts{cw};
    ldpcSeg = localLDPCSegmentationFromLayout(layout);
    [recLLR, rateRecoverInfo] = sixgr.phy.phycode.rateRecoverLDPC( ...
        llrCell{cw}, trBlkSize(cw), targetCodeRate(cw), rv(cw), modulationPerCodeword{cw}, ...
        double(layout.NumLayers), ldpcSeg.NumCodeBlocks, [], "CodingLayout", layout);
    [priorLLR, priorLayout] = localSelectHARQSoftBuffer(softBuffers, softLayouts, cw);
    [recLLR, harqInfo] = sixgr.phy.harq.combineSoftLLR(recLLR, priorLLR, ...
        "CurrentLayout", layout, "PriorLayout", priorLayout);
    recLLRBatch = localEnsureLLRBatch(recLLR);
    [decCbs, actIter, parity, usedMex, latency] = localDecodeLDPCCodeBlocks(recLLRBatch, double(layout.BaseGraph), maxIter, alg, cfg);
    B = double(ldpcSeg.TransportBlockLenWithCRC);
    [tbCrcRx, cbCrcErr] = sixgr.phy.tb.desegmentLDPC(decCbs, double(layout.BaseGraph), B);
    [tbRx, ok, err] = sixgr.phy.tb.checkCRC(tbCrcRx, char(string(layout.TBCRCType)));

    recLLRCell{cw} = recLLR;
    recLLRBatchCell{cw} = recLLRBatch;
    rateRecoverInfoCell{cw} = rateRecoverInfo;
    harqInfoCell{cw} = harqInfo;
    harqSoftBufferCell{cw} = sixgr.util.structGet(harqInfo, "SoftBuffer", struct());
    decodedCodeBlocksCell{cw} = decCbs;
    ldpcSegCell{cw} = ldpcSeg;
    tbCrcCell{cw} = tbCrcRx;
    tbCell{cw} = int8(tbRx(:));
    crcPass(cw) = logical(ok);
    crcError(cw) = logical(err);
    cbCrcCell{cw} = cbCrcErr(:).';
    activeIterCell{cw} = actIter(:).';
    parityCell{cw} = parity(:).';
    lineageCell{cw} = localBuildPDSCHDecodedBitLineage(cw, llrCell{cw}, recLLR, decCbs, ...
        layout, trBlkSize(cw), B, ok);
    decodeLatency(cw) = latency;
    useMexAny = useMexAny || logical(usedMex);
end

decode = struct();
decode.RecLLRCell = recLLRCell;
decode.RecLLRBatchCell = recLLRBatchCell;
decode.RateRecoverInfoCell = rateRecoverInfoCell;
decode.HARQCombiningInfoCell = harqInfoCell;
decode.HARQSoftBufferCell = harqSoftBufferCell;
decode.DecodedCodeBlocksCell = decodedCodeBlocksCell;
decode.LDPCSegmentationCell = ldpcSegCell;
decode.TransportBlockCRCPerCodeword = tbCrcCell;
decode.TransportBlockCell = tbCell;
decode.CRCPassPerCodeword = logical(crcPass);
decode.CRCErrorPerCodeword = logical(crcError);
decode.CodeBlockCRCErrorPerCodeword = cbCrcCell;
decode.CodeBlockCRCError = [cbCrcCell{:}];
decode.ActiveIterations = [activeIterCell{:}];
decode.ParityChecks = [parityCell{:}];
decode.DecodedBitLineageCell = lineageCell;
decode.DecodeLatency_s = double(sum(decodeLatency));
decode.DecodeLatencyPerCodeword_s = double(decodeLatency);
decode.UseMexLDPC = logical(useMexAny);
decode.TransportBlockLenWithCRCPerCodeword = double(cellfun(@(x) double(x.TransportBlockLenWithCRC), ldpcSegCell));
decode.HARQCombiningSummary = localSummarizeHARQCombining(harqInfoCell);
end

function lineage = localBuildPDSCHDecodedBitLineage(codewordIndex, demapperLLR, recLLR, decCbs, layout, trBlkSize, transportBlockLenWithCRC, crcPass)
lineage = struct( ...
    "ContractVersion", "PDSCHDecodedBitLineage/v1", ...
    "CodewordIndex", double(codewordIndex), ...
    "DemapperDomain", "rate_matched_codeword_llr", ...
    "DemapperLLRCount", double(numel(demapperLLR)), ...
    "RateMatchedBitCount", double(layout.RateMatchedBitCount), ...
    "RateRecoveryInputDomain", "rate_matched_codeword_llr", ...
    "RateRecoveryOutputDomain", "mother_code_llr_by_code_block", ...
    "RateRecoveredRows", double(size(recLLR, 1)), ...
    "RateRecoveredCodeBlocks", double(size(recLLR, 2)), ...
    "MotherCodeLength", double(layout.MotherCodeLength), ...
    "NumCodeBlocks", double(layout.NumCodeBlocks), ...
    "LDPCDecodedRows", double(size(decCbs, 1)), ...
    "LDPCDecodedCodeBlocks", double(size(decCbs, 2)), ...
    "TransportBlockSize", double(trBlkSize), ...
    "TransportBlockLengthWithCRC", double(transportBlockLenWithCRC), ...
    "TBCRCType", char(string(layout.TBCRCType)), ...
    "CRCPass", logical(crcPass), ...
    "RateMatchSignature", char(string(layout.RateMatchSignature)), ...
    "CombineSignature", char(string(layout.CombineSignature)));
end

function [decCbs, actIter, parity, useMexLDPC, decodeLatency_s] = localDecodeLDPCCodeBlocks(recLLRBatch, bgn, maxIter, alg, cfg)
C = size(recLLRBatch, 2);
actIter = NaN(1, C);
parity = NaN(1, C);
decodeTic = tic;
useMexLDPC = logical(sixgr.util.structGet(cfg, 'phy.ldpc.useMexBatchDecode', false)) ...
    && (exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3 || exist("sixgr_ldpc_decode_batch_kernel","file") == 2);

if useMexLDPC
    useNormMinSum = uint8(strcmpi(char(alg), 'Normalized min-sum'));
    try
        if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
            try
                [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
            catch
                [decMat, decLen] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
                actIterV = NaN(C, 1);
                parityV = NaN(C, 1);
            end
        else
            try
                [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
            catch
                [decMat, decLen] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
                actIterV = NaN(C, 1);
                parityV = NaN(C, 1);
            end
        end
        maxLen = max(1, min(size(decMat,1), round(max(decLen(:)))));
        decCbs = int8(decMat(1:maxLen, :));
        actIter = reshape(double(actIterV(:)), 1, []);
        parity = reshape(double(parityV(:)), 1, []);
    catch
        useMexLDPC = false;
    end
end

if ~useMexLDPC
    nRow = size(recLLRBatch, 1);
    decCbs = zeros(nRow, C, 'int8');
    maxLen = 0;
    usePar = (C > 1) && logical(sixgr.util.structGet(cfg, 'run.useParallel', false)) ...
        && license('test','Distrib_Computing_Toolbox') && ~isempty(gcp('nocreate'));
    if usePar
        dCell = cell(C,1);
        dLen = zeros(C,1);
        itV = NaN(C,1);
        pcV = NaN(C,1);
        parfor c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            dCell{c} = d;
            dLen(c) = min(numel(d), nRow);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = NaN; end
            if isempty(pc), pc = NaN; end
            itV(c) = double(it(1));
            pcV(c) = double(pc(1));
        end
        for c = 1:C
            actIter(c) = itV(c);
            parity(c) = pcV(c);
            Ld = dLen(c);
            if Ld > 0
                decCbs(1:Ld, c) = dCell{c}(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    else
        for c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = NaN; end
            if isempty(pc), pc = NaN; end
            actIter(c) = double(it(1));
            parity(c) = double(pc(1));
            d = int8(d(:));
            Ld = min(numel(d), nRow);
            if Ld > 0
                decCbs(1:Ld, c) = d(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    end
    if maxLen <= 0
        decCbs = zeros(1, C, 'int8');
    else
        decCbs = decCbs(1:maxLen, :);
    end
end
decodeLatency_s = toc(decodeTic);
end

function [priorLLR, priorLayout] = localSelectHARQSoftBuffer(softBuffers, softLayouts, codewordIndex)
priorLLR = [];
priorLayout = struct();
if isempty(softBuffers)
    return;
end
if iscell(softBuffers)
    if numel(softBuffers) >= codewordIndex
        priorLLR = softBuffers{codewordIndex};
    end
elseif isstruct(softBuffers)
    if isfield(softBuffers, "LLRSum") || isfield(softBuffers, "SoftBuffer")
        priorLLR = softBuffers;
        priorLayout = sixgr.util.structGet(softBuffers, "CodingLayout", struct());
        return;
    end
    softCell = sixgr.util.structGet(softBuffers, "SoftBufferCell", []);
    if iscell(softCell) && numel(softCell) >= codewordIndex
        priorLLR = softCell{codewordIndex};
        priorLayout = sixgr.util.structGet(priorLLR, "CodingLayout", struct());
        return;
    end
    raw = sixgr.util.structGet(softBuffers, "LLRCell", []);
    if isempty(raw)
        raw = sixgr.util.structGet(softBuffers, "RateRecoveredLLRCell", []);
    end
    if iscell(raw) && numel(raw) >= codewordIndex
        priorLLR = raw{codewordIndex};
    else
        priorLLR = sixgr.util.structGet(softBuffers, "LLR", sixgr.util.structGet(softBuffers, "RateRecoveredLLR", []));
    end
else
    priorLLR = softBuffers;
end

if isempty(softLayouts)
    return;
end
if iscell(softLayouts)
    if numel(softLayouts) >= codewordIndex
        priorLayout = softLayouts{codewordIndex};
    end
elseif isstruct(softLayouts)
    raw = sixgr.util.structGet(softLayouts, "CodingLayouts", []);
    if iscell(raw) && numel(raw) >= codewordIndex
        priorLayout = raw{codewordIndex};
    elseif numel(softLayouts) >= codewordIndex && isfield(softLayouts(codewordIndex), "RateMatchPositionMap")
        priorLayout = softLayouts(codewordIndex);
    else
        priorLayout = softLayouts;
    end
end
end

function summary = localSummarizeHARQCombining(infoCell)
applied = false(1, numel(infoCell));
cur = zeros(1, numel(infoCell));
prior = zeros(1, numel(infoCell));
reasons = strings(1, numel(infoCell));
for c = 1:numel(infoCell)
    applied(c) = logical(sixgr.util.structGet(infoCell{c}, "Applied", false));
    cur(c) = double(sixgr.util.structGet(infoCell{c}, "CurrentNumel", NaN));
    prior(c) = double(sixgr.util.structGet(infoCell{c}, "PriorNumel", NaN));
    reasons(c) = string(sixgr.util.structGet(infoCell{c}, "Reason", ""));
end
summary = struct( ...
    "Applied", any(applied), ...
    "AppliedPerCodeword", logical(applied), ...
    "PositionAware", any(cellfun(@(x) logical(sixgr.util.structGet(x, "PositionAware", false)), infoCell)), ...
    "Reason", char(strjoin(reasons, "|")), ...
    "CurrentNumel", double(sum(cur(isfinite(cur)))), ...
    "PriorNumel", double(sum(prior(isfinite(prior)))), ...
    "OverlapPositionCount", double(sum(cellfun(@(x) double(sixgr.util.structGet(x, "OverlapPositionCount", 0)), infoCell))), ...
    "SoftBufferCell", {cellfun(@(x) sixgr.util.structGet(x, "SoftBuffer", struct()), infoCell, "UniformOutput", false)});
if numel(summary.SoftBufferCell) == 1
    summary.SoftBuffer = summary.SoftBufferCell{1};
else
    summary.SoftBuffer = struct("ContractVersion", "HARQSoftBufferCollection/v1", ...
        "SoftBufferCell", {summary.SoftBufferCell});
end
end

function nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers)
nCodewords = 1 + (double(nLayers) > 4);
raw = localObjectValue(pdsch, "NumCodewords", []);
if ~isempty(raw)
    nCodewords = double(raw);
end
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1 && abs(nCodewords - round(nCodewords)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadCodewordCount", "PDSCH NumCodewords must be a positive integer scalar.");
end
nCodewords = round(nCodewords);
end

function localAssertPDSCHCodewordLayerScope(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nLayers < 1 || nLayers > 8
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH supports ranks 1-8 in this truth path. Requested NumLayers=%d.", nLayers);
end
expected = 1 + double(nLayers > 4);
if nCodewords ~= expected
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d requires NumCodewords=%d by TS 38.211 codeword-to-layer mapping. Requested %d.", ...
        nLayers, expected, nCodewords);
end
end

function counts = localLayerCountPerCodeword(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nCodewords == 1
    counts = double(nLayers);
    return;
end
switch nLayers
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
    otherwise
        error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
            "Two-codeword PDSCH mapping is defined here only for ranks 5-8. Requested rank %d.", nLayers);
end
if numel(counts) ~= nCodewords
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d maps to %d codeword layer groups, not %d.", nLayers, numel(counts), nCodewords);
end
end

function [cwByLayer, layerInCw] = localCodewordLayerIndexMap(layerCountPerCodeword)
cwByLayer = zeros(1, sum(layerCountPerCodeword));
layerInCw = zeros(1, sum(layerCountPerCodeword));
pos = 1;
for c = 1:numel(layerCountPerCodeword)
    n = double(layerCountPerCodeword(c));
    idx = pos:(pos + n - 1);
    % TS 38.211 7.3.1: physical q is zero-based; c indexes MATLAB cells.
    cwByLayer(idx) = c - 1;
    layerInCw(idx) = 1:n;
    pos = pos + n;
end
end

function values = localExpandPerCodewordDouble(values, nCodewords, name)
values = double(values(:).');
if numel(values) ~= nCodewords || any(~isfinite(values))
    error("sixgr:phy:dl:PDSCHBadPerCodewordVector", ...
        "%s must contain exactly NumCodewords=%d explicit values.", ...
        char(string(name)), nCodewords);
end
end

function values = localExpandPerCodewordInteger(values, nCodewords, name)
values = localExpandPerCodewordDouble(values, nCodewords, name);
if any(abs(values - round(values)) > 1e-9)
    error("sixgr:phy:dl:PDSCHBadPerCodewordVector", ...
        "%s must contain integer values.", char(string(name)));
end
values = round(values);
end

function rv = localExpandPerCodewordRV(rv, nCodewords)
rv = localExpandPerCodewordInteger(rv, nCodewords, "PDSCH RV");
if any(rv < 0 | rv > 3)
    error("sixgr:phy:dl:PDSCHBadRV", "PDSCH RV must be in [0,3].");
end
end

function mods = localPDSCHModulationPerCodeword(pdsch, nCodewords)
mods = localNormalizeModulationCell( ...
    localObjectValue(pdsch, "Modulation", ""), nCodewords);
end

function mods = localNormalizeModulationCell(raw, nCodewords)
tokens = string(raw);
tokens = tokens(:).';
if isempty(tokens) || any(strlength(strtrim(tokens)) == 0) ...
        || numel(tokens) ~= nCodewords
    error("sixgr:phy:dl:PDSCHMissingCodewordSpecificModulation", ...
        ["PDSCH Modulation must contain exactly NumCodewords=%d " ...
        "nonempty explicit tokens."], nCodewords);
end
tokens = upper(strrep(strtrim(tokens), " ", ""));
supported = ["QPSK","16QAM","64QAM","256QAM","1024QAM"];
if any(~ismember(tokens, supported))
    bad = tokens(find(~ismember(tokens, supported), 1));
    error("sixgr:pdsch:UnsupportedNRModulation", ...
        "Unsupported strict NR PDSCH modulation '%s'.", bad);
end
mods = cellstr(tokens);
end

function text = localModulationText(raw)
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    text = "";
else
    text = strjoin(tokens, "|");
end
end

function csiCell = localDemapCSIByCodeword(csi, mapping)
nCodewords = double(mapping.NumCodewords);
csiCell = cell(1, nCodewords);
for c = 1:nCodewords
    csiCell{c} = [];
end
if isempty(csi)
    return;
end
try
    out = nrLayerDemap(csi);
    if iscell(out) && numel(out) == nCodewords
        csiCell = reshape(out, 1, []);
        return;
    elseif ~iscell(out) && nCodewords == 1
        csiCell{1} = out;
        return;
    end
catch
end
if nCodewords == 1
    csiCell{1} = csi;
end
end

function cells = localNormalizeCodingLayoutCell(layoutIn, nCodewords)
cells = {};
if isempty(layoutIn)
    return;
end
if iscell(layoutIn)
    cells = reshape(layoutIn, 1, []);
elseif isstruct(layoutIn) && numel(layoutIn) > 1
    cells = num2cell(layoutIn(:).');
elseif isstruct(layoutIn) && isfield(layoutIn, "CodingLayouts") && iscell(layoutIn.CodingLayouts)
    cells = reshape(layoutIn.CodingLayouts, 1, []);
elseif isstruct(layoutIn) && ~isempty(fieldnames(layoutIn)) && isfield(layoutIn, "RateMatchPositionMap")
    cells = {layoutIn};
else
    cells = {};
end
if isempty(cells)
    return;
end
if numel(cells) == 1 && nCodewords > 1
    if isfield(cells{1}, "RateMatchPositionMap")
        cells = {};
        return;
    end
end
if numel(cells) ~= nCodewords
    cells = {};
end
end

function value = localPositiveIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadInteger", "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end
function [crcType, crcLen] = localResolveTBCRCSpec(schInfo, defaultType, defaultLen)
crcType = defaultType;
crcLen = defaultLen;
if nargin < 1 || ~isstruct(schInfo)
    return;
end
rawType = char(string(sixgr.util.structGet(schInfo, 'CRC', defaultType)));
if ~isempty(rawType)
    crcType = rawType;
end
rawLen = double(sixgr.util.structGet(schInfo, 'L', defaultLen));
if isfinite(rawLen) && rawLen >= 0
    crcLen = rawLen;
end
end

function seg = localResolveExpectedLDPCSegmentation(trBlkSize, bgn, tbCRCType)
% Mirror the Tx-side TB CRC + 38.212 code-block segmentation to recover C.
trBlkSize = double(trBlkSize);
bgn = double(bgn);
if ~(isscalar(trBlkSize) && isfinite(trBlkSize) && trBlkSize > 0)
    error("sixgr:phy:dl:PDSCHInvalidTBSForLDPC", ...
        "PDSCH_Rx cannot resolve LDPC segmentation for invalid TBS %.6g.", trBlkSize);
end
if ~(isscalar(bgn) && isfinite(bgn) && any(round(bgn) == [1 2]))
    error("sixgr:phy:dl:PDSCHInvalidBaseGraphForLDPC", ...
        "PDSCH_Rx cannot resolve LDPC segmentation for base graph %.6g.", bgn);
end
tb = zeros(round(trBlkSize), 1, 'int8');
tbCrc = sixgr.phy.tb.attachCRC(tb, tbCRCType);
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, round(bgn));
seg = struct( ...
    "TransportBlockLenWithCRC", double(numel(tbCrc)), ...
    "NumCodeBlocks", double(size(cbs, 2)), ...
    "CodeBlockLength", double(size(cbs, 1)), ...
    "SegmentationInfo", segInfo);
end

function layouts = localResolveRxCodingLayouts(layoutIn, phyGrant, direction, trBlkSize, targetCodeRate, rv, modulationPerCodeword, numLayers, rateMatchedBits)
nCodewords = numel(rateMatchedBits);
layerCounts = localLayerCountPerCodeword(double(numLayers), nCodewords);
provided = localNormalizeCodingLayoutCell(layoutIn, nCodewords);
if isempty(provided)
    grantLayout = sixgr.util.structGet(phyGrant, "CodingLayouts", []);
    if isempty(grantLayout)
        grantLayout = sixgr.util.structGet(phyGrant, "CodingLayout.CodingLayouts", []);
    end
    provided = localNormalizeCodingLayoutCell(grantLayout, nCodewords);
    if isempty(provided)
        grantSingle = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
        provided = localNormalizeCodingLayoutCell(grantSingle, nCodewords);
    end
end
layouts = cell(1, nCodewords);
for c = 1:nCodewords
    if ~isempty(provided) && isfield(provided{c}, "RateMatchPositionMap")
        layout = provided{c};
        localAssertCodingLayoutMatches(layout, trBlkSize(c), rv(c), modulationPerCodeword{c}, layerCounts(c), rateMatchedBits(c));
    else
        layout = sixgr.phy.phycode.resolveCodingLayout( ...
            "Direction", direction, ...
            "TransportBlockSize", trBlkSize(c), ...
            "TargetCodeRate", targetCodeRate(c), ...
            "RV", rv(c), ...
            "Modulation", modulationPerCodeword{c}, ...
            "NumLayers", layerCounts(c), ...
            "RateMatchedBitCount", rateMatchedBits(c));
    end
    layout.CodewordIndex = uint8(c);
    layout.NumCodewords = uint8(nCodewords);
    layout.PDSCHNumLayers = uint8(numLayers);
    layout.CodewordLayerCount = uint8(layerCounts(c));
    layout.CodewordLayerCountPerCodeword = uint8(layerCounts);
    layouts{c} = layout;
end
end

function localAssertCodingLayoutMatches(layout, trBlkSize, rv, modulation, numLayers, rateMatchedBits)
if double(layout.TransportBlockSize) ~= double(trBlkSize) || ...
        double(layout.RV) ~= double(rv) || ...
        ~strcmpi(char(string(layout.Modulation)), char(string(modulation))) || ...
        double(layout.NumLayers) ~= double(numLayers) || ...
        double(layout.RateMatchedBitCount) ~= double(rateMatchedBits)
    error("sixgr:phy:dl:PDSCHCodingLayoutMismatch", ...
        "Supplied CodingLayout does not match PDSCH RX grant dimensions.");
end
end

function seg = localLDPCSegmentationFromLayout(layout)
seg = struct( ...
    "TransportBlockLenWithCRC", double(layout.TransportBlockLengthWithCRC), ...
    "NumCodeBlocks", double(layout.NumCodeBlocks), ...
    "CodeBlockLength", double(layout.CodeBlockLength), ...
    "SegmentationInfo", sixgr.util.structGet(layout, "Segmentation", struct()));
end

function E = localRateMatchedBitCountFromInfo(info)
E = double(sixgr.util.structGet(info, "GPerCodeword", ...
    sixgr.util.structGet(info, "CodedBitCountGPerCodeword", ...
    sixgr.util.structGet(info, "G", NaN))));
E = E(:).';
if isempty(E) || any(~isfinite(E) | E <= 0 | abs(E - round(E)) > 1e-9)
    error("sixgr:phy:dl:PDSCHCodingLayoutMissingG", ...
        "PDSCH RX requires an integer rate-matched bit count to resolve CodingLayout.");
end
E = round(E);
end

function localValidateSupportedCodewordScope(cfg, pdsch)
nLayers = 1;
if isempty(pdsch)
    nLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
    nCodewords = double(sixgr.util.structGet(cfg, 'phy.pdsch.numCodewords', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.NumCodewords', 1 + (nLayers > 4))));
else
    try
        nLayers = double(pdsch.NumLayers);
    catch
        nLayers = 1;
    end
    nCodewords = double(localObjectValue(pdsch, "NumCodewords", 1 + (nLayers > 4)));
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = round(nLayers);
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1)
    nCodewords = 1 + (nLayers > 4);
end
nCodewords = round(nCodewords);
localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);
end
function nrePerPRB = localResolvePDSCHNREPerPRBOrError(carrier, pdsch, pdschInfo, nPRB)
nrePerPRB = localResolveNREFromInfo(pdschInfo, nPRB, pdsch.Modulation, pdsch.NumLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    try
        [~, pdschInfoFull] = nrPDSCHIndices(carrier, pdsch);
        nrePerPRB = localResolveNREFromInfo(pdschInfoFull, nPRB, pdsch.Modulation, pdsch.NumLayers);
    catch
    end
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error('sixgr:phy:dl:PDSCHRx:CannotResolveTBS', ...
        ['Cannot determine nrePerPRB for TBS calculation. Provide TransportBlockSize explicitly. ' ...
         'PRBSet=%s, SymbolAllocation=%s, Modulation=%s, NumLayers=%d.'], ...
        mat2str(double(pdsch.PRBSet)), mat2str(localSymAlloc(pdsch)), ...
        char(localModulationText(pdsch.Modulation)), round(double(pdsch.NumLayers)));
end
end

function nrePerPRB = localResolveNREFromInfo(info, nPRB, modStr, nLayers)
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = NaN;
end
end

function sa = localSymAlloc(pdsch)
try
    sa = double(pdsch.SymbolAllocation);
catch
    sa = [];
end
if numel(sa) < 2
    sa = [];
else
    sa = reshape(sa(1:2), 1, 2);
end
end

function x = localEnsureLLRBatch(xIn)
% Ensure a dense 2-D floating matrix for batch LDPC decode kernels.
x = xIn;
if ~(isa(x, 'double') || isa(x, 'single'))
    x = double(x);
end
if ~ismatrix(x)
    x = reshape(x, size(x,1), []);
else
    x = reshape(x, size(x,1), size(x,2));
end
end

function antInd = localPrecodeIndices(carrier, portInd, Wnr)
dummySym = complex(zeros(size(portInd)));
[~, antInd] = nrPDSCHPrecode(carrier, dummySym, portInd, Wnr);
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
try
    if isobject(obj) && isprop(obj, char(propName))
        value = obj.(char(propName));
    elseif isstruct(obj) && isfield(obj, char(propName))
        value = obj.(char(propName));
    end
catch
    value = defaultValue;
end
end

function numTxPorts = localExpectedTxPorts(pdsch, prec)
numTxPorts = 1;
try
    numTxPorts = max(numTxPorts, double(pdsch.NumLayers));
catch
end
if nargin >= 2 && isstruct(prec) && logical(sixgr.util.structGet(prec, "Active", false))
    Wnr = sixgr.util.structGet(prec, "MatrixNR", []);
    if ~isempty(Wnr)
        numTxPorts = max(numTxPorts, size(Wnr, 1));
    end
end
if ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1)
    numTxPorts = 1;
end
numTxPorts = max(1, round(numTxPorts));
end

function localValidateFastScalarShortcut(channelToken, numTxPorts, numRxAnt, useFastAWGNPath, contextLabel)
if ~logical(useFastAWGNPath)
    return;
end
if ~(localIsExplicitFlatChannel(channelToken) && numTxPorts <= 1 && numRxAnt <= 1)
    error("sixgr:phy:rx:InvalidFastScalarShortcut", ...
        "%s requires an explicit AWGN/flat SISO validation mode. Channel='%s', TxPorts=%d, RxAnt=%d.", ...
        contextLabel, localDisplayChannelToken(channelToken), numTxPorts, numRxAnt);
end
end

function localValidateNoDMRSUnitChannelFallback(channelToken, numTxPorts, numRxAnt, contextLabel)
if localIsExplicitFlatChannel(channelToken) && numTxPorts <= 1 && numRxAnt <= 1
    return;
end
error("sixgr:phy:rx:MissingDMRSForTruthChannelEstimate", ...
    "%s requires DM-RS-backed resource-selective channel estimation for truthful reception. Channel='%s', TxPorts=%d, RxAnt=%d.", ...
    contextLabel, localDisplayChannelToken(channelToken), numTxPorts, numRxAnt);
end

function channelToken = localResolveEstimatorChannelModel(cfg)
awgnOnly = logical(sixgr.util.structGet(cfg, 'channel.awgnOnly', false));
modelToken = localNormalizeChannelToken(sixgr.util.structGet(cfg, 'channel.model', ''));
fadingModelToken = localNormalizeChannelToken(sixgr.util.structGet(cfg, 'channel.fading.model', ''));
if awgnOnly || any(modelToken == ["AWGN", "NONE", "OFF"]) || any(fadingModelToken == ["AWGN", "NONE", "OFF"])
    channelToken = "AWGN";
    return;
end

candidates = { ...
    sixgr.util.structGet(cfg, 'channel.tdlProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.cdlProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.delayProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.fading.profile', ''), ...
    sixgr.util.structGet(cfg, 'channel.model', ''), ...
    sixgr.util.structGet(cfg, 'channel.fading.model', '') ...
    };

channelToken = "";
for i = 1:numel(candidates)
    token = localNormalizeChannelToken(candidates{i});
    if startsWith(token, "TDL") || startsWith(token, "CDL")
        channelToken = token;
        return;
    end
    if strlength(token) > 0 && strlength(channelToken) == 0
        channelToken = token;
    end
end
end

function token = localNormalizeChannelToken(rawValue)
token = upper(strtrim(string(rawValue)));
end

function tf = localIsExplicitFlatChannel(channelToken)
tf = any(strcmpi(char(string(channelToken)), {'AWGN', 'NONE', 'OFF'}));
end

function token = localDisplayChannelToken(channelToken)
token = char(string(channelToken));
if isempty(token)
    token = '<unspecified>';
end
end

function [dmrsSym, info] = localApplyPDSCHDMRSEPREDifference(dmrsSym, cfg)
[dmrsSym, info] = sixgr.phy.dl.applyPDSCHDMRSEPREDifference(dmrsSym, cfg);
end

function value = localScalarOrNaN(raw)
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw)
    value = NaN;
else
    value = double(raw(1));
end
end

function localPDSCHRxStageProgressLog(cfg, message, varargin)
enabled = logical(sixgr.util.structGet(cfg, "run.stageProgressLogging", false)) || ...
    localEnvLogical("SIXGR_VERBOSE_STAGE_LOG", false);
if ~enabled
    return;
end
try
    txt = sprintf(char(message), varargin{:});
catch
    txt = char(string(message));
end
fprintf("[%s] PDSCH-Rx %s\n", char(sixgr.util.utcNowISO8601()), txt);
drawnow("limitrate");
end

function tf = localEnvLogical(name, defaultValue)
if nargin < 2
    defaultValue = false;
end
raw = strtrim(string(getenv(char(name))));
if strlength(raw) == 0
    tf = logical(defaultValue);
    return;
end
tf = any(lower(raw) == ["1", "true", "yes", "on"]);
end
