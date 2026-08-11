function result = runISACSensingTrial(cfg,tx,runtimeContext)
%RUNISACSENSINGTRIAL Execute a measured communication-centric ISAC capture.
%
% The sensing transmitter is the exact PDSCH waveform and physical antenna
% projection used by the communication trial.  A public
% phased.ScatteringMIMOChannel models configured deterministic scatterers.
% Range, azimuth, and Doppler products are derived from the received
% samples by matched filtering and array beamforming; no configured target
% value is substituted into a measured result.

arguments
    cfg (1,1) struct
    tx (1,1) struct
    runtimeContext (1,1) struct = struct()
end

if ~logical(cfg.isac.enabled)
    error("sixgr:lls:ISACNotEnabled", ...
        "runISACSensingTrial requires isac.enabled=true.");
end
signalType = upper(string(sixgr.util.structGet(runtimeContext,"SignalType", ...
    sixgr.util.structGet(cfg,"simulation.link",""))));
if signalType ~= "PDSCH"
    error("sixgr:lls:ISACRequiresPDSCH", ...
        "Communication-centric ISAC requires the runtime PDSCH waveform.");
end
if exist("phased.ScatteringMIMOChannel","class") ~= 8 || ...
        exist("phased.SteeringVector","class") ~= 8
    error("sixgr:lls:MissingISACToolbox", ...
        "ISAC execution requires Phased Array System Toolbox.");
end

[state,txArray,rxArray] = localResolveSensingAntennaState(cfg,runtimeContext,size(tx.Waveform,2));
if ~state.Enabled || state.TxRole ~= "gnb"
    error("sixgr:lls:ISACRequiresPhysicalAntenna", ...
        "ISAC requires the enabled physical gNB PDSCH transmit array.");
end
mode = lower(string(cfg.isac.sensingMode));
if mode == "monostatic_gnb"
    rxState = state.Tx;
    rxRole = "gnb";
else
    rxState = state.Rx;
    rxRole = "ue";
end
arrayCleanup = onCleanup(@() localReleaseArrays(txArray,rxArray)); %#ok<NASGU>

fc = double(sixgr.util.structGet(runtimeContext,"CarrierFrequencyHz", ...
    sixgr.util.structGet(cfg,"carrier.frequencyHz",NaN)));
fs = double(sixgr.util.structGet(runtimeContext,"SampleRateHz",NaN));
if ~(isfinite(fs) && fs > 0)
    if ~isfield(tx,"Carrier")
        error("sixgr:lls:MissingISACSampleRate", ...
            "ISAC requires the exact runtime waveform sample rate.");
    end
    ofdm = nrOFDMInfo(tx.Carrier);
    fs = double(ofdm.SampleRate);
end
if ~(isfinite(fc) && fc > 0)
    error("sixgr:lls:MissingISACCarrierFrequency", ...
        "ISAC requires the exact runtime carrier frequency.");
end
c = physconst("LightSpeed");
lambda = c/fc;
gnbPosition = localPosition(runtimeContext,"GNBPositionM", ...
    sixgr.util.structGet(cfg,"isac.scene.gnbPositionM",[]));
uePosition = localPosition(runtimeContext,"UEPositionM", ...
    sixgr.util.structGet(cfg,"isac.scene.uePositionM",[]));
if mode == "monostatic_gnb"
    rxPosition = gnbPosition;
    rangeDivisor = 2;
else
    rxPosition = uePosition;
    rangeDivisor = 1;
end
txAxes = localOrientationAxes(state.Tx.OrientationDeg);
rxAxes = localOrientationAxes(rxState.OrientationDeg);
nTargets = double(cfg.isac.scene.numberTargets);
targetPositions0 = reshape(double(cfg.isac.scene.targetPositionsM),3,nTargets);
targetVelocities = reshape(double(cfg.isac.scene.targetVelocitiesMps),3,nTargets);
reflection = complex(double(cfg.isac.scene.reflectionCoefficientReal(:).'), ...
    double(cfg.isac.scene.reflectionCoefficientImag(:).'));

channel = phased.ScatteringMIMOChannel( ...
    "CarrierFrequency",fc, ...
    "TransmitArray",txArray, ...
    "TransmitArrayPosition",gnbPosition, ...
    "ReceiveArray",rxArray, ...
    "ReceiveArrayPosition",rxPosition, ...
    "TransmitArrayOrientationAxes",txAxes, ...
    "ReceiveArrayOrientationAxes",rxAxes, ...
    "SampleRate",fs, ...
    "SimulateDirectPath",logical(cfg.isac.channel.simulateDirectPath), ...
    "ScattererSpecificationSource","Input port");
channelCleanup = onCleanup(@() release(channel)); %#ok<NASGU>

txPhysical = tx.Waveform * transpose(state.Tx.PortToElementMatrix);
unscaledPower = sum(mean(abs(txPhysical).^2,1));
requestedPowerW = 10^((double(cfg.isac.transmitPowerDbm)-30)/10);
if ~(isfinite(unscaledPower) && unscaledPower > 0)
    error("sixgr:lls:InvalidISACTransmitWaveform", ...
        "The runtime PDSCH waveform has no finite positive transmit power.");
end
powerScale = sqrt(requestedPowerW/unscaledPower);
txPhysical = txPhysical*powerScale;
referenceBank = tx.Waveform*powerScale;
referenceEnergy = sum(abs(referenceBank).^2,1);
activeReferences = isfinite(referenceEnergy) & referenceEnergy > 0;
referenceBank = referenceBank(:,activeReferences);
referenceEnergy = referenceEnergy(activeReferences);
if isempty(referenceBank)
    error("sixgr:lls:InvalidISACReferenceWaveform", ...
        "The runtime ISAC reference waveform has invalid energy.");
end

nSamples = size(txPhysical,1);
nFFT = double(cfg.isac.processing.rangeFFTSize);
if nFFT < 2*nSamples-1
    error("sixgr:lls:ISACRangeFFTTooSmall", ...
        "isac.processing.rangeFFTSize=%d must be at least 2*waveformSamples-1=%d.", ...
        nFFT,2*nSamples-1);
end
pulseDuration = nSamples/fs;
nPulses = double(cfg.isac.coherentRepetitions);
nWarmupPulses = double(cfg.isac.channel.warmupPulses);
maximumRange = double(cfg.isac.processing.maximumRangeM);
maximumDelaySamples = floor(maximumRange*rangeDivisor*fs/c);
if maximumDelaySamples >= nSamples
    error("sixgr:lls:ISACRangeOutsideWaveform", ...
        "Configured ISAC maximum range requires %d delay samples; one waveform has %d.", ...
        maximumDelaySamples,nSamples);
end
nRange = maximumDelaySamples+1;
cube = complex(zeros(nRange,rxState.NumElements,size(referenceBank,2),nPulses));

priorRng = rng;
rngCleanup = onCleanup(@() rng(priorRng)); %#ok<NASGU>
rng(double(cfg.isac.seed),"twister");
kBoltzmann = 1.380649e-23;
noiseFactor = 10^(double(cfg.isac.receiver.noiseFigureDb)/10);
gainLinear = 10^(double(cfg.isac.receiver.gainDb)/10);
noisePowerW = kBoltzmann*double(cfg.isac.receiver.referenceTemperatureK)* ...
    fs*noiseFactor*gainLinear;
referenceSpectrum = fft(referenceBank,nFFT,1);

% YAML-owned warm-up pulses fill propagation-delay state. Only subsequent
% coherent observations enter the primary sensing cube.
for pulse = 1:(nWarmupPulses+nPulses)
    timeSeconds = (pulse-1)*pulseDuration;
    targetPositions = targetPositions0 + targetVelocities*timeSeconds;
    received = channel(txPhysical,targetPositions,targetVelocities,reflection);
    received = received*sqrt(gainLinear);
    noise = sqrt(noisePowerW/2) * ...
        (randn(size(received))+1i*randn(size(received)));
    received = received+noise;
    if pulse <= nWarmupPulses
        continue;
    end
    sensingPulse = pulse-nWarmupPulses;
    receivedSpectrum = fft(received,nFFT,1);
    for referenceIndex = 1:size(referenceBank,2)
        correlation = ifft(receivedSpectrum.* ...
            conj(referenceSpectrum(:,referenceIndex)),nFFT,1);
        cube(:,:,referenceIndex,sensingPulse) = ...
            correlation(1:nRange,:)/referenceEnergy(referenceIndex);
    end
end

rawCubeHash = localComplexHash(cube);
processedCube = cube;
if strcmpi(string(cfg.isac.processing.backgroundRemoval),"slow_time_mean")
    processedCube = processedCube-mean(processedCube,4);
end
rangeM = (0:nRange-1).'/fs*c/rangeDivisor;
azimuthGrid = (double(cfg.isac.processing.azimuthGrid.minimumDeg): ...
    double(cfg.isac.processing.azimuthGrid.stepDeg): ...
    double(cfg.isac.processing.azimuthGrid.maximumDeg));
steering = phased.SteeringVector( ...
    "SensorArray",rxArray,"PropagationSpeed",c, ...
    "IncludeElementResponse",logical(cfg.isac.processing.includeElementResponse));
steeringCleanup = onCleanup(@() release(steering)); %#ok<NASGU>
steeringVectors = steering(fc,[azimuthGrid;zeros(size(azimuthGrid))]);

rangeAnglePower = zeros(nRange,numel(azimuthGrid));
for pulse = 1:nPulses
    for referenceIndex = 1:size(referenceBank,2)
        beamformed = processedCube(:,:,referenceIndex,pulse)*conj(steeringVectors);
        rangeAnglePower = rangeAnglePower+abs(beamformed).^2;
    end
end
rangeAnglePower = rangeAnglePower/nPulses;
rangeProfilePower = squeeze(sum(sum(mean(abs(processedCube).^2,4),2),3));

nDoppler = double(cfg.isac.processing.dopplerFFTSize);
dopplerCube = fftshift(fft(processedCube,nDoppler,4),4);
rangeDopplerPower = squeeze(sum(sum(abs(dopplerCube).^2,2),3))/nPulses;
prfHz = 1/pulseDuration;
dopplerHz = ((-floor(nDoppler/2)):(ceil(nDoppler/2)-1))*prfHz/nDoppler;

[detectionTable,thresholdTable] = localCACFAR( ...
    rangeAnglePower,rangeM,azimuthGrid,cfg.isac.detection);
truthTable = localTargetTruth(targetPositions0,targetVelocities, ...
    gnbPosition,rxPosition,rxAxes,mode,lambda);
[detectionTable,matchedCount,rangeRMSE,azimuthRMSE] = ...
    localMatchDetections(detectionTable,truthTable,cfg.isac.acceptance);
evidenceValid = matchedCount >= double(cfg.isac.acceptance.minimumMatchedTargets) && ...
    rangeRMSE <= double(cfg.isac.acceptance.maximumRangeErrorM) && ...
    azimuthRMSE <= double(cfg.isac.acceptance.maximumAzimuthErrorDeg);

peakPower = max(rangeAnglePower,[],"all");
rangeAngleDb = localRelativeDb(rangeAnglePower,peakPower);
rangeDopplerDb = localRelativeDb(rangeDopplerPower,max(rangeDopplerPower,[],"all"));
rangeProfileDb = localRelativeDb(rangeProfilePower,max(rangeProfilePower));
[rangeGrid,azimuthGridMatrix] = ndgrid(rangeM,azimuthGrid);
[rangeDopplerGrid,dopplerGrid] = ndgrid(rangeM,dopplerHz);

scenarioId = string(sixgr.util.structGet(runtimeContext,"ScenarioId", ...
    sixgr.util.structGet(cfg,"scenario.id",sixgr.util.structGet(cfg,"run.scenarioID",""))));
configTable = table(scenarioId,string(cfg.isac.researchTaxonomy), ...
    string(cfg.isac.approach),mode,string(cfg.isac.waveformAuthority), ...
    string(cfg.isac.channelModel),fc,fs, ...
    gnbPosition(1),gnbPosition(2),gnbPosition(3), ...
    uePosition(1),uePosition(2),uePosition(3), ...
    requestedPowerW,nPulses, ...
    string(cfg.isac.processing.observationSource),string(cfg.isac.processing.backgroundRemoval), ...
    maximumRange,nFFT,nDoppler,nWarmupPulses, ...
    logical(cfg.isac.processing.includeElementResponse), ...
    string(cfg.isac.processing.matchedFilterImplementation), ...
    string(cfg.isac.processing.beamformer),string(cfg.isac.detection.algorithm), ...
    string(rxRole),state.Tx.NumElements,rxState.NumElements,size(referenceBank,2), ...
    'VariableNames',{'ScenarioID','ResearchTaxonomy','Approach','SensingMode', ...
    'WaveformAuthority','ChannelModel','CarrierFrequencyHz','SampleRateHz', ...
    'GNBX_m','GNBY_m','GNBZ_m','UEX_m','UEY_m','UEZ_m', ...
    'TransmitPowerW','CoherentRepetitions','ObservationSource','BackgroundRemoval', ...
    'MaximumRangeM','RangeFFTSize','DopplerFFTSize','WarmupPulses', ...
    'IncludeElementResponse','MatchedFilterImplementation','Beamformer', ...
    'DetectionAlgorithm','SensingReceiverRole', ...
    'TransmitElements','ReceiveElements','ActiveMatchedFilterReferences'});
rangeProfileTable = table(rangeM,rangeProfilePower,rangeProfileDb, ...
    'VariableNames',{'RangeM','PowerLinear','PowerRelativeDb'});
rangeAngleTable = table(rangeGrid(:),azimuthGridMatrix(:), ...
    rangeAnglePower(:),rangeAngleDb(:), ...
    'VariableNames',{'RangeM','AzimuthDeg','PowerLinear','PowerRelativeDb'});
rangeDopplerTable = table(rangeDopplerGrid(:),dopplerGrid(:), ...
    rangeDopplerPower(:),rangeDopplerDb(:), ...
    'VariableNames',{'RangeM','DopplerHz','PowerLinear','PowerRelativeDb'});
runtimeTable = table(scenarioId,true,true,evidenceValid, ...
    "phased.ScatteringMIMOChannel", ...
    "runtime_pdsch_waveform_repeated_coherently", ...
    "matched_filter_plus_phased_array_beamforming_plus_ca_cfar", ...
    localComplexHash(tx.Waveform),localComplexHash(txPhysical),rawCubeHash, ...
    nPulses,size(referenceBank,2),height(detectionTable),matchedCount,rangeRMSE,azimuthRMSE, ...
    noisePowerW,unscaledPower,requestedPowerW, ...
    'VariableNames',{'ScenarioID','Enabled','Executed','EvidenceValid', ...
    'ChannelSource','WaveformSource','ProcessingSource','LogicalWaveformSHA256', ...
    'PhysicalWaveformSHA256','ReceivedSensingCubeSHA256','CoherentRepetitions', ...
    'ActiveMatchedFilterReferences','DetectionCount','MatchedTargetCount','RangeRMSEM','AzimuthRMSEDeg', ...
    'ReceiverNoisePowerW','UnscaledWaveformPower','ExecutedTransmitPowerW'});

result = struct( ...
    "ConfigTable",configTable, ...
    "TargetTruthTable",truthTable, ...
    "RangeProfileTable",rangeProfileTable, ...
    "RangeAngleTable",rangeAngleTable, ...
    "RangeDopplerTable",rangeDopplerTable, ...
    "DetectionTable",detectionTable, ...
    "CFARThresholdTable",thresholdTable, ...
    "RuntimeTable",runtimeTable, ...
    "RangeAnglePower",rangeAnglePower, ...
    "RangeDopplerPower",rangeDopplerPower, ...
    "RangeProfilePower",rangeProfilePower, ...
    "RangeM",rangeM, ...
    "AzimuthDeg",azimuthGrid, ...
    "DopplerHz",dopplerHz, ...
    "GNBPositionM",gnbPosition, ...
    "UEPositionM",uePosition, ...
    "EvidenceValid",logical(evidenceValid), ...
    "LogicalWaveformSHA256",string(localComplexHash(tx.Waveform)), ...
    "PhysicalWaveformSHA256",string(localComplexHash(txPhysical)), ...
    "ReceivedSensingCubeSHA256",string(rawCubeHash));
end

function [state,txArray,rxArray] = localResolveSensingAntennaState(cfg,runtimeContext,numWaveformColumns)
txEntry = sixgr.util.structGet(runtimeContext,"TxAntennaRuntime",[]);
rxEntry = sixgr.util.structGet(runtimeContext,"RxAntennaRuntime",[]);
if isstruct(txEntry) && isscalar(txEntry) && isfield(txEntry,"Antenna")
    if ~(isstruct(rxEntry) && isscalar(rxEntry) && isfield(rxEntry,"Antenna"))
        error("sixgr:lls:MissingISACRuntimeReceiveAntenna", ...
            "Full-PHY ISAC requires the runtime sensing receive array.");
    end
    txRuntime = localRuntimeArrayView(txEntry,numWaveformColumns,"isac_exact_pdsch_runtime_view");
    rxRuntime = rxEntry.Antenna;
    txArray = sixgr.util.structGet(txRuntime,"ArrayObj",[]);
    rxArray = sixgr.util.structGet(rxRuntime,"ArrayObj",[]);
    if isempty(txArray) || isempty(rxArray)
        error("sixgr:lls:MissingISACRuntimeArrayObject", ...
            "Full-PHY ISAC requires the Phased Array objects created by AntennaArrayFactory.");
    end
    state = struct("Enabled",true,"TxRole","gnb", ...
        "Tx",localRuntimeArrayState(txRuntime,txEntry.Metadata), ...
        "Rx",localRuntimeArrayState(rxRuntime,rxEntry.Metadata));
    return;
end

state = sixgr.lls.resolveAntennaState(cfg);
txArray = sixgr.lls.buildAntennaArray(state.Tx);
mode = lower(string(cfg.isac.sensingMode));
if mode == "monostatic_gnb"
    rxArray = sixgr.lls.buildAntennaArray(state.Tx);
else
    rxArray = sixgr.lls.buildAntennaArray(state.Rx);
end
end

function arr = localRuntimeArrayView(entry,numWaveformColumns,source)
arr = entry.Antenna;
matrix = sixgr.util.structGet(arr,"PortToElementMatrix",[]);
if size(matrix,2) == numWaveformColumns
    return;
end
[arr,~] = sixgr.rf.AntennaArrayFactory.logicalPortView( ...
    arr,sixgr.util.structGet(entry,"Metadata",struct()), ...
    numWaveformColumns,source);
end

function state = localRuntimeArrayState(arr,metadata)
orientation = [ ...
    double(sixgr.util.structGet(metadata,"Azimuth_deg", ...
        sixgr.util.structGet(metadata,"Heading_deg",0))), ...
    double(sixgr.util.structGet(metadata,"Tilt_deg",0)),0];
orientation(~isfinite(orientation)) = 0;
state = struct( ...
    "NumElements",double(sixgr.util.structGet(arr,"Nant", ...
        sixgr.util.structGet(arr,"NumElements",NaN))), ...
    "PortToElementMatrix",double(sixgr.util.structGet(arr,"PortToElementMatrix",[])), ...
    "OrientationDeg",orientation);
end

function position = localPosition(runtimeContext,fieldName,configured)
raw = sixgr.util.structGet(runtimeContext,fieldName,configured);
if ~(isnumeric(raw) && numel(raw) == 3 && all(isfinite(double(raw(:)))))
    error("sixgr:lls:MissingISACRuntimePosition", ...
        "ISAC requires a finite three-dimensional %s.",char(fieldName));
end
position = double(raw(:));
end

function axesMatrix = localOrientationAxes(orientationDeg)
angles = double(orientationDeg(:));
bearing = deg2rad(angles(1));
downtilt = deg2rad(angles(2));
slant = deg2rad(angles(3));
rz = [cos(bearing) -sin(bearing) 0; sin(bearing) cos(bearing) 0; 0 0 1];
ry = [cos(-downtilt) 0 sin(-downtilt); 0 1 0; -sin(-downtilt) 0 cos(-downtilt)];
rx = [1 0 0; 0 cos(slant) -sin(slant); 0 sin(slant) cos(slant)];
axesMatrix = rz*ry*rx;
end

function tableOut = localTargetTruth(positions,velocities,txPosition,rxPosition,rxAxes,mode,lambda)
n = size(positions,2);
targetId = (1:n).';
pathLength = zeros(n,1);
azimuth = zeros(n,1);
doppler = zeros(n,1);
radialSpeed = zeros(n,1);
for index = 1:n
    txVector = positions(:,index)-txPosition;
    rxVector = positions(:,index)-rxPosition;
    txRange = norm(txVector);
    rxRange = norm(rxVector);
    if mode == "monostatic_gnb"
        pathLength(index) = txRange;
    else
        pathLength(index) = txRange+rxRange;
    end
    localVector = rxAxes.'*rxVector;
    azimuth(index) = atan2d(localVector(2),localVector(1));
    bistaticProjection = dot(velocities(:,index), ...
        txVector/max(txRange,eps)+rxVector/max(rxRange,eps));
    doppler(index) = -bistaticProjection/lambda;
    if mode == "monostatic_gnb"
        radialSpeed(index) = -doppler(index)*lambda/2;
    else
        radialSpeed(index) = bistaticProjection/2;
    end
end
tableOut = table(targetId,positions(1,:).',positions(2,:).',positions(3,:).', ...
    velocities(1,:).',velocities(2,:).',velocities(3,:).', ...
    pathLength,azimuth,doppler,radialSpeed, ...
    'VariableNames',{'TargetId','X_m','Y_m','Z_m','Vx_mps','Vy_mps','Vz_mps', ...
    'ExpectedRangeM','ExpectedAzimuthDeg','ExpectedDopplerHz','EquivalentRadialSpeedMps'});
end

function [detections,thresholds] = localCACFAR(powerMap,rangeM,azimuthDeg,cfg)
[nRange,nAngle] = size(powerMap);
tr = double(cfg.trainingCellsRange); ta = double(cfg.trainingCellsAngle);
gr = double(cfg.guardCellsRange); ga = double(cfg.guardCellsAngle);
pfa = double(cfg.probabilityFalseAlarm);
candidate = false(nRange,nAngle);
threshold = nan(nRange,nAngle);
for r = tr+gr+1:nRange-(tr+gr)
    for a = ta+ga+1:nAngle-(ta+ga)
        window = powerMap(r-(tr+gr):r+(tr+gr),a-(ta+ga):a+(ta+ga));
        guardMask = false(size(window));
        centerR = tr+gr+1; centerA = ta+ga+1;
        guardMask(centerR-gr:centerR+gr,centerA-ga:centerA+ga) = true;
        training = window(~guardMask);
        nTraining = numel(training);
        noise = mean(training);
        alpha = nTraining*(pfa^(-1/nTraining)-1);
        threshold(r,a) = alpha*noise;
        candidate(r,a) = powerMap(r,a) > threshold(r,a) && ...
            powerMap(r,a) >= max(powerMap(r-1:r+1,a-1:a+1),[],"all");
    end
end
[rIndex,aIndex] = find(candidate);
if isempty(rIndex)
    detections = localEmptyDetectionTable();
else
    values = powerMap(candidate);
    [~,order] = sort(values,"descend");
    selected = false(size(order));
    acceptedR = zeros(0,1); acceptedA = zeros(0,1);
    maxDetections = double(cfg.maximumDetections);
    for index = 1:numel(order)
        rr = rIndex(order(index)); aa = aIndex(order(index));
        if any(abs(acceptedR-rr) <= double(cfg.nonMaximumSuppressionRangeBins) & ...
                abs(acceptedA-aa) <= double(cfg.nonMaximumSuppressionAngleBins))
            continue;
        end
        selected(index) = true;
        acceptedR(end+1,1) = rr; %#ok<AGROW>
        acceptedA(end+1,1) = aa; %#ok<AGROW>
        if numel(acceptedR) >= maxDetections
            break;
        end
    end
    keepOrder = order(selected);
    rIndex = rIndex(keepOrder); aIndex = aIndex(keepOrder);
    detectionId = (1:numel(rIndex)).';
    linearIndex = sub2ind(size(powerMap),rIndex,aIndex);
    detections = table(detectionId,rangeM(rIndex),azimuthDeg(aIndex).', ...
        powerMap(linearIndex),threshold(linearIndex), ...
        10*log10(max(powerMap(linearIndex)./max(threshold(linearIndex),realmin),realmin)), ...
        zeros(numel(rIndex),1),nan(numel(rIndex),1),nan(numel(rIndex),1),false(numel(rIndex),1), ...
        'VariableNames',{'DetectionId','MeasuredRangeM','MeasuredAzimuthDeg', ...
        'PowerLinear','CFARThresholdLinear','MarginDb','MatchedTargetId', ...
        'RangeErrorM','AzimuthErrorDeg','AcceptanceMatch'});
end
[rr,aa] = ndgrid(rangeM,azimuthDeg);
thresholds = table(rr(:),aa(:),threshold(:),candidate(:), ...
    'VariableNames',{'RangeM','AzimuthDeg','CFARThresholdLinear','RawDetection'});
end

function tableOut = localEmptyDetectionTable()
tableOut = table(zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1), ...
    'VariableNames',{'DetectionId','MeasuredRangeM','MeasuredAzimuthDeg', ...
    'PowerLinear','CFARThresholdLinear','MarginDb','MatchedTargetId', ...
    'RangeErrorM','AzimuthErrorDeg','AcceptanceMatch'});
end

function [detections,matchedCount,rangeRMSE,azimuthRMSE] = localMatchDetections(detections,truth,acceptance)
matchedCount = 0;
rangeErrors = zeros(0,1); azimuthErrors = zeros(0,1);
if isempty(detections)
    rangeRMSE = Inf; azimuthRMSE = Inf;
    return;
end
available = true(height(detections),1);
for target = 1:height(truth)
    rangeError = abs(detections.MeasuredRangeM-truth.ExpectedRangeM(target));
    angleError = abs(mod(detections.MeasuredAzimuthDeg-truth.ExpectedAzimuthDeg(target)+180,360)-180);
    score = rangeError/double(acceptance.maximumRangeErrorM) + ...
        angleError/double(acceptance.maximumAzimuthErrorDeg);
    score(~available) = Inf;
    [~,index] = min(score);
    if isfinite(score(index)) && ...
            rangeError(index) <= double(acceptance.maximumRangeErrorM) && ...
            angleError(index) <= double(acceptance.maximumAzimuthErrorDeg)
        matchedCount = matchedCount+1;
        available(index) = false;
        detections.MatchedTargetId(index) = truth.TargetId(target);
        detections.RangeErrorM(index) = rangeError(index);
        detections.AzimuthErrorDeg(index) = angleError(index);
        detections.AcceptanceMatch(index) = true;
        rangeErrors(end+1,1) = rangeError(index); %#ok<AGROW>
        azimuthErrors(end+1,1) = angleError(index); %#ok<AGROW>
    end
end
if matchedCount == 0
    rangeRMSE = Inf; azimuthRMSE = Inf;
else
    rangeRMSE = sqrt(mean(rangeErrors.^2));
    azimuthRMSE = sqrt(mean(azimuthErrors.^2));
end
end

function valuesDb = localRelativeDb(values,peak)
valuesDb = 10*log10(max(values,realmin)/max(peak,realmin));
end

function digest = localComplexHash(value)
realBytes = typecast(double(real(value(:))),"uint8");
imagBytes = typecast(double(imag(value(:))),"uint8");
digest = string(sixgr.util.sha256Hex([realBytes(:);imagBytes(:)]));
end

function localReleaseArrays(txArray,rxArray)
release(txArray);
release(rxArray);
end
