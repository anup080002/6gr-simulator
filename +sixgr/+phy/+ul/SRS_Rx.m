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
[nullRENoise, nullRENoiseInfo] = localEstimateSRSNullREDisturbance( ...
    rxGrid, srsInd, double(srs.NumSRSPorts));
if estimator=="nr_channel_estimate" && isfinite(nullRENoise) && nullRENoise>=0
    % nrChannelEstimate's residual is a channel-estimator diagnostic.  On a
    % frequency-selective multiport SRS it can contain interpolation/CDM
    % modelling error and must not be relabelled as receiver noise.  The
    % unoccupied comb REs in the same SRS symbols are an independent,
    % practical receiver observation of noise plus ICI/interference.
    estInfo.ChannelEstimatorResidualNoiseVariance = double(nVarEst);
    estInfo.NullREDisturbance = nullRENoiseInfo;
    nVarEst = nullRENoise;
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
    if estimator=="nr_channel_estimate" && ...
            string(sixgr.util.structGet(nullRENoiseInfo,"Status",""))=="available"
        noiseSource = "received_srs_inband_null_re_disturbance";
    end
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
rsrp = localMeasureSRSReferencePower(Hest, srsInd, srsSym, ...
    size(rxGrid,1), size(rxGrid,2), size(rxGrid,3), double(srs.NumSRSPorts));
rx.SRSRSRPPerPortReceiveBranch_UnitOccupiedRE_Es = rsrp.PerPortReceiveBranch;
rx.SRSRSRPPerReceiveAntenna_UnitOccupiedRE_Es = rsrp.PerReceiveAntenna;
rx.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = rsrp.PerReceiveAntenna_dB;
rx.SRS_RSRP_dB_re_UnitOccupiedRE_Es = rsrp.Aggregate_dB;
rx.SRSRSRPSource = rsrp.Source;
rx.SRSRSRPStatus = rsrp.Status;
[leakage, leakageStatus] = localMeasureSRSInterPortLeakage( ...
    Hest, srsInd, srsSym, size(rxGrid,1), size(rxGrid,2), ...
    size(rxGrid,3), double(srs.NumSRSPorts));
rx.SRSInterPortLeakageMatrix_dB = leakage;
rx.SRSInterPortLeakageMatrixJSON = string(jsonencode(leakage));
rx.SRSInterPortLeakageWorst_dB = localFiniteMaximum(leakage);
rx.SRSInterPortLeakageStatus = leakageStatus;
rx.SRSInterPortLeakageSource = ...
    "received_per_re_srs_channel_estimate_independent_code_projection_not_antenna_crosstalk";
rx.SRS_RSRP_dBm = NaN;
rx.SRSRSRPPerReceiveAntenna_dBm = nan(size(rsrp.PerReceiveAntenna));
rx.SRSAbsolutePowerStatus = "not_available_normalized_or_uncalibrated_sample_plane";
if ~sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)
    powerContext = sixgr.util.structGet(cfg,'lls6g.runtimePowerContext',struct());
    physical = string(sixgr.util.structGet(powerContext, ...
        'WaveformAmplitudeUnit','')) == "sqrt_mW" && ...
        logical(sixgr.util.structGet(powerContext,'PhysicalDevicePowerClaim',false)) && ...
        ~logical(sixgr.util.structGet(opt.ReceivedExecutionEvidence, ...
        'CompositeReceiverFrontEndApplied',false));
    if physical
        nfft = double(ofdmInfo.Nfft);
        perRxW = double(rsrp.PerReceiveAntenna) ./ (nfft.^2 .* 1000);
        validPower = isfinite(perRxW) & perRxW > 0;
        rx.SRSRSRPPerReceiveAntenna_dBm(validPower) = ...
            10 .* log10(perRxW(validPower)) + 30;
        if any(validPower)
            rx.SRS_RSRP_dBm = 10 .* log10(mean(perRxW(validPower))) + 30;
            rx.SRSAbsolutePowerStatus = "available_calibrated_receiver_grid_sqrt_w";
            rx.SRSRSRPSource = ...
                "received_srs_channel_estimate_on_calibrated_sqrt_mw_waveform";
        end
    end
end

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

function [noiseVariance,info] = localEstimateSRSNullREDisturbance(rxGrid,srsInd,numPorts)
% Estimate effective disturbance on receiver-observed, unoccupied comb REs.
% SRS_Rx owns an SRS-only physical reception.  Any energy on these same-
% symbol, same-band null REs is therefore noise, ICI, or interference; it is
% not inferred from injected noise metadata or channel truth.
noiseVariance = NaN;
info = struct("Status","not_available_no_inband_null_re", ...
    "Source","received_srs_inband_null_re_disturbance", ...
    "SampleCount",0,"SymbolCount",0,"ReceiveBranchCount",size(rxGrid,3), ...
    "PerSymbolVariance",zeros(0,1));
if isempty(rxGrid) || isempty(srsInd)
    return;
end
K=size(rxGrid,1); L=size(rxGrid,2);
[subcarrier,symbol,~]=ind2sub([K,L,max(1,round(numPorts))],double(srsInd(:)));
symbols=unique(symbol(:),"stable");
energy=0; count=0; perSymbol=nan(numel(symbols),1);
for ii=1:numel(symbols)
    sym=symbols(ii);
    occupied=unique(subcarrier(symbol==sym));
    if isempty(occupied), continue; end
    inBand=(min(occupied):max(occupied)).';
    nullRE=setdiff(inBand,occupied,"stable");
    if isempty(nullRE), continue; end
    samples=rxGrid(nullRE,sym,:);
    values=abs(samples(:)).^2;
    values=values(isfinite(values) & values>=0);
    if isempty(values), continue; end
    perSymbol(ii)=mean(values);
    energy=energy+sum(values);
    count=count+numel(values);
end
if count<=0, return; end
noiseVariance=energy/count;
if ~(isfinite(noiseVariance) && noiseVariance>=0)
    noiseVariance=NaN;
    return;
end
info.Status="available";
info.SampleCount=count;
info.SymbolCount=nnz(isfinite(perSymbol));
info.PerSymbolVariance=perSymbol(isfinite(perSymbol));
end

function [leakage_dB,status] = localMeasureSRSInterPortLeakage( ...
        Hest,srsInd,srsSym,K,L,R,P)
% Receiver-side code projection.  Rows are observing matched filters and
% columns are emitting SRS ports.  The diagonal is excluded because it is
% the desired projection, not leakage.  This executes only from the actual
% SRS reference map and received channel estimate; no channel truth or
% transmitted payload decision is consulted.
leakage_dB = nan(P,P);
status = "not_available_requires_at_least_two_executed_srs_ports";
if P < 2 || isempty(Hest) || isempty(srsInd) || isempty(srsSym)
    return;
end
[k,l,pidx] = ind2sub([K,L,P],double(srsInd(:)));
X = complex(zeros(K*L,P));
X(sub2ind([K*L,P],sub2ind([K,L],k,l),pidx)) = srsSym(:);
norms = sqrt(sum(abs(X).^2,1));
if any(~isfinite(norms) | norms<=0), status="not_available_invalid_srs_reference_norm"; return; end
Q = X ./ norms;
for sourcePort=1:P
    selected = pidx==sourcePort;
    sourceRE = sub2ind([K,L],k(selected),l(selected));
    contribution = complex(zeros(K*L,R));
    for r=1:R
        hidx=sub2ind([K,L,R,P],k(selected),l(selected), ...
            repmat(r,nnz(selected),1),repmat(sourcePort,nnz(selected),1));
        values=Hest(hidx);
        valid=isfinite(values);
        contribution(sourceRE(valid),r)= ...
            X(sourceRE(valid),sourcePort).*values(valid);
    end
    % Project the independently reconstructed contribution of each emitting
    % port onto every installed SRS code. Retaining the per-RE channel
    % estimate is essential: replacing it by one averaged coefficient would
    % reduce this to ideal reference-code orthogonality and manufacture
    % unrealistically tiny (~-300 dB) leakage.
    projections = Q' * contribution;
    desired = mean(abs(projections(sourcePort,:)).^2,'omitnan');
    if ~(isfinite(desired) && desired>0), continue; end
    for observerPort=1:P
        if observerPort==sourcePort, continue; end
        undesired=mean(abs(projections(observerPort,:)).^2,'omitnan');
        if isfinite(undesired) && undesired>=0
            leakage_dB(observerPort,sourcePort)=10*log10(max(undesired,realmin)/desired);
        end
    end
end
offDiagonal = leakage_dB(~eye(P));
if any(isfinite(offDiagonal))
    status="observed_executed_srs_code_domain_projection";
else
    status="not_available_no_finite_off_diagonal_projection";
end
end

function value = localFiniteMaximum(x)
values=double(x(isfinite(x)));
if isempty(values), value=NaN; else, value=max(values); end
end

function measurement = localMeasureSRSReferencePower(Hest, srsInd, srsSym, K, L, R, P)
measurement = struct( ...
    "PerPortReceiveBranch", NaN(P,R), ...
    "PerReceiveAntenna", NaN(1,R), ...
    "PerReceiveAntenna_dB", NaN(1,R), ...
    "Aggregate_dB", NaN, ...
    "Source", "unavailable_srs_channel_estimate", ...
    "Status", "not_available");
if isempty(Hest) || isempty(srsInd) || isempty(srsSym)
    return;
end
[subcarrier, symbol, port] = ind2sub([K,L,P], double(srsInd(:)));
reference = srsSym(:);
if numel(reference) ~= numel(port)
    return;
end
for p = 1:P
    selected = port == p;
    if ~any(selected), continue; end
    ref = reference(selected);
    for r = 1:R
        hidx = sub2ind([K,L,R,P], subcarrier(selected), symbol(selected), ...
            repmat(r,nnz(selected),1), repmat(p,nnz(selected),1));
        predictedReceivedReference = Hest(hidx) .* ref;
        powerSamples = abs(predictedReceivedReference).^2;
        powerSamples = powerSamples(isfinite(powerSamples) & powerSamples >= 0);
        if ~isempty(powerSamples)
            measurement.PerPortReceiveBranch(p,r) = mean(powerSamples);
        end
    end
end
for r = 1:R
    x = measurement.PerPortReceiveBranch(:,r);
    x = x(isfinite(x) & x >= 0);
    if ~isempty(x)
        measurement.PerReceiveAntenna(r) = mean(x, "omitnan");
    end
end
valid = isfinite(measurement.PerReceiveAntenna) & measurement.PerReceiveAntenna > 0;
if ~any(valid)
    measurement.Source = "estimated_srs_channel_has_no_positive_reference_power";
    return;
end
measurement.PerReceiveAntenna_dB(valid) = 10 .* log10(measurement.PerReceiveAntenna(valid));
% Preserve the linear-power averaging order.  Averaging dB values or taking
% the strongest branch would introduce an antenna-count/selection bias and
% would not represent the receiver-observed SRS reference power.
measurement.Aggregate_dB = 10 .* log10(mean(measurement.PerReceiveAntenna(valid)));
measurement.Source = "received_srs_channel_estimate_times_known_reference_symbols";
measurement.Status = "observed";
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
