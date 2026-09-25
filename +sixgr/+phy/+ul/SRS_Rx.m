function [rx, info] = SRS_Rx(rxWaveform, cfg, varargin)
%SRS_Rx Receive and estimate channel from an SRS-only waveform.
%
%   [RX,INFO] = sixgr.phy.ul.SRS_Rx(RXWAVEFORM, CFG) demodulates the OFDM
%   waveform, extracts SRS REs, and estimates the channel response.
%
%   Name-Value options:
%     "Carrier"   : nrCarrierConfig override
%     "SRS"       : nrSRSConfig override
%     "NoiseVar"  : explicit runtime noise variance metadata
%     "NoiseVarDomain": "time", "grid", "frequency", or "auto"
%     "ConfiguredNoiseVariance": explicit configured/derived AWGN variance
%
%   Outputs (RX struct):
%     .Hest        : estimated channel (K-by-L-by-NRx-by-NTxPorts)
%     .NoiseVar    : estimated or provided noise variance
%     .NoiseVarStatus : "OK" or "NOT_AVAILABLE"
%     .NoiseVarSource : provenance for the used/unavailable noise variance
%     .RxGrid      : received resource grid
%     .SRSIndices  : SRS indices
%     .SRSSymbols  : reference SRS symbols

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('SRS', [], @(x) isempty(x) || isobject(x));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('ConfiguredNoiseVariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ConfiguredNoiseVarianceSource', 'configured_awgn_derivation', @(x) ischar(x) || isstring(x));
ip.addParameter('StrictNoiseVarianceRequired', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('TimingSearchWindowSamples',[],@(x)isempty(x)||(isnumeric(x)&&numel(x)==2));
ip.addParameter('ReceivedExecutionEvidence',struct(),@(x)isstruct(x)&&isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% SRS config
if isempty(opt.SRS)
    strictSRS = sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
    srs = strictSRS.ToolboxSRS;
else
    srs = opt.SRS;
end

% SRS indices and symbols
[srsInd, srsInfo] = nrSRSIndices(carrier, srs);
srsSym = nrSRS(carrier, srs);

timing=struct('TimingOffsetSamples',NaN,'AppliedTimingCorrectionSamples',0, ...
    'TimingSource',"caller_aligned_legacy_observation_not_measured", ...
    'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
if ~isempty(opt.TimingSearchWindowSamples)
    [rxWaveform,timing]=sixgr.phy.sync.alignULReferenceObservation( ...
        carrier,rxWaveform,srsInd,srsSym,opt.TimingSearchWindowSamples);
end
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);

% Channel estimation
Hest = [];
nVarEst = [];
estInfo = struct();
estimator=string(sixgr.util.structGet(cfg,'phy.srs.runtimeChannelEstimator','nr_channel_estimate'));
assert(isscalar(estimator) && any(estimator==["nr_channel_estimate","flat_static_awgn_ls"]), ...
    'sixgr:phy:ul:InvalidSRSEstimator','Select a supported explicit SRS estimator.');
if estimator=="flat_static_awgn_ls"
    assert(isempty(opt.NoiseVar) && isempty(opt.ConfiguredNoiseVariance), ...
        'sixgr:phy:ul:FlatSRSNoiseOverrideForbidden', ...
        'Flat practical SRS estimates noise from received pilots, not injected variance.');
    assert(strcmpi(string(sixgr.util.structGet(cfg,'channel.model','')),'AWGN') && ...
        sixgr.channel.IdentityAWGNRuntime.enabled(cfg), ...
        'sixgr:phy:rx:FlatAWGNObservationRequired','Flat SRS LS is restricted to the explicit AWGN lab operator.');
    modelEvidence=sixgr.phy.rx.assertFlatStaticAWGNObservation(opt.ReceivedExecutionEvidence);
    reference=nrResourceGrid(carrier,srs.NumSRSPorts);
    reference(srsInd)=srsSym;
    K=size(rxGrid,1); L=size(rxGrid,2); R=size(rxGrid,3); P=double(srs.NumSRSPorts);
    X=reshape(reference,K*L,P); Y=reshape(rxGrid,K*L,R);
    occupied=any(X~=0,2);
    estInfo=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(Y(occupied,:),X(occupied,:));
    Hest=repmat(reshape(estInfo.GainPerPortReceiveBranch.',1,1,R,P),K,L,1,1);
    nVarEst=estInfo.NoiseVariance;
    estInfo.ModelEvidence=modelEvidence;
    estInfo.EngineUsed="received_joint_flat_static_awgn_ls";
    estInfo.FrequencyHoppingHandled=localSRSFrequencyHoppingEnabled(srs);
    estInfo.PrimaryEstimatorFallbackUsed=false;
else
try
    [avgWindow, srsSymbols] = localSRSChannelEstimateWindow(carrier, srs, srsInd, srsInfo);
    cdmLengths = localSRSCDMLengths(srs);
    if localSRSFrequencyHoppingEnabled(srs) && numel(srsSymbols) > 1
        [Hest, nVarEst, estInfo] = localEstimateSRSHopped( ...
            carrier, rxGrid, srsInd, srsSym, srsSymbols, cdmLengths);
    else
        [Hest, nVarEst, estInfo] = localEstimateSRSNoHop( ...
            carrier, rxGrid, srsInd, srsSym, cdmLengths, avgWindow);
    end
catch primaryCause
    try
        [Hest, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, srsInd, srsSym);
        if ~isstruct(estInfo), estInfo = struct(); end
        estInfo.PrimaryEstimatorFallbackUsed = true;
        estInfo.PrimaryEstimatorFailureIdentifier = string(primaryCause.identifier);
        estInfo.PrimaryEstimatorFailureMessage = string(primaryCause.message);
    catch fallbackCause
        Hest = [];
        nVarEst = [];
        estInfo = struct( ...
            'PrimaryEstimatorFallbackUsed',true, ...
            'PrimaryEstimatorFailureIdentifier',string(primaryCause.identifier), ...
            'PrimaryEstimatorFailureMessage',string(primaryCause.message), ...
            'FallbackEstimatorFailureIdentifier',string(fallbackCause.identifier), ...
            'FallbackEstimatorFailureMessage',string(fallbackCause.message));
    end
end
end
noiseCandidate = opt.NoiseVar;
noiseSource = "runtime_metadata";
noiseTransformInfo = struct( ...
    "InputDomain", "grid", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "runtime_channel_estimate_grid_domain");
configuredNoiseTransformInfo = struct( ...
    "InputDomain", "time", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "not_requested");
if isempty(noiseCandidate)
    noiseCandidate = nVarEst;
    noiseSource = "runtime_channel_estimate";
    if estimator=="flat_static_awgn_ls"
        noiseSource="received_flat_static_awgn_joint_ls_residual_dof_corrected";
    end
else
    [noiseCandidate, noiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        noiseCandidate, ofdmInfo, ...
        "InputDomain", opt.NoiseVarDomain, ...
        "Source", noiseSource);
end
configuredNoiseVariance = opt.ConfiguredNoiseVariance;
if ~isempty(configuredNoiseVariance)
    [configuredNoiseVariance, configuredNoiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        configuredNoiseVariance, ofdmInfo, ...
        "InputDomain", "time", ...
        "Source", opt.ConfiguredNoiseVarianceSource);
end
[nVar, noiseStatus] = sixgr.phy.ul.resolveULNoiseVariance(noiseCandidate, cfg, ...
    "ChannelType", "SRS", ...
    "OriginalSource", noiseSource, ...
    "StrictRequired", opt.StrictNoiseVarianceRequired, ...
    "ConfiguredNoiseVariance", configuredNoiseVariance, ...
    "ConfiguredNoiseVarianceSource", opt.ConfiguredNoiseVarianceSource);
nVar = double(nVar);

rx = struct();
rx.Timing=timing;
rx.Hest = Hest;
rx.NoiseVar = nVar;
rx.NoiseVarDomain = "resource_grid_pre_equalization";
rx.NoiseVarTransformSource = char(string(sixgr.util.structGet(noiseTransformInfo, "TransformSource", "")));
rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet(noiseTransformInfo, "SampleToGridNoiseVarianceGain", NaN));
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
rx.MeasurementAttempted = logical(noiseStatus.IsValid);
rx.MeasurementUsable = logical(noiseStatus.IsValid);
rx.FailureReason = "";
if ~logical(noiseStatus.IsValid)
    rx.FailureReason = char(string(noiseStatus.Reason));
end
rx.RxGrid = rxGrid;
rx.Carrier = carrier;
rx.SRS = srs;
rx.SRSIndices = srsInd;
rx.SRSSymbols = srsSym;

info = struct();
info.CarrierInfo = cinfo;
info.OFDMInfo = ofdmInfo;
info.SRSInfo = srsInfo;
info.ChannelEstimation = estInfo;
info.NoiseVariance = noiseStatus;
info.OFDMNoiseTransform = sixgr.util.structGet(ofdmInfo, "NoiseTransform", struct());
info.NoiseVarianceTransform = noiseTransformInfo;
info.ConfiguredNoiseVarianceTransform = configuredNoiseTransformInfo;

end

function [Hest, nVarEst, estInfo] = localEstimateSRSNoHop(carrier, rxGrid, srsInd, srsSym, cdmLengths, avgWindow)
[Hest, nVarEst, estInfo] = nrChannelEstimate(carrier, rxGrid, srsInd, srsSym, ...
    'CDMLengths', cdmLengths, 'AveragingWindow', avgWindow);
if isstruct(estInfo)
    estInfo.AveragingWindow = avgWindow;
    estInfo.CDMLengths = cdmLengths;
    estInfo.CDMLengthsSource = "nr_srs_cyclic_shift_port_multiplexing";
    estInfo.FrequencyHoppingHandled = false;
end
end

function [Hest, nVarEst, estInfo] = localEstimateSRSHopped(carrier, rxGrid, srsInd, srsSym, srsSymbols, cdmLengths)
Hest = [];
nVals = [];
estInfo = struct("AveragingWindow", [0 0], "CDMLengths", cdmLengths, ...
    "CDMLengthsSource", "nr_srs_cyclic_shift_port_multiplexing", ...
    "FrequencyHoppingHandled", true, "HopCount", numel(srsSymbols));
if isempty(srsInd)
    nVarEst = NaN;
    return;
end
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
nPorts = max(1, ceil(max(double(srsInd(:))) / max(K * L, 1)));
[~, symIdx, ~] = ind2sub([K, L, max(1, nPorts)], double(srsInd(:)));
srsSymVec = srsSym(:);
for ii = 1:numel(srsSymbols)
    sym = double(srsSymbols(ii));
    mask = symIdx == sym;
    if ~any(mask)
        continue;
    end
    [Hpart, nPart, infoPart] = localEstimateSRSNoHop( ...
        carrier, rxGrid, srsInd(mask), srsSymVec(mask), cdmLengths, [0 0]);
    if isempty(Hpart)
        continue;
    end
    if isempty(Hest)
        Hest = complex(zeros(size(Hpart), "like", Hpart));
    end
    if ndims(Hpart) >= 2 && sym >= 1 && sym <= size(Hpart, 2)
        Hest(:, sym, :, :) = Hpart(:, sym, :, :);
    else
        Hest = Hpart;
    end
    if isfinite(double(nPart)) && double(nPart) >= 0
        nVals(end+1, 1) = double(nPart); %#ok<AGROW>
    end
    if ii == 1 && isstruct(infoPart)
        estInfo.FirstHopInfo = infoPart;
    end
end

if isempty(nVals)
    nVarEst = NaN;
else
    nVarEst = mean(nVals, "omitnan");
end
end

function cdmLengths = localSRSCDMLengths(srs)
% nrSRS multiplexes its antenna ports by cyclic shifts of the same base
% sequence. The practical channel estimator must jointly despread every
% configured SRS port; treating those orthogonal ports as independent
% residuals classifies their signal energy as noise.
nPorts = double(srs.NumSRSPorts);
if ~(isscalar(nPorts) && isfinite(nPorts) && any(nPorts == [1 2 4]))
    error('sixgr:phy:ul:UnsupportedSRSPortCount', ...
        'SRS receiver requires NumSRSPorts to be one of [1 2 4], got %g.',nPorts);
end
comb = double(srs.KTC);
if ~(isscalar(comb) && isfinite(comb) && any(comb == [2 4]))
    error('sixgr:phy:ul:UnsupportedSRSComb', ...
        'SRS receiver requires KTC to be 2 or 4, got %g.',comb);
end
% nrChannelEstimate consumes the complete SRS port set jointly. KTC changes
% the occupied-RE pattern, but all configured SRS ports remain members of
% the frequency-domain orthogonal cover presented to the estimator.
cdmLengths = [nPorts 1];
end

function [avgWindow, srsSymbols] = localSRSChannelEstimateWindow(carrier, srs, srsInd, srsInfo)
% nrSRSConfig owns the native comb as KTC. Do not pass this handle object to
% struct-only configuration helpers: doing so used to throw and silently
% divert all SRS reception to the generic fallback estimator.
combSize = double(srs.KTC);
if ~(isscalar(combSize) && isfinite(combSize) && any(combSize == [2 4]))
    error('sixgr:phy:ul:UnsupportedSRSComb', ...
        'SRS receiver requires KTC to be 2 or 4, got %g.',combSize);
end
srsSymbols = [];
if ~isempty(srsInd)
    K = double(carrier.NSizeGrid) * 12;
    L = double(carrier.SymbolsPerSlot);
    nPorts = max(1, round(double(srs.NumSRSPorts)));
    [~, symIdx, ~] = ind2sub([K, L, nPorts], double(srsInd(:)));
    srsSymbols = unique(double(symIdx(:)), "stable");
end
if combSize >= 4 || numel(srsSymbols) <= 1
    avgWindow = [0 0];
else
    avgWindow = [0 max(0, numel(srsSymbols) - 1)];
end
end

function tf = localSRSFrequencyHoppingEnabled(srs)
try
    bSRS = double(srs.BSRS);
    bHop = double(srs.BHop);
catch
    tf = false;
    return;
end
% TS 38.211 / nrSRSConfig native frequency hopping is active when b_hop is
% smaller than B_SRS. There is no nrSRSConfig.FrequencyHopping property.
tf = isscalar(bSRS) && isfinite(bSRS) && isscalar(bHop) && ...
    isfinite(bHop) && bSRS > 0 && bHop < bSRS;
end

% -------------------------------------------------------------------------
