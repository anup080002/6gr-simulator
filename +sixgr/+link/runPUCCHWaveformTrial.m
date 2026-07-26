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
parse(p,cfg,varargin{:});
opt = p.Results;

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
    tx = sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
        carrier,opt.Assignment,opt.Report);
    trial.WaveformGenerated = true;
catch ME
    trial.WaveformGenerationFailed = true;
    trial.ErrorID = string(ME.identifier);
    trial.FailureReason = "waveform_generation_failed";
    return;
end

rng(double(opt.Seed),"twister");
if opt.SignalPresent
    [channelWaveform,channelMeta] = localChannel( ...
        tx.Waveform,carrier,opt);
else
    channelWaveform = complex(zeros(size(tx.Waveform)));
    channelMeta = struct("Profile",string(opt.ChannelProfile), ...
        "ExecutionBackend","waveform_truth","ApproximationMode","none");
end
channelWaveform = localApplyOffsets(channelWaveform,tx.OFDMInfo,opt);
if ~isempty(fieldnames(opt.PhaseNoiseConfig))
    phaseNoise = sixgr.rf.PhaseNoiseModel(opt.PhaseNoiseConfig, ...
        double(tx.OFDMInfo.SampleRate),double(opt.Seed));
    channelWaveform = phaseNoise.apply(channelWaveform, ...
        double(tx.OFDMInfo.SampleRate));
    channelMeta.PhaseNoiseBackend = string(phaseNoise.Backend);
    channelMeta.PhaseNoiseTruthClassification = ...
        string(phaseNoise.TruthClassification);
else
    channelMeta.PhaseNoiseBackend = "disabled";
    channelMeta.PhaseNoiseTruthClassification = "disabled";
end
signalPower = mean(abs(channelWaveform(:)).^2);
if ~opt.SignalPresent || signalPower <= 0
    signalPower = mean(abs(tx.Waveform(:)).^2);
end
noiseVariance = max(signalPower/10^(double(opt.SNR_dB)/10),eps);
noise = sqrt(noiseVariance/2)*(randn(size(channelWaveform))+ ...
    1i*randn(size(channelWaveform)));
rxWaveform = channelWaveform+noise;
measuredNoisePower = mean(abs(noise(:)).^2);
trial.InputMeasuredSINR_dB = 10*log10(max(signalPower,eps)/ ...
    max(measuredNoisePower,eps));
trial.InputEVMPercent = 100*sqrt(max(measuredNoisePower,eps)/ ...
    max(signalPower,eps));
trial.NoiseVariance = noiseVariance;
trial.Channel = channelMeta;
[estimatedCFO,cfoInfo] = sixgr.phy.rx.estimateCFOFromCyclicPrefix( ...
    rxWaveform,tx.OFDMInfo,double(tx.OFDMInfo.SampleRate));
trial.EstimatedCFO_Hz = double(estimatedCFO);
trial.CFOEstimatorInfo = cfoInfo;
trial.EstimatedTimingOffsetSamples = localTimingEstimate( ...
    carrier,rxWaveform,tx);

try
    rx = sixgr.phy.pucch.PUCCHReceiver.receive( ...
        rxWaveform,carrier,opt.Assignment,context, ...
        "NoiseVariance",noiseVariance, ...
        "NoiseVarianceDomain","sample", ...
        "ChannelProfile",opt.ChannelProfile, ...
        "DetectionThreshold",opt.DetectionThreshold);
catch ME
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
trial.ChannelModel = string(opt.ChannelProfile);
trial.ConfiguredSNR_dB = double(opt.SNR_dB);
trial.AppliedAWGNSNR_dB = localAWGNSNR(opt);
trial.NoiseVarStatus = "OK";
trial.NoiseVarSource = "calibrated_sample_to_grid_transform";
trial.NoiseVarReason = "";
trial.NoiseVarStrictFailure = false;
trial.ReceiverHestSINR_dB = rx.MeasuredSINR_dB;
trial.ReceiverHestSINRApplicable = opt.Assignment.Format >= 2;
trial.ReceiverHestSINRSource = "pucch_receiver_resource_measurement";
trial.ReceiverHestSINRValueRole = "estimated";
trial.ReceiverHestSINRValueStatus = "OK";
trial.MeasuredTrialSINR_dB = rx.MeasuredSINR_dB;
trial.MeasuredTrialSINRSource = "pucch_receiver_resource_measurement";
trial.MeasuredTrialSINRValueRole = "measured";
trial.MeasuredTrialSINRValueStatus = "OK";
trial.MeasuredSINR_dB = rx.MeasuredSINR_dB;
trial.PostEqSINR_dB = rx.MeasuredSINR_dB;
trial.PostEqSINRSource = "pucch_receiver_resource_measurement";
trial.PostEqSINRValueRole = "measured";
trial.PostEqSINRValueStatus = "OK";
trial.SINRValueRole = "measured";
trial.SINRSource = "pucch_receiver_resource_measurement";
trial.SINRValueStatus = "OK";
trial.SINRValueDefinition = "post_equalization_resource_sinr";
trial.CRCOutcome = localCRCOutcome(trial.CRCApplicable,trial.CRCFailed);
trial.DetectionOutcome = localDetectionOutcome(rx.DTX,contentMismatch);
trial.Crash = false;
trial.CrashSource = "";
trial.CrashMessage = "";
trial.UsedOracleFields = "";
trial.Notes = "Waveform-backed PUCCH through typed report, assignment and oracle-free receiver.";
trial.Ok = ~trial.ReceiverDTX && ~trial.CRCFailed && ...
    ~trial.ContentMismatch && logical(opt.SignalPresent);
if ~opt.SignalPresent
    trial.Ok = rx.DTX;
end
trial.ResourceExtractionAttempted = true;
trial.ResourceExtractionAvailable = true;
trial.ChannelEstimateAttempted = opt.Assignment.Format >= 2 && ...
    upper(string(opt.ChannelProfile)) ~= "AWGN";
trial.ChannelEstimateAvailable = ~trial.ChannelEstimateAttempted || ...
    ~isempty(rx.ChannelEstimate);
trial.ChannelEstimateSource = localChannelEstimateSource( ...
    opt.ChannelProfile,trial.ChannelEstimateAttempted);
trial.EqualizationAttempted = trial.ChannelEstimateAttempted;
trial.EqualizationAvailable = ~trial.EqualizationAttempted || ...
    ~isempty(rx.ChannelEstimate);
trial.PUCCHControlSINR_dB = rx.MeasuredSINR_dB;
trial.PUCCHReceiverEvidenceSource = ...
    "canonical_typed_pucch_waveform_receiver";
trial.StrictReceiverEvidenceOk = logical(rx.ReceiverUsable) && ...
    trial.ResourceExtractionAvailable && ...
    trial.ChannelEstimateAvailable && trial.EqualizationAvailable;
trial.StrictOk = logical(trial.Ok) && trial.StrictReceiverEvidenceOk;
trial.Status = localStatus(trial.Ok);
trial.FailureReason = localFailure(trial);
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

function value = localChannelEstimateSource(profile,attempted)
if attempted
    value = "pucch_dmrs_per_resource_nrChannelEstimate";
elseif upper(string(profile)) == "AWGN"
    value = "explicit_awgn_unit_channel";
else
    value = "not_attempted";
end
end

function [waveform,meta] = localChannel(waveform,carrier,opt)
profile = upper(string(opt.ChannelProfile));
ofdm = nrOFDMInfo(carrier);
switch profile
    case "AWGN"
        source = "unit_awgn_channel";
    case {"TDL-A","TDL-B","TDL-C","TDL-D","TDL-E"}
        channel = nrTDLChannel;
        channel.DelayProfile = profile;
        channel.DelaySpread = double(opt.DelaySpreadSeconds);
        channel.MaximumDopplerShift = double(opt.DopplerHz);
        channel.SampleRate = ofdm.SampleRate;
        channel.NumTransmitAntennas = 1;
        channel.NumReceiveAntennas = 1;
        waveform = channel(waveform);
        source = "nrTDLChannel";
    case {"CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"}
        channel = nrCDLChannel;
        channel.DelayProfile = profile;
        channel.DelaySpread = double(opt.DelaySpreadSeconds);
        channel.MaximumDopplerShift = double(opt.DopplerHz);
        channel.SampleRate = ofdm.SampleRate;
        channel.TransmitAntennaArray.Size = [1 1 1 1 1];
        channel.ReceiveAntennaArray.Size = [1 1 1 1 1];
        waveform = channel(waveform);
        source = "nrCDLChannel";
    otherwise
        error("sixgr:config:BadChannelProfile", ...
            "PUCCH trial requires AWGN or a concrete TDL-*/CDL-* profile.");
end
meta = struct("Profile",profile,"Source",source, ...
    "ExecutionBackend","waveform_truth","ApproximationMode","none");
end

function waveform = localApplyOffsets(waveform,ofdm,opt)
if opt.TimingOffsetSamples ~= 0
    offset = double(opt.TimingOffsetSamples);
    if offset > 0
        waveform = [zeros(offset,size(waveform,2));waveform];
        waveform = waveform(1:end-offset,:);
    else
        offset = abs(offset);
        waveform = [waveform(offset+1:end,:);zeros(offset,size(waveform,2))];
    end
end
if opt.CFOHz ~= 0
    n = (0:size(waveform,1)-1).';
    waveform = waveform.*exp(1i*2*pi*double(opt.CFOHz)*n/ofdm.SampleRate);
end
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
