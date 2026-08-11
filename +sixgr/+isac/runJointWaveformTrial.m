function [row,raw] = runJointWaveformTrial(cfg,bundle,trial)
%RUNJOINTWAVEFORMTRIAL Execute one common-waveform communication+sensing trial.
%
% The full data+sensing waveform passes through one deterministic time-domain
% channel. Exact reconstructed direct/data components may be cancelled only
% when the YAML receiver policy declares them known. Sensing and communication
% metrics therefore originate from the same received sample vector.

arguments
    cfg (1,1) struct
    bundle (1,1) struct
    trial (1,1) struct
end
required = ["TrialId","Seed","DelayOverCP","NormalizedDoppler", ...
    "SensingMode","CollisionRatioPercent","CollisionResponse", ...
    "TDDPattern","TargetPresent","UseGeometryDelay","PortProfile"];
for i = 1:numel(required)
    if ~isfield(trial,required(i))
        error("sixgr:isac:MissingTrialValue", ...
            "Joint waveform trial is missing %s.",required(i));
    end
end

prior = rng;
cleanup = onCleanup(@() rng(prior)); %#ok<NASGU>
rng(double(trial.Seed),"twister");

configuredMask = bundle.ConfiguredMask;
collisionMask = false(size(configuredMask));
configuredIndices = find(configuredMask);
nCollision = round(numel(configuredIndices)*double(trial.CollisionRatioPercent)/100);
if nCollision > 0
    selected = configuredIndices(randperm(numel(configuredIndices),nCollision));
    collisionMask(selected) = true;
end
patternState = sixgr.isac.deriveEffectivePattern(configuredMask,collisionMask, ...
    string(trial.CollisionResponse),localTrialRelationClass(trial));

% Apply the effective sensing mask to the actual grid. Punctured sensing REs
% revert to their exact saved communication symbols, not zeros or synthetic
% values. Relocated RE values are reconstructed only where supported.
sensingGrid = localBuildEffectiveSensingGrid(cfg,bundle,patternState, ...
    string(trial.CollisionResponse));
txGrid = bundle.Grid;
removed = bundle.TransmittedMask & ~patternState.EffectiveMask;
txGrid(removed) = sqrt(double(cfg.waveform.communicationDataPower))*bundle.DataGrid(removed);
txGrid(patternState.EffectiveMask) = sensingGrid(patternState.EffectiveMask);
waveform = nrOFDMModulate(bundle.Carrier,txGrid, ...
    "Windowing",double(cfg.waveform.ofdmWindowingSamples));
sensingWaveform = nrOFDMModulate(bundle.Carrier,sensingGrid, ...
    "Windowing",double(cfg.waveform.ofdmWindowingSamples));
dataGrid = sqrt(double(cfg.waveform.communicationDataPower))*bundle.DataGrid;
dataGrid(patternState.EffectiveMask) = 0;
dataWaveform = nrOFDMModulate(bundle.Carrier,dataGrid, ...
    "Windowing",double(cfg.waveform.ofdmWindowingSamples));

mode = lower(string(trial.SensingMode));
[txPosition,rxPosition,targetPosition,targetVelocity] = localGeometry(cfg,mode);
geometry = sixgr.isac.bistaticGeometry(txPosition,rxPosition,targetPosition, ...
    targetVelocity,double(bundle.CarrierProfile.frequencyHz),mode);
fs = double(bundle.OFDMInfo.SampleRate);
cpSamples = min(double(bundle.CPLengths));
if logical(trial.UseGeometryDelay)
    if mode == "trp_monostatic"
        delaySeconds = geometry.TotalDelayS;
    else
        delaySeconds = geometry.ExcessDelayS;
    end
    delaySamples = max(0,round(delaySeconds*fs));
    dopplerHz = geometry.DopplerHz;
    channelBasis = "configured_geometry";
else
    delaySamples = round(double(trial.DelayOverCP)*cpSamples);
    delaySeconds = delaySamples/fs;
    dopplerHz = double(trial.NormalizedDoppler)* ...
        double(bundle.Carrier.SubcarrierSpacing)*1e3;
    channelBasis = "controlled_delay_doppler_sweep";
end
if delaySamples >= numel(waveform)
    error("sixgr:isac:DelayOutsideObservation", ...
        "Delay %d samples exceeds common waveform observation %d.", ...
        delaySamples,numel(waveform));
end

arrayCfg = sixgr.util.structGet(cfg,"antenna."+string(trial.PortProfile),[]);
if ~(isstruct(arrayCfg) && isscalar(arrayCfg))
    error("sixgr:isac:MissingPortProfile", ...
        "Unknown antenna port profile %s.",string(trial.PortProfile));
end
nTx = double(arrayCfg.transmitElements);
nRx = double(arrayCfg.receiveElements);
spacing = double(cfg.antenna.elementSpacingWavelength);
[txLocalAzimuthDeg,rxLocalAzimuthDeg] = localArrayAngles(cfg,mode, ...
    txPosition,rxPosition,targetPosition);
txSteering = exp(1i*2*pi*spacing*(0:nTx-1).'*sind(txLocalAzimuthDeg));
rxSteering = exp(1i*2*pi*spacing*(0:nRx-1).'*sind(rxLocalAzimuthDeg));
txWeights = conj(txSteering)/sqrt(nTx);
if lower(string(trial.CollisionResponse))=="beam_precoder_change"
    txWeights=txWeights.*exp(1i*deg2rad(double(cfg.collisions.beamPrecoderPhaseSlopeDeg))* ...
        (0:nTx-1).');
    txWeights=txWeights/norm(txWeights);
end
txFieldFull = (waveform*transpose(txWeights))*txSteering;
txFieldSense = (sensingWaveform*transpose(txWeights))*txSteering;
txFieldData = (dataWaveform*transpose(txWeights))*txSteering;

gain = 10^(double(cfg.channel.targetPathGainDb)/20);
if logical(trial.TargetPresent)
    targetFullField = gain*localDelayDoppler(txFieldFull,delaySamples,dopplerHz,fs,0);
    targetSenseField = gain*localDelayDoppler(txFieldSense,delaySamples,dopplerHz,fs,0);
    targetDataField = gain*localDelayDoppler(txFieldData,delaySamples,dopplerHz,fs,0);
    targetFull = targetFullField*transpose(rxSteering);
    targetSense = targetSenseField*transpose(rxSteering);
    targetData = targetDataField*transpose(rxSteering);
else
    targetFull = complex(zeros(numel(waveform),nRx));
    targetSense = complex(zeros(numel(waveform),nRx));
    targetData = complex(zeros(numel(waveform),nRx));
end
if logical(cfg.channel.directPathEnabled)
    direct = repmat(waveform,1,nRx);
else
    direct = complex(zeros(numel(waveform),nRx));
end
referenceEchoPower = mean(abs(targetSense).^2,"all");
if ~(isfinite(referenceEchoPower) && referenceEchoPower > 0)
    referenceEchoPower = max(mean(abs(sensingWaveform).^2)*gain^2*nTx,realmin);
end
noisePower = referenceEchoPower/10^(double(cfg.receiver.snrDb)/10);
noise = sqrt(noisePower/2)*(randn(size(direct))+1i*randn(size(direct)));
receivedCommon = direct+targetFull+noise;
knowledge=lower(string(cfg.receiver.sharedResourceKnowledge));
if isfield(trial,"SharedResourceKnowledge") && strlength(string(trial.SharedResourceKnowledge))>0
    knowledge=lower(string(trial.SharedResourceKnowledge));
end
switch knowledge
    case {"known_cancelled","decoded_reconstructed"}
        receivedSensing = receivedCommon-direct-targetData;
    case "residual_data_interference"
        residualFraction=double(cfg.receiver.residualDataInterferenceFraction);
        receivedSensing = receivedCommon-direct-(1-residualFraction)*targetData;
    otherwise
        error("sixgr:isac:UnsupportedSharedResourceKnowledge", ...
            "Unsupported shared-resource receiver policy %s.",knowledge);
end

% Whole-waveform linear matched filter for delay/range.
nFFTCorrelation = 2^nextpow2(2*numel(sensingWaveform)-1);
referenceSpectrum = fft(sensingWaveform,nFFTCorrelation);
correlation = ifft(fft(receivedSensing,nFFTCorrelation).*conj(referenceSpectrum));
maximumLag = min(numel(waveform)-1,max(delaySamples+4*cpSamples,4*cpSamples));
rangeResponse = correlation(1:maximumLag+1,:);
rangePower = sum(abs(rangeResponse).^2,2);
[peakPower,peakIndex] = max(rangePower);
estimatedDelaySamples = peakIndex-1;
noiseFloor = median(rangePower);
nSearchCells = numel(rangePower);
cellPFA = 1-(1-double(cfg.detection.probabilityFalseAlarm))^(1/nSearchCells);
noiseMean = noiseFloor/log(2);
threshold = max(realmin,-log(cellPFA)*noiseMean);
detection = peakPower > threshold;
delayTolerance = max(1,double(cfg.detection.delayToleranceBins));
wrongPeak = detection && abs(estimatedDelaySamples-delaySamples) > delayTolerance;

if mode == "trp_monostatic"
    rangeScale = physconst("LightSpeed")/(2*fs);
else
    rangeScale = physconst("LightSpeed")/fs;
end
expectedRangeM = delaySamples*rangeScale;
measuredRangeM = estimatedDelaySamples*rangeScale;
rangeErrorM = measuredRangeM-expectedRangeM;
reportedExpectedDopplerHz = dopplerHz;

angleGrid = (double(cfg.antenna.angleEstimation.minimumDeg): ...
    double(cfg.antenna.angleEstimation.stepDeg): ...
    double(cfg.antenna.angleEstimation.maximumDeg)).';
if nRx > 1 && logical(trial.TargetPresent)
    scanSteering = exp(1i*2*pi*spacing*(0:nRx-1).'*sind(angleGrid.'));
    snapshot = reshape(rangeResponse(peakIndex,:),1,[]);
    if size(scanSteering,1) ~= numel(snapshot)
        error("sixgr:isac:ArraySnapshotDimensionMismatch", ...
            "Receive snapshot has %d elements, steering manifold has %d rows.", ...
            numel(snapshot),size(scanSteering,1));
    end
    anglePower = abs(snapshot*conj(scanSteering)).^2;
    [~,angleIndex] = max(anglePower);
    measuredAzimuthDeg = angleGrid(angleIndex);
    angleErrorDeg = localWrap180(measuredAzimuthDeg-rxLocalAzimuthDeg);
    receiveSteering = scanSteering(:,angleIndex);
else
    anglePower = nan(size(angleGrid.'));
    measuredAzimuthDeg = NaN;
    angleErrorDeg = NaN;
    receiveSteering = ones(nRx,1);
end
receivedSensingBeam = receivedSensing*conj(receiveSteering)/nRx;

% OFDM-grid slow-time phase uses the exact transmitted sensing symbols and
% absolute OFDM symbol times. This avoids a fictitious slot-rate pulse train.
rxSensingGrid = nrOFDMDemodulate(bundle.Carrier,receivedSensingBeam);
occasionSymbols = find(any(patternState.EffectiveMask,1));
occasionPhase = nan(numel(occasionSymbols),1);
occasionTime = nan(numel(occasionSymbols),1);
symbolStart = [0;cumsum(double(bundle.CPLengths(:))+double(bundle.OFDMInfo.Nfft))];
for i = 1:numel(occasionSymbols)
    symbol = occasionSymbols(i);
    mask = patternState.EffectiveMask(:,symbol);
    product = rxSensingGrid(mask,symbol).*conj(sensingGrid(mask,symbol));
    % Remove the measured propagation-delay phase before coherently adding
    % frequency-comb REs. Without this operation the wideband phasors cancel
    % and the slow-time phase estimate becomes noise dominated.
    rows0 = find(mask)-1;
    physicalK = rows0 + 12*double(bundle.Carrier.NStartGrid) - ...
        floor(size(bundle.Grid,1)/2);
    delayDerotation = exp(1i*2*pi*physicalK*estimatedDelaySamples/ ...
        double(bundle.OFDMInfo.Nfft));
    product = product.*delayDerotation;
    occasionPhase(i) = angle(sum(product));
    occasionTime(i) = (symbolStart(symbol)+double(bundle.CPLengths(symbol)))/fs;
end
if numel(occasionSymbols) >= 2
    fitCoefficients = polyfit(occasionTime,unwrap(occasionPhase),1);
    measuredDopplerHz = fitCoefficients(1)/(2*pi);
else
    measuredDopplerHz = NaN;
end
dopplerErrorHz = measuredDopplerHz-dopplerHz;
reportedDopplerErrorHz = dopplerErrorHz;
targetMetricApplicable = logical(trial.TargetPresent);
angleMeasurementApplicable = targetMetricApplicable && nRx > 1;
if ~targetMetricApplicable
    expectedRangeM = NaN;
    rangeErrorM = NaN;
    reportedExpectedDopplerHz = NaN;
    reportedDopplerErrorHz = NaN;
end

% Communication output comes from the same receivedCommon samples. A single
% complex least-squares channel coefficient is estimated on data REs; this is
% a declared narrowband calibration receiver, not a coded PDSCH BLER claim.
receivedCommunication = mean(receivedCommon,2);
rxGrid = nrOFDMDemodulate(bundle.Carrier,receivedCommunication);
% Decode only REs that remain communication REs after applying the runtime
% collision response.  Relocation can add sensing REs outside the configured
% mask; using bundle.TransmittedMask here would silently score those sensing
% symbols as QPSK data.
dataMask = ~patternState.EffectiveMask;
txData = txGrid(dataMask);
rxData = rxGrid(dataMask);
channelEstimate = (txData'*rxData)/max(txData'*txData,eps);
if abs(channelEstimate) < eps
    error("sixgr:isac:CommunicationChannelEstimateDegenerate", ...
        "The common-waveform communication channel estimate is degenerate.");
end
equalized = rxData/channelEstimate;
evmRMS = sqrt(mean(abs(equalized-txData).^2)/mean(abs(txData).^2));
decision = localQPSKDecision(equalized);
symbolErrorRate = mean(decision ~= localQPSKDecision(txData));
uncodedBlockError = symbolErrorRate > 0;
slotDuration = numel(waveform)/fs;
uncodedGoodputBps = 2*numel(txData)*(~uncodedBlockError)/slotDuration;

[pslrDb,islrDb,mainLobeBins] = localRangeMetrics(rangePower,peakIndex);
[aclrDb,oobeRatio] = localSpectralMetrics(waveform,fs, ...
    double(bundle.CarrierProfile.channelBandwidthHz));
paprDb = 10*log10(max(abs(waveform).^2)/mean(abs(waveform).^2));
observationHash = localComplexHash(receivedCommon);

row = table(string(trial.TrialId),string(bundle.ProfileId),string(trial.SensingMode), ...
    string(trial.TDDPattern),string(trial.CollisionResponse),double(trial.Seed), ...
    logical(trial.TargetPresent),logical(trial.UseGeometryDelay),channelBasis, ...
    double(trial.DelayOverCP),double(trial.NormalizedDoppler), ...
    double(trial.CollisionRatioPercent),cpSamples,delaySamples,delaySeconds, ...
    reportedExpectedDopplerHz,measuredDopplerHz,reportedDopplerErrorHz,expectedRangeM,measuredRangeM, ...
    rangeErrorM,rxLocalAzimuthDeg,measuredAzimuthDeg,angleErrorDeg, ...
    targetMetricApplicable,angleMeasurementApplicable,string(trial.PortProfile),nTx,nRx, ...
    detection,wrongPeak,peakPower,noiseFloor,threshold, ...
    patternState.ConfiguredObservations,nnz(patternState.ReplacementMask), ...
    patternState.RetainedObservations,patternState.CoherentSegmentCount, ...
    string(patternState.RelationClass),knowledge,evmRMS,symbolErrorRate, ...
    uncodedBlockError,uncodedGoodputBps,paprDb,pslrDb,islrDb,mainLobeBins, ...
    aclrDb,oobeRatio,string(bundle.WaveformSHA256),string(observationHash), ...
    string(cfg.study.evidenceClass),"common_time_domain_waveform_truth", ...
    'VariableNames',{'TrialId','WaveformProfile','SensingMode','TDDPattern', ...
    'CollisionResponse','Seed','TargetPresent','UseGeometryDelay','ChannelBasis', ...
    'DelayOverCP','NormalizedDoppler','CollisionRatioPercent','CPSamples', ...
    'DelaySamples','DelaySeconds','ExpectedDopplerHz','MeasuredDopplerHz', ...
    'DopplerErrorHz','ExpectedRangeM','MeasuredRangeM','RangeErrorM', ...
    'ExpectedAzimuthDeg','MeasuredAzimuthDeg','AzimuthErrorDeg', ...
    'TargetMetricApplicable','AngleMeasurementApplicable', ...
    'PortProfile','TransmitElements','ReceiveElements', ...
    'Detected','WrongPeak','PeakPower','NoiseFloorPower','DetectionThreshold', ...
    'ConfiguredObservations','ReplacementObservations','RetainedObservations', ...
    'CoherentSegments','RelationClass','SharedResourceKnowledge', ...
    'CommunicationEVMRMS','UncodedSymbolErrorRate','UncodedDataBlockError', ...
    'UncodedGoodputBps','PAPRDb','PSLRDb','ISLRDb','MainLobeWidthBins', ...
    'ACLRDb','OOBEPowerRatio','TransmitWaveformSHA256', ...
    'ReceivedObservationSHA256','EvidenceClass','ObservationSource'});

geometryTable = table(txPosition(1),txPosition(2),txPosition(3), ...
    rxPosition(1),rxPosition(2),rxPosition(3),targetPosition(1), ...
    targetPosition(2),targetPosition(3),targetVelocity(1),targetVelocity(2), ...
    targetVelocity(3),geometry.TxLegM,geometry.RxLegM,geometry.TargetPathM, ...
    geometry.DirectPathM,geometry.TotalDelayS,geometry.ExcessDelayS, ...
    geometry.BistaticAngleDeg,geometry.DopplerHz, ...
    'VariableNames',{'TxX_m','TxY_m','TxZ_m','RxX_m','RxY_m','RxZ_m', ...
    'TargetX_m','TargetY_m','TargetZ_m','TargetVx_mps','TargetVy_mps', ...
    'TargetVz_mps','TxLegM','RxLegM','TargetPathM','DirectPathM', ...
    'TotalDelayS','ExcessDelayS','BistaticAngleDeg','GeometryDopplerHz'});
rangeAxisM = (0:maximumLag)'*rangeScale;
rangeTable = table(rangeAxisM,rangePower, ...
    10*log10(max(rangePower,realmin)/max(peakPower,realmin)), ...
    'VariableNames',{'RangeM','PowerLinear','PowerRelativeDb'});
occasionTable = table(occasionSymbols(:)-1,occasionTime,occasionPhase, ...
    'VariableNames',{'AbsoluteSymbolIndex','ObservationTimeS','MeasuredPhaseRad'});
angleTable = table(angleGrid,anglePower(:), ...
    'VariableNames',{'AzimuthDeg','BeamPowerLinear'});
raw = struct("Trial",row,"Geometry",geometryTable,"RangeProfile",rangeTable, ...
    "OccasionPhase",occasionTable,"AngleProfile",angleTable,"PatternState",patternState, ...
    "ReceivedCommon",receivedCommon,"ReceivedSensing",receivedSensing, ...
    "TransmitWaveform",waveform,"SensingWaveform",sensingWaveform);
end

function relation = localRelationClass(response)
switch lower(response)
    case {"time_relocation","frequency_relocation","recoverable_relocation"}
        relation = "known_transform";
    otherwise
        relation = "preserved";
end
end

function relation=localTrialRelationClass(trial)
if isfield(trial,"RelationClass") && strlength(string(trial.RelationClass))>0
    relation=lower(string(trial.RelationClass));
else
    relation=localRelationClass(string(trial.CollisionResponse));
end
end

function sensingGrid=localBuildEffectiveSensingGrid(cfg,bundle,state,response)
sensingGrid=complex(zeros(size(bundle.SensingGrid)));
existing=state.EffectiveMask & bundle.TransmittedMask;
sensingGrid(existing)=bundle.SensingGrid(existing);
added=state.EffectiveMask & ~bundle.TransmittedMask;
[targetRows,targetCols]=find(added);
for i=1:numel(targetRows)
    row=targetRows(i); col=targetCols(i); sourceRow=row; sourceCol=col;
    if contains(response,"time_relocation") || response=="recoverable_relocation"
        candidates=find(bundle.TransmittedMask(row,1:max(1,col-1)),1,"last");
        if ~isempty(candidates), sourceCol=candidates; else, sourceCol=0; end
    elseif response=="frequency_relocation" || response=="comb_pattern_selection"
        candidates=find(bundle.TransmittedMask(1:max(1,row-1),col),1,"last");
        if ~isempty(candidates), sourceRow=candidates; else, sourceRow=0; end
    end
    if sourceRow<1 || sourceCol<1
        error("sixgr:isac:RelocatedSequenceSourceMissing", ...
            "No source sensing RE exists for relocated RE (%d,%d).",row,col);
    end
    value=bundle.SensingGrid(sourceRow,sourceCol);
    if logical(bundle.Profile.cumulativeCPPhase)
        nSC=size(bundle.SensingGrid,1); nFFT=double(bundle.OFDMInfo.Nfft);
        sourceK=(sourceRow-1)+12*double(bundle.Carrier.NStartGrid)-floor(nSC/2);
        targetK=(row-1)+12*double(bundle.Carrier.NStartGrid)-floor(nSC/2);
        base=value*exp(-1i*2*pi*sourceK*bundle.CumulativeCPState(sourceCol)/nFFT);
        value=base*exp(1i*2*pi*targetK*bundle.CumulativeCPState(col)/nFFT);
    end
    sensingGrid(row,col)=value;
end
if response=="known_ratio_power_scaling"
    sensingGrid=sensingGrid*10^(double(cfg.collisions.knownRatioPowerScalingDb)/20);
end
end

function [tx,rx,target,velocity] = localGeometry(cfg,mode)
tx = double(cfg.scene.nodes.trp1PositionM(:));
if mode == "trp_monostatic"
    rx = tx;
elseif mode == "trp_trp_bistatic"
    rx = double(cfg.scene.nodes.trp2PositionM(:));
else
    error("sixgr:isac:UnsupportedSensingMode","Unsupported sensing mode %s.",mode);
end
targetCfg = sixgr.util.structGet(cfg,"scene.targets."+string(cfg.scene.activeTarget),[]);
target = double(targetCfg.positionM(:));
velocity = double(targetCfg.velocityMps(:));
end

function [txLocal,rxLocal] = localArrayAngles(cfg,mode,tx,rx,target)
txGlobal = atan2d(target(2)-tx(2),target(1)-tx(1));
if mode == "trp_monostatic"
    txBearing = double(cfg.scene.nodes.trp1OrientationDeg(1));
    rxBearing = txBearing;
else
    txBearing = double(cfg.scene.nodes.trp1OrientationDeg(1));
    rxBearing = double(cfg.scene.nodes.trp2OrientationDeg(1));
end
rxGlobal = atan2d(target(2)-rx(2),target(1)-rx(1));
txLocal = localWrap180(txGlobal-txBearing);
rxLocal = localWrap180(rxGlobal-rxBearing);
if abs(txLocal) > 90 || abs(rxLocal) > 90
    error("sixgr:isac:TargetBehindConfiguredULA", ...
        "Configured ULA boresight places target outside the visible +/-90 degree sector.");
end
end

function value = localWrap180(value)
value = mod(value+180,360)-180;
end

function y = localDelayDoppler(x,delaySamples,dopplerHz,fs,startTime)
n = (0:numel(x)-1).';
phase = exp(1i*2*pi*dopplerHz*(startTime+n/fs));
shifted = [complex(zeros(delaySamples,1));x(1:end-delaySamples)];
y = shifted.*phase;
end

function decided = localQPSKDecision(value)
decided = (2*(real(value) >= 0)-1 + 1i*(2*(imag(value) >= 0)-1))/sqrt(2);
end

function [pslrDb,islrDb,width] = localRangeMetrics(power,peakIndex)
halfWidth = 1;
main = false(size(power));
main(max(1,peakIndex-halfWidth):min(numel(power),peakIndex+halfWidth)) = true;
peak = max(power);
sidelobes = power(~main);
if isempty(sidelobes)
    pslrDb = -Inf;
    islrDb = -Inf;
else
    pslrDb = 10*log10(max(sidelobes)/max(peak,realmin));
    islrDb = 10*log10(sum(sidelobes)/max(sum(power(main)),realmin));
end
width = nnz(main);
end

function [aclrDb,oobeRatio] = localSpectralMetrics(waveform,fs,channelBandwidth)
nFFT = 2^nextpow2(numel(waveform));
spectrum = abs(fftshift(fft(waveform,nFFT))).^2;
frequency = ((-nFFT/2):(nFFT/2-1)).'*fs/nFFT;
inBand = abs(frequency) <= channelBandwidth/2;
adjacent = abs(frequency) > channelBandwidth/2 & ...
    abs(frequency) <= min(fs/2,3*channelBandwidth/2);
inPower = sum(spectrum(inBand));
adjacentPower = sum(spectrum(adjacent));
oobePower = sum(spectrum(~inBand));
aclrDb = 10*log10(max(inPower,realmin)/max(adjacentPower,realmin));
oobeRatio = oobePower/max(sum(spectrum),realmin);
end

function digest = localComplexHash(value)
bytes = typecast([real(value(:));imag(value(:))],"uint8");
digest = sixgr.util.sha256Hex(bytes);
end
