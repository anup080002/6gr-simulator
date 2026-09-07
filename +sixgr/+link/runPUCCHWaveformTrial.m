function trial = runPUCCHWaveformTrial(cfg, varargin)
%RUNPUCCHWAVEFORMTRIAL Execute one canonical typed-report PUCCH trial.

p = inputParser;
p.FunctionName = "sixgr.link.runPUCCHWaveformTrial";
addRequired(p,"cfg",@(x) isstruct(x)||isobject(x));
addParameter(p,"Assignment",[], ...
    @(x) isa(x,"sixgr.phy.pucch.PUCCHTransmissionAssignment"));
addParameter(p,"Report",[],@(x) isa(x,"sixgr.phy.pucch.UCIReport"));
addParameter(p,"ReceiverContext",[], ...
    @(x) isempty(x)||isa(x,"sixgr.phy.pucch.UCIReportContext"));
addParameter(p,"Carrier",[],@(x) isempty(x)||isa(x,"nrCarrierConfig"));
addParameter(p,"ChannelProfile","AWGN",@(x) ischar(x)||isstring(x));
addParameter(p,"SNR_dB",30,@(x) isnumeric(x)&&isscalar(x)&&isfinite(x));
addParameter(p,"Seed",1,@(x) isnumeric(x)&&isscalar(x)&&isfinite(x));
addParameter(p,"SignalPresent",true,@(x) islogical(x)&&isscalar(x));
addParameter(p,"DetectionThreshold",0.2, ...
    @(x) isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
addParameter(p,"DopplerHz",0,@(x) isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(p,"DelaySpreadSeconds",300e-9, ...
    @(x) isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(p,"CFOHz",0,@(x) isnumeric(x)&&isscalar(x)&&isfinite(x));
addParameter(p,"TimingOffsetSamples",0, ...
    @(x) isnumeric(x)&&isscalar(x)&&isfinite(x)&&x==fix(x));
addParameter(p,"PhaseNoiseConfig",struct(),@(x) isstruct(x)&&isscalar(x));
addParameter(p,"InitialRuntimeChannelState",struct(), ...
    @(x) isempty(x)||isstruct(x));
addParameter(p,"InterferenceBundle",struct([]), ...
    @(x) isempty(x)||isstruct(x));
addParameter(p,"PrepareOnly",false,@(x)islogical(x)&&isscalar(x));
addParameter(p,"ReceivedContext",struct(),@(x)isstruct(x)&&isscalar(x));
addParameter(p,"TimingAdvanceSamples",NaN,@(x)isnumeric(x)&&isscalar(x));
parse(p,cfg,varargin{:});
opt = p.Results;
prepareOnly=opt.PrepareOnly;
received=~isempty(fieldnames(opt.ReceivedContext));
assert(~(prepareOnly && received),'sixgr:link:InvalidULControlStreamRequest','Select exactly one execution stage.');
if prepareOnly || received
    assert(isempty(opt.InterferenceBundle),'sixgr:link:ULControlInterferenceAlreadyComposed', ...
        'Shared-stream interference belongs to the physical receiver composition.');
    assert(opt.SignalPresent,'sixgr:link:AbsentPUCCHNeedsReceiveOnlyWindow', ...
        'An absent PUCCH requires a receive-only observation, not an active prepared transmitter.');
end
prepared=[];
if received
    receivedContext=opt.ReceivedContext;
    assert(isfield(receivedContext,'Prepared') && isa(receivedContext.Prepared,'sixgr.link.PreparedUplinkControlTransmission'), ...
        'sixgr:link:IncompleteULControlReceivedContext','Retain the actual prepared PUCCH transmission.');
    prepared=receivedContext.Prepared;
    prepared.validateReceived('PUCCH',cfg,opt);
    assert(isfield(receivedContext,'Channel') && isstruct(receivedContext.Channel) && ...
        isscalar(receivedContext.Channel) && isfield(receivedContext.Channel,'Profile') && ...
        string(receivedContext.Channel.Profile)==string(opt.ChannelProfile), ...
        'sixgr:link:ULControlChannelMismatch','Retain the actual configured channel execution metadata.');
end
stage="TX_RX_TRIAL";
if prepareOnly, stage="TX_PREPARATION"; elseif received, stage="RX_COMPLETION"; end
sixgr.runtime.RuntimeCallLedger.record("sixgr.link.runPUCCHWaveformTrial", ...
    "PUCCH", "UL", struct("Stage",stage));
trialPipelineTic = tic;

trial = localEmptyTrial(opt);
if isempty(opt.Assignment)
    trial.AssignmentRejected = true;
    trial.ErrorID = "sixgr:phy:pucch:WrongResource";
    trial.FailureReason = "missing_assignment";
    return;
end
if isempty(opt.Report)
    trial.ReportConstructionRejected = true;
    trial.ErrorID = "sixgr:phy:pucch:MissingUCIReportContext";
    trial.FailureReason = "missing_report";
    return;
end
context = opt.ReceiverContext;
if isempty(context)
    context = sixgr.phy.pucch.UCIReportContext.fromReport(opt.Report);
end
carrier = opt.Carrier;
if isempty(carrier)
    if isa(cfg,"nrCarrierConfig")
        carrier = cfg;
    else
        carrier = sixgr.phy.grid.makeCarrier(cfg);
    end
end

try
    if received
        tx=prepared.Tx;
    else
        tx = sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
            carrier,opt.Assignment,opt.Report);
    end
    trial.WaveformGenerated = true;
catch ME
    if prepareOnly || received, rethrow(ME); end
    trial.WaveformGenerationFailed = true;
    trial.ErrorID = string(ME.identifier);
    trial.ErrorMessage = string(ME.message);
    trial.ErrorStack = join(string({ME.stack.name}) + ":" + ...
        string([ME.stack.line]), " <- ");
    trial.FailureReason = "waveform_generation_failed";
    return;
end

cfgRuntime = localRuntimeConfig(cfg,carrier,opt);
if prepareOnly
    [tx.Waveform,cfgRuntime,powerEvidence]=sixgr.link.preparePUCCHTransmitWaveform( ...
        tx,cfgRuntime,'ApplyNodeRF',false);
    tx.PowerContext=cfgRuntime.lls6g.runtimePowerContext;
    tx.WaveformSHA256=sixgr.phy.pucch.PUCCHUtil.hash([real(tx.Waveform(:)).' imag(tx.Waveform(:)).']);
    trial.PreparedTransmission=sixgr.link.PreparedUplinkControlTransmission( ...
        'PUCCH',cfg,opt,tx,struct('OFDMInfo',tx.OFDMInfo),cfgRuntime, ...
        opt.Assignment.DueSlot-1,struct('PowerEvidence',powerEvidence));
    trial.ExecutionStage="transmit_prepared_not_received";
    trial.ExecutionBackend="pucch_transmitter_pre_node_rf";
    trial.EvidenceClass="prepared_transmission_not_received";
    trial.Status="PREPARED_NOT_RECEIVED";
    return;
elseif received
    cfgRuntime=prepared.ReceiverConfig;
    rxWaveform=prepared.readObservation(receivedContext.Observation,"receiver");
    desiredWaveform=[]; injectedNoise=[];
    if isfield(receivedContext,'DesiredReferenceObservation')
        desiredWaveform=prepared.readObservation(receivedContext.DesiredReferenceObservation,"receiver");
    end
    replay=receivedContext.Replay; runtimeState=receivedContext.ChannelState;
    noiseVariance=double(replay.SampleNoiseVariance);
    channelMeta=receivedContext.Channel;
    trial.ExecutionStage="received_shared_stream_completed";
    trial.ExecutionBackend="pucch_shared_stream_receiver";
else
    rng(double(opt.Seed),"twister");
    [rxWaveform, desiredWaveform, injectedNoise, noiseVariance, ...
        channelMeta, replay, runtimeState] = localRuntimeWaveformPath( ...
        cfgRuntime,tx,opt);
end
[signalPower, activeSymbolIndices] = localActiveOFDMMeanPower( ...
    desiredWaveform,tx);
measuredNoisePower = localActiveOFDMMeanPower( ...
    injectedNoise,tx,activeSymbolIndices);
measuredInterferencePower = double(sixgr.util.structGet( ...
    replay,"InterferenceWaveformVariance",0));
if received
    % A variance parameter is not a measured noise-only waveform. A nonlinear
    % composite cannot be separated into desired/noise components by guessing.
    measuredNoisePower=NaN;
    measuredInterferencePower=double(sixgr.util.structGet(replay,'InterferenceWaveformVariance',NaN));
end
if ~(isfinite(measuredInterferencePower) && measuredInterferencePower >= 0)
    measuredInterferencePower = NaN;
end
measuredDisturbancePower = measuredNoisePower+measuredInterferencePower;
if isfinite(signalPower) && signalPower > 0 && ...
        isfinite(measuredDisturbancePower) && measuredDisturbancePower > 0
    trial.InputMeasuredSINR_dB = 10*log10(signalPower/measuredDisturbancePower);
    trial.InputEVMPercent = 100*sqrt(measuredDisturbancePower/signalPower);
else
    trial.InputMeasuredSINR_dB = NaN;
    trial.InputEVMPercent = NaN;
end
trial.NoiseVariance = noiseVariance;
trial.MeasuredInputSignalPower = signalPower;
trial.MeasuredInputNoisePower = measuredNoisePower;
trial.MeasuredInputInterferencePower = measuredInterferencePower;
trial.MeasuredInputDisturbancePower = measuredDisturbancePower;
trial.Channel = channelMeta;
trial.ImpairmentReplay = replay;
trial.UpdatedRuntimeChannelState = runtimeState;
[estimatedCFO,cfoInfo] = sixgr.phy.rx.estimateCFOFromCyclicPrefix( ...
    rxWaveform,tx.OFDMInfo,double(tx.OFDMInfo.SampleRate));
trial.EstimatedCFO_Hz = double(estimatedCFO);
trial.CFOEstimatorInfo = cfoInfo;
trial.EstimatedTimingOffsetSamples = localTimingEstimate( ...
    carrier,rxWaveform,tx);

try
    rxArgs = {"NoiseVariance",noiseVariance, ...
        "NoiseVarianceDomain","sample", ...
        "ChannelProfile",channelMeta.Profile, ...
        "DetectionThreshold",opt.DetectionThreshold};
    interferenceCovariance = sixgr.util.structGet( ...
        replay,"InterferenceCovariance",[]);
    if ~isempty(interferenceCovariance)
        rxArgs = [rxArgs {"InterferenceCovariance", ...
            interferenceCovariance, ...
            "InterferenceCovarianceSource", ...
            "shared_slot_pucch_receiver_sample_contribution_covariance"}]; %#ok<AGROW>
    end
    rx = sixgr.phy.pucch.PUCCHReceiver.receive( ...
        rxWaveform,carrier,opt.Assignment,context,rxArgs{:});
catch ME
    if received, rethrow(ME); end
    trial.ReceiverDecodeFailed = true;
    trial.ErrorID = string(ME.identifier);
    trial.ErrorMessage = string(ME.message);
    trial.ErrorStack = join(string({ME.stack.name})+":" + ...
        string([ME.stack.line])," <- ");
    trial.FailureReason = "receiver_decode_failed";
    return;
end

serialized = tx.Serialization;
reference = [serialized.Sequence1.Bits;serialized.Sequence2.Bits];
decoded = [rx.DecodedSequence1;rx.DecodedSequence2];
[bitErrors,bitsCompared,contentMismatch] = localCompare(reference,decoded);
trial.ReceiverDTX = logical(rx.DTX);
trial.CRCFailed = ~logical(rx.CRCPassed);
trial.ContentMismatch = contentMismatch;
trial.BitErrors = bitErrors;
trial.BitsCompared = bitsCompared;
trial.Receiver = rx;
trial.Transmitter = tx;
trial.Rx = rx;
trial.RxInfo = struct("OFDMInfo",rx.OFDMInfo, ...
    "ReceiverUsable",rx.ReceiverUsable, ...
    "DetectionAttempted",rx.DetectionAttempted, ...
    "DetectionMetric",rx.DetectionMetric, ...
    "FailureReason",rx.FailureReason);
trial.Tx = tx;
trial.TxInfo = struct("OFDMInfo",tx.OFDMInfo, ...
    "Format",opt.Assignment.Format, ...
    "AssignmentDigest",tx.AssignmentDigest, ...
    "ConnectedModeEvidenceEligible",tx.ConnectedModeEvidenceEligible);
trial.Channel = channelMeta;
trial.NoiseVariance = noiseVariance;
trial.ExpectedBits = reference;
trial.DecodedBits = decoded;
trial.ExpectedBitCount = numel(reference);
trial.DecodedBitCount = numel(decoded);
trial.UCIExpectedBitVector = sixgr.phy.pucch.PUCCHUtil.bitString(reference);
trial.UCIDecodedBitVector = sixgr.phy.pucch.PUCCHUtil.bitString(decoded);
trial.UCIBitErrorVector = localErrorVector(reference,decoded);
trial.UCICodedBitCount = numel(tx.Coding.CodedBits);
trial.UCICRCBitCount = tx.Coding.Plan.CRCBits;
trial.UCICRCApplicable = tx.Coding.Plan.CRCBits > 0;
trial.CRCApplicable = trial.UCICRCApplicable;
if trial.CRCApplicable
    trial.CRCPass = double(~trial.CRCFailed);
else
    trial.CRCPass = NaN;
end
trial.UCIContentMatch = ~contentMismatch;
trial.AckObserved = ~isempty(decoded) && logical(decoded(1));
trial.DTXFlag = logical(rx.DTX);
trial.DetectionMetric = rx.DetectionMetric;
trial.DetectionThreshold = rx.DetectionThreshold;
trial.DetectionAttempted = rx.DetectionAttempted;
trial.DetectionUsable = rx.ReceiverUsable;
trial.ReceiverUsable = rx.ReceiverUsable;
trial.RequestedFormat = opt.Assignment.Format;
trial.ResolvedFormat = opt.Assignment.Format;
trial.PUCCHFormat = opt.Assignment.Format;
trial.FormatAdapted = false;
trial.FormatAdaptationReason = "none_strict_assignment";
trial.ControlResourceValidity = true;
trial.PUCCHResourceId = string(opt.Assignment.Resource.ID);
trial.PUCCHPRBStart = opt.Assignment.Resource.Data.StartPRB;
trial.PUCCHPRBCount = opt.Assignment.Resource.Data.NumPRBs;
trial.PUCCHSymbolStart = opt.Assignment.Resource.Data.StartSymbol;
trial.PUCCHNumSymbols = opt.Assignment.Resource.Data.NumSymbols;
trial.PUCCHRECount = height(tx.Ownership.Table);
trial.PUCCHDMRSRECount = numel(tx.DMRS.Indices);
trial.PUCCHGridHash = tx.ResourceOwnershipDigest;
trial.PUCCHWaveformHash = tx.WaveformSHA256;
trial.ChannelModel = string(channelMeta.Profile);
trial.DopplerHz = double(sixgr.util.structGet( ...
    cfgRuntime,"channel.doppler_Hz",opt.DopplerHz));
trial.ConfiguredSNR_dB = double(opt.SNR_dB);
trial.AppliedAWGNSNR_dB = double(sixgr.util.structGet( ...
    replay,"AppliedAWGNSNR_dB",localAWGNSNR(opt)));
trial.NoiseVarStatus = "OK";
trial.NoiseVarSource = string(sixgr.util.structGet( ...
    replay,"NoiseVarianceSource", ...
    "calibrated_sample_to_grid_transform"));
trial.NoiseVarReason = "";
trial.NoiseVarStrictFailure = false;
sinrAvailable = logical(sixgr.util.structGet(rx, ...
    "MeasuredSINRApplicable",isfinite(rx.MeasuredSINR_dB))) && ...
    isfinite(double(rx.MeasuredSINR_dB));
hestSINRApplicable = logical(sixgr.util.structGet(rx, ...
    "ChannelEstimateApplicable",false)) && ~isempty(rx.ChannelEstimate) && ...
    sinrAvailable;
sinrSource = string(sixgr.util.structGet(rx,"MeasuredSINRSource", ...
    "pucch_receiver_resource_measurement"));
trial.ReceiverHestSINR_dB = NaN;
if hestSINRApplicable
    trial.ReceiverHestSINR_dB = rx.MeasuredSINR_dB;
end
trial.ReceiverHestSINRApplicable = hestSINRApplicable;
trial.ReceiverHestSINRSource = localAvailableText( ...
    hestSINRApplicable,sinrSource,"not_applicable_without_dmrs_channel_estimate");
trial.ReceiverHestSINRValueRole = localAvailableText( ...
    hestSINRApplicable,"estimated","unavailable");
trial.ReceiverHestSINRValueStatus = localAvailableText( ...
    hestSINRApplicable,"OK","unavailable");
trial.MeasuredTrialSINR_dB = rx.MeasuredSINR_dB;
trial.MeasuredTrialSINRSource = sinrSource;
trial.MeasuredTrialSINRValueRole = localAvailableText( ...
    sinrAvailable,"measured","unavailable");
trial.MeasuredTrialSINRValueStatus = localAvailableText( ...
    sinrAvailable,"OK","unavailable");
trial.MeasuredSINR_dB = rx.MeasuredSINR_dB;
trial.PostEqSINR_dB = rx.MeasuredSINR_dB;
trial.PostEqSINRSource = sinrSource;
trial.PostEqSINRValueRole = localAvailableText( ...
    sinrAvailable,"measured","unavailable");
trial.PostEqSINRValueStatus = localAvailableText( ...
    sinrAvailable,"OK","unavailable");
trial.SINRValueRole = localAvailableText( ...
    sinrAvailable,"measured","unavailable");
trial.SINRSource = sinrSource;
trial.SINRValueStatus = localAvailableText( ...
    sinrAvailable,"OK","unavailable");
trial.SINRValueDefinition = "post_equalization_resource_sinr";
trial.ReceiverEVMPercent = double(sixgr.util.structGet(rx,"EVMPercent",NaN));
trial.ReceiverEVMApplicable = logical(sixgr.util.structGet(rx, ...
    "EVMApplicable",false));
trial.CRCOutcome = localCRCOutcome(trial.CRCApplicable,trial.CRCFailed);
trial.DetectionOutcome = localDetectionOutcome(rx.DTX,contentMismatch);
trial.Crash = false;
trial.CrashSource = "";
trial.CrashMessage = "";
trial.UsedOracleFields = "";
trial.Notes = "Waveform-backed PUCCH through typed report, assignment and oracle-free receiver.";
trial.RuntimeIntegrationMode = "coupled_slot_runtime";
trial.RuntimeTransportMode = "pucch_tx_runtime_channel_rf_noise_pucch_rx";
if received
    trial.RuntimeTransportMode="prepared_pucch_shared_stream_receiver";
    trial.TransmitterCompositeObservation=receivedContext.TransmitterObservation;
    trial.PUCCHWaveformReferencePlane="pre_node_rf_transmitter_contribution";
end
trial.RuntimeStageWaveformsRequired = true;
trial.RuntimeStageWaveformsUsed = true;
trial.RuntimeSelfLoopWaveformsUsed = false;
trial.RuntimeChannelStateUsed = logical(sixgr.util.structGet( ...
    replay,"RuntimeChannelStateUsed",false));
trial.RuntimeNoiseApplied = isfinite(noiseVariance) && noiseVariance > 0;
trial.RuntimeNoiseVarianceMean = double(noiseVariance);
trial.RuntimeChannelLinkKeys = string(sixgr.util.structGet( ...
    replay,"RuntimeChannelLinkKey",""));
trial.RuntimeStageCount = 5;
trial.InterferenceMode = string(sixgr.util.structGet( ...
    replay,"InterferenceMode","none"));
trial.InterferenceContributorCount = double(sixgr.util.structGet( ...
    replay,"InterferenceContributorCount",0));
trial.InterferenceAggregatedRxPower_dBm = double(sixgr.util.structGet( ...
    replay,"InterferenceAggregatedRxPower_dBm",NaN));
trial.InterferencePowerSource = string(sixgr.util.structGet( ...
    replay,"InterferencePowerSource",""));
trial.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet( ...
    replay,"FullInterfererChannelTruthUsed",false));
txBoundary = sixgr.util.structGet(replay,"PUCCHTransmitBoundary",struct());
trial.PUCCHAppliedTxPower_dBm = double(sixgr.util.structGet( ...
    txBoundary,"AppliedPower_dBm",NaN));
trial.PUCCHMeasuredTxOutputPower_dBm = double(sixgr.util.structGet( ...
    txBoundary,"MeasuredTxOutputPower_dBm",NaN));
trial.PUCCHTxPowerClosureError_dB = double(sixgr.util.structGet( ...
    txBoundary,"PowerClosureError_dB",NaN));
trial.PUCCHRequestedTxPower_dBm = double(sixgr.util.structGet( ...
    tx,"Power.RequestedPowerdBm",NaN));
trial.PUCCHPCMAX_dBm = double(sixgr.util.structGet( ...
    tx,"Power.PCMAXdBm",NaN));
trial.PUCCHPowerHeadroom_dB = double(sixgr.util.structGet( ...
    tx,"Power.PowerHeadroomdB",NaN));
trial.PUCCHPowerControlPathloss_dB = double(sixgr.util.structGet( ...
    tx,"Power.PathlossdB",NaN));
trial.PUCCHConfiguredPathloss_dB = double(sixgr.util.structGet( ...
    tx,"Power.ConfiguredPathlossdB",NaN));
trial.PUCCHPathlossSource = string(sixgr.util.structGet( ...
    tx,"Power.PathlossSource",""));
trial.PUCCHPathlossReferenceRS = string(sixgr.util.structGet( ...
    tx,"Power.PathlossReferenceRS",""));
trial.PUCCHPathlossMeasurementId = string(sixgr.util.structGet( ...
    tx,"Power.PathlossMeasurementId",""));
trial.PUCCHPathlossMeasurementSlot = double(sixgr.util.structGet( ...
    tx,"Power.PathlossMeasurementSlot",NaN));
trial.PUCCHRuntimeMeasuredPathlossUsed = logical(sixgr.util.structGet( ...
    tx,"Power.RuntimeMeasuredPathlossUsed",false));
trial.PUCCHWaveformAmplitudeUnit = string(sixgr.util.structGet( ...
    txBoundary,"WaveformAmplitudeUnit",""));
trial.PUCCHTxOutputWaveformHash = string(sixgr.util.structGet( ...
    txBoundary,"TxOutputWaveformSHA256",""));
trial.TxRFExecutionStatus = string(sixgr.util.structGet( ...
    txBoundary,"TXRFExecutionStatus",""));
trial.TxRFStageOrder = string(sixgr.util.structGet( ...
    txBoundary,"TXRFStageOrder",""));
trial.TxRFAppliedStageCount = double(sixgr.util.structGet( ...
    txBoundary,"TXRFAppliedStageCount",0));
trial.Ok = ~trial.ReceiverDTX && ~trial.CRCFailed && ...
    ~trial.ContentMismatch && logical(opt.SignalPresent);
if ~opt.SignalPresent
    trial.Ok = rx.DTX;
end
trial.ResourceExtractionAttempted = true;
trial.ResourceExtractionAvailable = true;
trial.ChannelEstimateAttempted = ~isempty(tx.DMRS.Indices) && ...
    upper(string(channelMeta.Profile)) ~= "AWGN";
trial.ChannelEstimateAvailable = ~trial.ChannelEstimateAttempted || ...
    ~isempty(rx.ChannelEstimate);
trial.ChannelEstimateSource = localChannelEstimateSource( ...
    channelMeta.Profile,trial.ChannelEstimateAttempted,opt.Assignment.Format);
trial.EqualizationAttempted = trial.ChannelEstimateAttempted;
trial.EqualizationAvailable = ~trial.EqualizationAttempted || ...
    ~isempty(rx.ChannelEstimate);
trial.PUCCHControlSINR_dB = rx.MeasuredSINR_dB;
trial.PUCCHReceiverEvidenceSource = ...
    "canonical_typed_pucch_waveform_receiver";
trial.ChannelEstimationLatency_ms = double(sixgr.util.structGet( ...
    rx,"ChannelEstimationLatency_ms",NaN));
trial.EqualizationLatency_ms = double(sixgr.util.structGet( ...
    rx,"EqualizationLatency_ms",NaN));
trial.DecodeLatency_ms = double(sixgr.util.structGet( ...
    rx,"DecodeLatency_ms",NaN));
trial.ReceiverPipelineLatency_ms = double(sixgr.util.structGet( ...
    rx,"ReceiverPipelineLatency_ms",NaN));
trial.ReceiverStageLatencySource = string(sixgr.util.structGet( ...
    rx,"ReceiverStageLatencySource","unavailable"));
trial.NoncoherentSequenceDetection = logical(sixgr.util.structGet( ...
    rx,"NoncoherentSequenceDetection",false));
trial.ChannelEstimationMode = char(string(sixgr.util.structGet( ...
    rx,"ChannelEstimationMode","")));
trial.StrictReceiverEvidenceOk = logical(rx.ReceiverUsable) && ...
    trial.ResourceExtractionAvailable && ...
    trial.ChannelEstimateAvailable && trial.EqualizationAvailable;
trial.StrictOk = logical(trial.Ok) && trial.StrictReceiverEvidenceOk;
trial.Status = localStatus(trial.Ok);
trial.FailureReason = localFailure(trial);
trial.ComputeLatency_ms = 1e3 .* toc(trialPipelineTic);
end

function trial = localEmptyTrial(opt)
trial = struct( ...
    "Ok",false,"Status","FAIL", ...
    "AssignmentRejected",false, ...
    "ReportConstructionRejected",false, ...
    "ResourceMappingRejected",false, ...
    "WaveformGenerationFailed",false, ...
    "ReceiverDTX",false,"ReceiverDecodeFailed",false, ...
    "CRCFailed",false,"ContentMismatch",false, ...
    "WaveformGenerated",false,"StateChanged",false, ...
    "GrantCreated",false,"BitErrors",NaN,"BitsCompared",0, ...
    "NoiseVariance",NaN,"FailureReason","","ErrorID","","ErrorMessage","", ...
    "ErrorStack","", ...
    "Seed",double(opt.Seed),"SNR_dB",double(opt.SNR_dB), ...
    "ChannelProfile",string(opt.ChannelProfile), ...
    "SignalPresent",logical(opt.SignalPresent), ...
    "ExecutionBackend","waveform_truth", ...
    "ApproximationMode","none","EvidenceClass","waveform_truth", ...
    "Receiver",struct(),"Transmitter",struct(),"Channel",struct());
end

function value = localTimingEstimate(carrier,waveform,tx)
value = NaN;
try
    if ~isempty(tx.DMRS.Indices)
        value = double(nrTimingEstimate(carrier,waveform, ...
            tx.DMRS.Indices,tx.DMRS.Symbols));
    else
        value = double(nrTimingEstimate(carrier,waveform,tx.Grid));
    end
catch
    value = NaN;
end
end

function value = localChannelEstimateSource(profile,attempted,format)
if attempted
    value = "pucch_dmrs_per_resource_nrChannelEstimate";
elseif double(format) == 0 && upper(string(profile)) ~= "AWGN"
    value = "not_applicable_format0_noncoherent_sequence_detection";
elseif upper(string(profile)) == "AWGN"
    value = "explicit_awgn_unit_channel";
else
    value = "not_attempted";
end
end

function cfgRuntime = localRuntimeConfig(cfg,carrier,opt)
% Production PUCCH must consume the immutable YAML authority.  Standalone
% unit calls that pass only an nrCarrierConfig receive an explicit minimal
% configuration assembled from their named trial arguments.
if isstruct(cfg)
    cfgRuntime = cfg;
    resolved = sixgr.util.structGet(cfgRuntime,"lls6g.resolvedConfig",[]);
    yamlAuthority = isstruct(resolved) && ~isempty(fieldnames(resolved));
else
    cfgRuntime = struct();
    yamlAuthority = false;
    cfgRuntime.run = struct("seed",double(opt.Seed), ...
        "noiseOperatingMode","standalone_awgn_snr_argument", ...
        "interferenceExecutionMode","none");
    cfgRuntime.phy = struct();
    cfgRuntime.phy.carrier = struct( ...
        "NSizeGrid",double(carrier.NSizeGrid), ...
        "SubcarrierSpacing",double(carrier.SubcarrierSpacing), ...
        "CyclicPrefix",char(string(carrier.CyclicPrefix)), ...
        "NCellID",double(carrier.NCellID));
    cfgRuntime.phy.nTxAnt = 1;
    cfgRuntime.phy.nRxAnt = 1;
    cfgRuntime.scenario = struct("ue",struct("nTxAnt",1), ...
        "bs",struct("nRxAnt",1));
end

requestedProfile = upper(strtrim(string(opt.ChannelProfile)));
if ~ismember(requestedProfile,["AWGN","TDL-A","TDL-B","TDL-C", ...
        "TDL-D","TDL-E","CDL-A","CDL-B","CDL-C","CDL-D","CDL-E", ...
        "NTN-TDL-A","NTN-TDL-B","NTN-TDL-C","NTN-TDL-D"])
    error("sixgr:config:BadChannelProfile", ...
        "PUCCH trial requires AWGN or a concrete TDL-*/CDL-*/NTN-TDL-* profile.");
end
if yamlAuthority
    configuredProfile = upper(strtrim(string( ...
        sixgr.channel.resolveConcreteProfile(cfgRuntime))));
    if configuredProfile ~= requestedProfile
        error("sixgr:config:YAMLChannelProfileBypassed", ...
            ["PUCCH requested channel profile %s, but the resolved YAML " ...
             "authority requires %s."],char(requestedProfile), ...
             char(configuredProfile));
    end
else
    if startsWith(requestedProfile,"NTN-TDL-")
        % The normal runtime channel factory is terrestrial. Keep its state
        % disabled; localRuntimeWaveformPath applies the exact NTN-TDL object.
        cfgRuntime = localSetConcreteChannelProfile(cfgRuntime,"AWGN");
        cfgRuntime = sixgr.util.structSet(cfgRuntime, ...
            "ntn.runtimePUCCHProfile",char(requestedProfile));
    else
        cfgRuntime = localSetConcreteChannelProfile(cfgRuntime,requestedProfile);
    end
    cfgRuntime = sixgr.util.structSet(cfgRuntime,"channel.doppler_Hz", ...
        double(opt.DopplerHz));
    cfgRuntime = sixgr.util.structSet(cfgRuntime,"channel.delaySpread_s", ...
        double(opt.DelaySpreadSeconds));
    cfgRuntime = sixgr.util.structSet(cfgRuntime,"phy.impairments.cfoHz", ...
        double(opt.CFOHz));
    cfgRuntime = sixgr.util.structSet(cfgRuntime, ...
        "phy.impairments.timingOffsetSamples", ...
        double(opt.TimingOffsetSamples));
end
cfgRuntime = sixgr.util.structSet(cfgRuntime, ...
    "lls6g.userContext.RuntimeCurrentDirection","UL");
cfgRuntime = sixgr.util.structSet(cfgRuntime, ...
    "lls6g.userContext.Direction","UL");
cfgRuntime = sixgr.util.structSet(cfgRuntime, ...
    "lls6g.userContext.RuntimeSignalFamily","PUCCH");
cfgRuntime = sixgr.util.structSet(cfgRuntime,"channel.snr_dB", ...
    double(opt.SNR_dB));
end

function cfg = localSetConcreteChannelProfile(cfg,profile)
cfg = sixgr.util.structSet(cfg,"channel.awgnOnly",profile == "AWGN");
cfg = sixgr.util.structSet(cfg,"channel.model",char(profile));
if startsWith(profile,"TDL-")
    cfg = sixgr.util.structSet(cfg,"channel.tdlProfile",char(profile));
elseif startsWith(profile,"CDL-")
    cfg = sixgr.util.structSet(cfg,"channel.cdlProfile",char(profile));
end
end

function [rxWaveform,desiredWaveform,injectedNoise,noiseVariance, ...
        channelMeta,replay,updatedRuntimeState] = ...
        localRuntimeWaveformPath(cfg,tx,opt)
txInfo = struct("OFDM",tx.OFDMInfo);
[txWaveform,cfg,txBoundary] = ...
    sixgr.link.preparePUCCHTransmitWaveform(tx,cfg);
initialState = opt.InitialRuntimeChannelState;
state = sixgr.link.initWaveformTruthChannelState(cfg,tx,txInfo, ...
    "InitialRuntimeChannelState",initialState);
if opt.SignalPresent
    channelInput = txWaveform;
else
    channelInput = complex(zeros(size(txWaveform),"like",txWaveform));
end
replay = struct();
if startsWith(upper(string(opt.ChannelProfile)),"NTN-TDL-")
    [channelWaveform,ntnReplay] = localApplyNTNTDLChannel(channelInput,tx,opt);
    replay = localMergeStruct(replay,ntnReplay);
else
    [channelWaveform,replay,state] = sixgr.link.applyRuntimeFadingChannel( ...
        channelInput,state);
end

sampleRateHz = double(tx.OFDMInfo.SampleRate);
[desiredWaveform,impairmentReplay] = sixgr.link.applyWaveformImpairments( ...
    channelWaveform,cfg,sampleRateHz,"ApplyRFChain",false);
replay = localMergeStruct(replay,impairmentReplay);
replay.PUCCHTransmitBoundary = txBoundary;
replay.PUCCHAppliedTxPower_dBm = double(txBoundary.AppliedPower_dBm);
replay.PUCCHMeasuredTxOutputPower_dBm = double( ...
    txBoundary.MeasuredTxOutputPower_dBm);
replay.PUCCHTxPowerClosureError_dB = double( ...
    txBoundary.PowerClosureError_dB);
replay.TxRFExecutionStatus = char(string(txBoundary.TXRFExecutionStatus));
replay.TxRFStageOrder = char(string(txBoundary.TXRFStageOrder));
replay.TxRFAppliedStageCount = double(txBoundary.TXRFAppliedStageCount);
[interferenceWaveform,interferenceMeta] = ...
    sixgr.link.synthesizeInterferenceWaveform( ...
    "UL",desiredWaveform,replay,opt.InterferenceBundle);
compositeWaveform = desiredWaveform+cast( ...
    interferenceWaveform,"like",desiredWaveform);
replay = localAttachInterferenceReplay(replay,interferenceMeta, ...
    interferenceWaveform,tx,desiredWaveform);
[preFrontEndWaveform,injectedNoise,preFrontEndNoiseVariance,noiseReplay] = ...
    localAddRuntimeNoise(compositeWaveform,desiredWaveform,tx,cfg,opt,replay);
replay = localMergeStruct(replay,noiseReplay);
replay.InjectedNoiseVariance = double(preFrontEndNoiseVariance);
[rxWaveform,replay] = sixgr.link.applyCompositeReceiverFrontEnd( ...
    preFrontEndWaveform,cfg,sampleRateHz,replay,"Direction","UL");
replay = sixgr.link.applyCompositeFrontEndVarianceReplay(replay);
noiseVariance = double(sixgr.util.structGet(replay, ...
    "InjectedNoiseVariancePostCompositeFrontEnd", ...
    preFrontEndNoiseVariance));
if ~(isfinite(noiseVariance) && noiseVariance >= 0)
    error("sixgr:phy:pucch:InvalidRuntimeNoiseVariance", ...
        "PUCCH runtime chain did not produce a finite nonnegative receiver noise variance.");
end

function [waveform,replay] = localApplyNTNTDLChannel(input,tx,opt)
profile=upper(string(opt.ChannelProfile));
if exist("nrTDLChannel","class")~=8 && exist("nrTDLChannel","file")~=2
    error("sixgr:phy:pucch:MissingNTNTDLChannel", ...
        "nrTDLChannel is required for PUCCH profile %s.",char(profile));
end
channel=nrTDLChannel;
channel.DelayProfile=char(profile);
channel.DelaySpread=double(opt.DelaySpreadSeconds);
channel.MaximumDopplerShift=max(0,double(opt.DopplerHz));
channel.SatelliteDopplerShift=0;
channel.NumTransmitAntennas=size(input,2);
channel.NumReceiveAntennas=1;
channel.SampleRate=double(tx.OFDMInfo.SampleRate);
channel.TransmissionDirection='Uplink';
channel.MIMOCorrelation='Low';
channel.Polarization='Co-Polar';
if isprop(channel,'RandomStream'),channel.RandomStream='mt19937ar with seed';end
if isprop(channel,'Seed'),channel.Seed=double(opt.Seed);end
if isprop(channel,'NormalizePathGains'),channel.NormalizePathGains=true;end
if isprop(channel,'NormalizeChannelOutputs'),channel.NormalizeChannelOutputs=true;end
reset(channel);cleanup=onCleanup(@() release(channel)); %#ok<NASGU>
objectInfo=info(channel);
pad=max(0,round(double(sixgr.util.structGet(objectInfo,'MaximumChannelDelay',0))));
padded=[input;complex(zeros(pad,size(input,2),'like',input))];
[raw,pathGains]=channel(padded);
filters=getPathFilters(channel);
timing=max(0,round(double(nrPerfectTimingEstimate(pathGains,filters))));
first=timing+1;last=first+size(input,1)-1;
if last>size(raw,1),raw(end+1:last,:)=complex(0);end %#ok<AGROW>
waveform=raw(first:last,:);
replay=struct('ChannelFadingApplied',true, ...
    'ChannelFadingExecutionStatus','applied_ntn_tdl_waveform_truth', ...
    'ChannelFadingObjectClass','nrTDLChannel', ...
    'ChannelPathGainsAvailable',~isempty(pathGains), ...
    'RuntimeChannelStateUsed',false,'RuntimeChannelLinkKey','pucch_ntn_tdl', ...
    'RuntimeChannelSeed',double(opt.Seed),'RuntimeChannelResetCount',1, ...
    'RuntimeChannelStartSample',1,'RuntimeChannelEndSample',size(input,1), ...
    'RuntimeChannelIdleAdvancedSamples',0,'NTNEnabled',true, ...
    'NTNProfile',profile,'NTNTransmissionDirection','Uplink', ...
    'NTNSatelliteDopplerShift_Hz',0, ...
    'NTNResidualCFOAppliedByImpairmentStage_Hz',double(opt.CFOHz), ...
    'ChannelTimingAlignmentSamples',timing,'ProxyUsed',false,'FallbackUsed',false);
end

runtimeState = sixgr.util.structGet(state,"RuntimeChannelState",struct());
if isstruct(runtimeState) && isfield(runtimeState,"ContractVersion")
    updatedRuntimeState = runtimeState;
else
    updatedRuntimeState = struct();
end
runtimeMeta = sixgr.util.structGet(runtimeState,"Meta",struct());
if startsWith(upper(string(opt.ChannelProfile)),"NTN-TDL-")
    profile = upper(strtrim(string(opt.ChannelProfile)));
else
    profile = upper(strtrim(string(sixgr.channel.resolveConcreteProfile(cfg))));
end
channelMeta = struct( ...
    "Profile",profile, ...
    "Source",string(sixgr.util.structGet(runtimeMeta, ...
        "ChannelObjectSource",sixgr.util.structGet(replay, ...
        "ChannelFadingObjectClass","unit_awgn_channel"))), ...
    "ExecutionBackend","waveform_truth", ...
    "ApproximationMode","none", ...
    "RuntimeChannelStateUsed",logical(sixgr.util.structGet( ...
        replay,"RuntimeChannelStateUsed",false)), ...
    "RuntimeChannelLinkKey",string(sixgr.util.structGet( ...
        replay,"RuntimeChannelLinkKey","")), ...
    "RuntimeChannelPhysicalTxElements",double(sixgr.util.structGet( ...
        replay,"RuntimeChannelPhysicalTxElements",NaN)), ...
    "RuntimeChannelNumRxAntennas",double(sixgr.util.structGet( ...
        runtimeState,"NumRxAnt",size(rxWaveform,2))), ...
    "ChannelUsesSameRuntimeAntennaAssumptions",logical( ...
        sixgr.util.structGet(runtimeMeta, ...
        "ChannelUsesSameRuntimeAntennaAssumptions",false)), ...
    "ChannelUsesCountOnlyAntennaModel",logical(sixgr.util.structGet( ...
        runtimeMeta,"ChannelUsesCountOnlyAntennaModel",false)), ...
    "ChannelArrayHandlingStatus",string(sixgr.util.structGet( ...
        runtimeMeta,"ChannelArrayHandlingStatus","")), ...
    "ChannelArrayHandlingBlocker",string(sixgr.util.structGet( ...
        runtimeMeta,"ChannelArrayHandlingBlocker","")), ...
    "PhaseNoiseBackend",string(sixgr.util.structGet( ...
        replay,"PhaseNoiseBackend","disabled")), ...
    "PhaseNoiseTruthClassification",string(sixgr.util.structGet( ...
        replay,"PhaseNoiseTruthClassification","disabled")));
end

function replay = localAttachInterferenceReplay( ...
        replay,meta,interferenceWaveform,tx,desiredWaveform)
replay.InterferenceMode = char(string(sixgr.util.structGet( ...
    meta,"InterferenceMode","none")));
replay.InterferenceContributorCount = double(sixgr.util.structGet( ...
    meta,"Contributors",0));
replay.InterferenceAggregatedRxPower_dBm = double(sixgr.util.structGet( ...
    meta,"AggregatedRxPower_dBm",NaN));
replay.InterferencePowerSource = char(string(sixgr.util.structGet( ...
    meta,"PowerSource","")));
replay.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet( ...
    meta,"FullPerLinkChannelTruthUsed",false));
replay.InterferenceChannelObjectSource = char(string(sixgr.util.structGet( ...
    meta,"ChannelObjectSource","")));
replay.InterferenceChannelObjectClass = char(string(sixgr.util.structGet( ...
    meta,"ChannelObjectClass","")));
replay.InterferenceChannelArrayHandlingStatus = char(string( ...
    sixgr.util.structGet(meta,"ChannelArrayHandlingStatus","")));
replay.InterferenceChannelArrayHandlingBlocker = char(string( ...
    sixgr.util.structGet(meta,"ChannelArrayHandlingBlocker","")));
replay.InterferenceUsesSameRuntimeAntennaAssumptions = logical( ...
    sixgr.util.structGet(meta, ...
    "ChannelUsesSameRuntimeAntennaAssumptions",false));
replay.InterferenceContributionTensorAvailable = logical( ...
    sixgr.util.structGet(meta,"ContributionTensorAvailable",false));
replay.InterferenceContributionSourceIdSet = char(string( ...
    sixgr.util.structGet(meta,"ContributionSourceIdSet","")));
replay.InterferenceSampleExactSuperpositionOk = logical( ...
    sixgr.util.structGet(meta,"SampleExactSuperpositionOk",true));
replay.InterferenceSampleExactSuperpositionError = double( ...
    sixgr.util.structGet(meta,"SampleExactSuperpositionError",0));
[~, activeSymbolIndices] = localActiveOFDMMeanPower(desiredWaveform,tx);
replay.InterferenceWaveformVariance = localActiveOFDMMeanPower( ...
    interferenceWaveform,tx,activeSymbolIndices);
if logical(sixgr.util.structGet(meta,"ContributionTensorAvailable",false))
    replay.InterferenceContributionTensor = meta.ContributionTensor;
end
if logical(sixgr.util.structGet(meta,"InterferenceCovarianceAvailable",false))
    replay.InterferenceCovariance = meta.InterferenceCovariance;
    replay.InterferenceCovarianceAvailableFromContributions = true;
end
end

function [waveform,noise,nVar,info] = ...
        localAddRuntimeNoise(compositeWaveform,desiredWaveform,tx,cfg,opt,impairmentReplay)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.noiseOperatingMode","receiver_noise_figure_thermal_noise"))));
switch mode
    case "standalone_awgn_snr_argument"
        signalEnergy = localOccupiedResourceEnergy(tx);
        [waveform,reference] = sixgr.phy.waveform.addOccupiedREAWGN( ...
            compositeWaveform,tx.Carrier,double(opt.SNR_dB), ...
            "SignalEnergyPerOccupiedRE",signalEnergy);
        noise = waveform-compositeWaveform;
        nVar = double(reference.SampleNoiseVariance);
        info = struct( ...
            "AppliedAWGNSNR_dB",double(reference.RequestedEsN0_dB), ...
            "InjectedNoiseVariance",nVar, ...
            "NoiseVarianceSource", ...
                "standalone_awgn_occupied_grid_esn0_reference", ...
            "NoiseOperatingMode",char(mode), ...
            "SNRReferencePlane", ...
                "occupied_resource_grid_re_after_ofdm_demodulation", ...
            "SampleToGridNoiseVarianceGain", ...
                double(reference.SampleToGridNoiseVarianceGain), ...
            "GridNoiseVariance",double(reference.GridNoiseVariance), ...
            "GridNoiseVarianceDomain","resource_grid_pre_equalization", ...
            "SampleNoiseVariance",nVar, ...
            "SampleNoiseVarianceDomain", ...
                "receiver_sample_waveform_pre_composite_front_end", ...
            "NoiseCalibrationVersion",char(string(reference.Version)));
    case "receiver_noise_figure_thermal_noise"
        referencePower = localActiveOFDMMeanPower(desiredWaveform,tx);
        nVar = sixgr.link.resolveReceiverThermalNoiseVariance(impairmentReplay);
        noise = sqrt(nVar/2).*(randn(size(desiredWaveform), ...
            "like",real(desiredWaveform))+1i*randn(size(desiredWaveform), ...
            "like",real(desiredWaveform)));
        waveform = compositeWaveform+cast(noise,"like",compositeWaveform);
        info = struct( ...
            "AppliedAWGNSNR_dB",NaN, ...
            "AppliedNoiseSNR_dB",10*log10(referencePower/nVar), ...
            "InjectedNoiseVariance",double(nVar), ...
            "NoiseVarianceSource","receiver_thermal_psd_times_sample_rate_absolute_sqrt_mW", ...
            "NoiseOperatingMode",char(mode), ...
            "SNRReferencePlane", ...
                "receiver_sample_waveform_pre_composite_front_end", ...
            "SampleNoiseVariance",double(nVar), ...
            "SampleNoiseVarianceDomain", ...
                "receiver_sample_waveform_pre_composite_front_end", ...
            "GridNoiseVariance",NaN, ...
            "GridNoiseVarianceDomain","not_available");
    otherwise
        error("sixgr:phy:pucch:UnsupportedNoiseOperatingMode", ...
            "Unsupported PUCCH noise operating mode '%s'.",char(mode));
end
end

function out = localMergeStruct(out,extra)
if ~isstruct(extra)
    return;
end
names = fieldnames(extra);
for i = 1:numel(names)
    out.(names{i}) = extra.(names{i});
end
end

function value = localOccupiedResourceEnergy(tx)
grid = sixgr.util.structGet(tx,"Grid",[]);
if isempty(grid)
    value = 1;
    return;
end
samples = grid(abs(grid) > 0);
if isempty(samples)
    value = 1;
else
    value = double(mean(abs(samples(:)).^2,"omitnan"));
end
if ~(isfinite(value) && value > 0)
    value = 1;
end
try
    rawWaveform = sixgr.phy.waveform.ofdmModulate(tx.Carrier,grid);
    rawPower = localActiveOFDMMeanPower(rawWaveform,tx);
    appliedPower = localActiveOFDMMeanPower(tx.Waveform,tx);
    if isfinite(rawPower) && rawPower > 0 && ...
            isfinite(appliedPower) && appliedPower > 0
        value = value*(appliedPower/rawPower);
    end
catch ME
    failure = MException("sixgr:phy:pucch:NoiseReferenceReconstructionFailed", ...
        "PUCCH occupied-RE Es/N0 requires the exact transmitter OFDM power scale: %s", ...
        ME.message);
    failure = addCause(failure,ME);
    throwAsCaller(failure);
end
end

function value = localFiniteWaveformPower(waveform)
value = NaN;
if isempty(waveform)
    return;
end
samples = waveform(:);
mask = isfinite(real(samples)) & isfinite(imag(samples));
if any(mask)
    value = double(mean(abs(samples(mask)).^2,"omitnan"));
end
end

function [value, activeSymbolIndices] = localActiveOFDMMeanPower( ...
        waveform,tx,activeSymbolIndices)
if nargin < 3
    activeSymbolIndices = [];
end
txInfo = struct("OFDM",sixgr.util.structGet(tx,"OFDMInfo",struct()));
args = {};
if ~isempty(activeSymbolIndices)
    args = {"ActiveSymbolIndices",activeSymbolIndices};
end
[~,perPortPower,info] = sixgr.rf.measureActiveOFDMTotalPower( ...
    waveform,txInfo,args{:});
value = double(mean(perPortPower,"omitnan"));
activeSymbolIndices = double(info.ActiveSymbolIndices(:));
end

function [errors,count,mismatch] = localCompare(reference,decoded)
count = min(numel(reference),numel(decoded));
errors = abs(numel(reference)-numel(decoded));
if count > 0
    errors = errors+sum(reference(1:count)~=decoded(1:count));
end
mismatch = errors ~= 0;
end

function value = localErrorVector(reference,decoded)
n=max(numel(reference),numel(decoded));
bits=false(n,1);
common=min(numel(reference),numel(decoded));
if common>0,bits(1:common)=reference(1:common)~=decoded(1:common);end
if common<n,bits(common+1:end)=true;end
value=sixgr.phy.pucch.PUCCHUtil.bitString(int8(bits));
end

function value = localAWGNSNR(opt)
if upper(string(opt.ChannelProfile))=="AWGN",value=double(opt.SNR_dB);
else,value=NaN;end
end

function value = localAvailableText(available,yesValue,noValue)
if logical(available)
    value = string(yesValue);
else
    value = string(noValue);
end
end

function value = localCRCOutcome(applicable,failed)
if ~applicable,value="not_applicable";
elseif failed,value="fail";
else,value="pass";end
end

function value = localDetectionOutcome(dtx,mismatch)
if dtx,value="dtx";
elseif mismatch,value="missed";
else,value="detected";end
end

function value = localStatus(ok)
if ok, value = "PASS"; else, value = "FAIL"; end
end

function value = localFailure(trial)
if trial.Ok, value = ""; ...
elseif trial.ReceiverDTX, value = "receiver_dtx"; ...
elseif trial.CRCFailed, value = "crc_failure"; ...
elseif trial.ContentMismatch, value = "content_mismatch"; ...
else, value = "receiver_failure"; end
end
