function studies = runIntegrationStudies(cfg,bundles,trialRows)
%RUNINTEGRATIONSTUDIES Deterministic event/TDD/budget/beam analyses.

phaseDeg = double(cfg.events.commonPhaseStepDeg(:));
positions = double(cfg.events.eventPositionFraction(:));
[phaseGrid,positionGrid] = ndgrid(phaseDeg,positions);
gain = abs(positionGrid+(1-positionGrid).*exp(1i*deg2rad(phaseGrid))).^2;
eventWaveform = bundles.W0.SensingWaveform(:);
eventEnergy = abs(eventWaveform).^2;
cumulativeEnergy = cumsum(eventEnergy)/sum(eventEnergy);
waveformGain = zeros(numel(phaseGrid),1);
executedFraction = zeros(numel(phaseGrid),1);
analyticalExecuted = zeros(numel(phaseGrid),1);
measuredDopplerBiasHz=zeros(numel(phaseGrid),1);
wrongPeak=false(numel(phaseGrid),1);
symbolLengths=double(bundles.W0.CPLengths(:))+double(bundles.W0.OFDMInfo.Nfft);
symbolStarts=[0;cumsum(symbolLengths)];
eventSymbols=double(bundles.W0.SensingSymbolIndices(:))+1;
eventTimes=(symbolStarts(eventSymbols)+double(bundles.W0.CPLengths(eventSymbols)) ...
    +double(bundles.W0.OFDMInfo.Nfft)/2)/double(bundles.W0.OFDMInfo.SampleRate);
for rowIndex=1:numel(phaseGrid)
    cut=find(cumulativeEnergy>=positionGrid(rowIndex),1,"first");
    executedFraction(rowIndex)=sum(eventEnergy(1:cut))/sum(eventEnergy);
    received=eventWaveform;
    received(cut+1:end)=received(cut+1:end)*exp(1i*deg2rad(phaseGrid(rowIndex)));
    waveformGain(rowIndex)=abs(eventWaveform'*received)^2/sum(eventEnergy)^2;
    a=executedFraction(rowIndex);
    analyticalExecuted(rowIndex)=abs(a+(1-a)*exp(1i*deg2rad(phaseGrid(rowIndex))))^2;
    observations=complex(zeros(numel(eventSymbols),1));
    for occasionIndex=1:numel(eventSymbols)
        symbol=eventSymbols(occasionIndex);
        indices=symbolStarts(symbol)+(1:symbolLengths(symbol));
        reference=eventWaveform(indices);
        observations(occasionIndex)=reference'*received(indices)/sum(abs(reference).^2);
    end
    measuredDopplerBiasHz(rowIndex)=polyfit(eventTimes,unwrap(angle(observations)),1)*[1;0]/(2*pi);
    spectrum=fftshift(abs(fft(observations,128)).^2);
    [~,peakBin]=max(spectrum);
    wrongPeak(rowIndex)=peakBin~=65;
end
studies.EventPhase = table(phaseGrid(:),positionGrid(:),executedFraction, ...
    gain(:),10*log10(max(gain(:),realmin)),waveformGain, ...
    10*log10(max(waveformGain,realmin)),analyticalExecuted, ...
    waveformGain-analyticalExecuted,measuredDopplerBiasHz,wrongPeak, ...
    repmat(string(bundles.W0.SensingWaveformSHA256),numel(phaseGrid),1), ...
    repmat("executed_time_domain_waveform_event",numel(phaseGrid),1), ...
    'VariableNames',{'PhaseStepDeg','FractionBeforeEvent', ...
    'ExecutedEnergyFractionBeforeEvent','CoherentGainLinear','CoherentGainDb', ...
    'WaveformCoherentGainLinear','WaveformCoherentGainDb', ...
    'AnalyticalGainAtExecutedFraction','WaveformAnalyticalDelta', ...
    'MeasuredDopplerBiasHz','WrongPeak', ...
    'SourceWaveformSHA256','EvidenceClass'});

patterns = string(fieldnames(cfg.tdd.patterns));
tddParts = cell(numel(patterns),1);
analysisSlots=double(cfg.tdd.analysisSlots);
for i = 1:numel(patterns)
    token = string(cfg.tdd.patterns.(patterns(i)));
    repetitions = ceil(analysisSlots/strlength(token));
    expanded = char(join(repmat(token,1,repetitions),""));
    expanded = expanded(1:analysisSlots);
    mask = double(expanded == 'D').';
    response = abs(fft(mask,analysisSlots)).^2;
    response = fftshift(response/max(response));
    executedWaveform = complex(zeros(analysisSlots*numel(bundles.W0.SensingWaveform),1));
    for slotIndex=1:analysisSlots
        if mask(slotIndex)>0
            sampleIndices=(slotIndex-1)*numel(bundles.W0.SensingWaveform)+(1:numel(bundles.W0.SensingWaveform));
            executedWaveform(sampleIndices)=bundles.W0.SensingWaveform;
        end
    end
    executedHash=string(localComplexHash(executedWaveform));
    executedEnergy=sum(abs(executedWaveform).^2);
    tddParts{i} = table(repmat(patterns(i),analysisSlots,1),(0:analysisSlots-1).',mask, ...
        ((-analysisSlots/2):(analysisSlots/2-1)).'/analysisSlots,response, ...
        repmat(executedHash,analysisSlots,1), ...
        repmat(numel(executedWaveform),analysisSlots,1), ...
        repmat(executedEnergy,analysisSlots,1), ...
        repmat("executed_tdd_masked_cp_ofdm_waveform",analysisSlots,1), ...
        'VariableNames',{'TDDPattern','SlotIndex','DLSensingAvailable', ...
        'NormalizedDopplerBin','MaskDFTPowerNormalized','ExecutedWaveformSHA256', ...
        'ExecutedWaveformSamples','ExecutedWaveformEnergy','EvidenceClass'});
end
studies.TDD = vertcat(tddParts{:});

w0 = bundles.W0;
configured = w0.ConfiguredMask;
ratios = double(cfg.collisions.ratiosPercent(:));
responses = string(cfg.collisions.responses(:));
patternParts = cell(numel(ratios)*numel(responses),1);
index = 0;
for ratio = ratios.'
    collision = false(size(configured));
    active = find(configured);
    count = round(numel(active)*ratio/100);
    if count > 0, collision(active(1:count)) = true; end
    for response = responses.'
        index = index+1;
        state = sixgr.isac.deriveEffectivePattern(configured,collision,response,"preserved");
        [executedGrid,evidenceClass]=localExecutedSensingGrid(bundles.W0,state,response, ...
            double(cfg.collisions.knownRatioPowerScalingDb));
        executedWaveform=nrOFDMModulate(bundles.W0.Carrier,executedGrid, ...
            "Windowing",double(cfg.waveform.ofdmWindowingSamples));
        patternParts{index} = table(ratio,response,state.ConfiguredObservations, ...
            nnz(collision),state.RetainedObservations,state.CoherentSegmentCount, ...
            string(state.RelationClass),string(localComplexHash(executedWaveform)), ...
            sum(abs(executedWaveform).^2),true,evidenceClass, ...
            'VariableNames',{'CollisionRatioPercent','Response','ConfiguredObservations', ...
            'CollidedObservations','RetainedObservations','CoherentSegments','RelationClass', ...
            'ExecutedWaveformSHA256','ExecutedWaveformEnergy','WaveformExecuted','EvidenceClass'});
    end
end

studies.EffectivePatterns = vertcat(patternParts{1:index});

% Transparent candidate properties are derived from the observed pattern and
% configured response classes. They remain study decisions, not PHY truth.
baseCount = nnz(configured);
candidates(1) = localCandidate("share_reuse",1,baseCount,0,0,0,12,true);
candidates = repmat(candidates(1),4,1);
candidates(2) = localCandidate("sensing_puncture",1,round(0.9*baseCount),0,0,0,8,true);
candidates(3) = localCandidate("recoverable_relocation",2,round(0.5*baseCount),20,0.25,50,5,true);
candidates(4) = localCandidate("occasion_drop_defer",1,round(0.75*baseCount),0,0,0,10,true);
budget = struct("MaxCoherentSegments",2,"MinimumSegmentLength",8, ...
    "MaximumResidualPhaseDeg",30,"MaximumResidualTimingBins",0.5, ...
    "MaximumResidualFrequencyHz",10);
measurements = ["range_only","range_doppler","range_doppler_angle"];
budgetParts = cell(numel(measurements),1);
selectionParts = cell(numel(measurements),1);
for i = 1:numel(measurements)
    [selected,evaluation] = sixgr.isac.selectCollisionResponse(candidates,budget,measurements(i));
    evaluation.Selected = evaluation.Response == string(selected.Name);
    budgetParts{i} = evaluation;
    selectionParts{i} = table(measurements(i),string(selected.Name), ...
        logical(selected.Feasible),logical(selected.FallbackRequired), ...
        'VariableNames',{'Measurement','SelectedResponse','Feasible','FallbackRequired'});
end
studies.BudgetEvaluation = vertcat(budgetParts{:});
studies.BudgetSelection = vertcat(selectionParts{:});

studies.BeamManagement = localBeamStudy(cfg);
halfWidths = double(cfg.assistance.dopplerHalfWidthCyclesPerSlot(:));
targetRows = trialRows(trialRows.TargetPresent,:);
wrongRate = mean(targetRows.WrongPeak);
rmse = sqrt(mean(targetRows.DopplerErrorHz.^2,"omitnan"));
studies.Assistance = table(halfWidths, ...
    repmat(wrongRate,numel(halfWidths),1), ...
    repmat(rmse,numel(halfWidths),1),round(2*halfWidths*1000)+1, ...
    'VariableNames',{'DopplerHalfWidthCyclesPerSlot','ObservedWrongPeakRate', ...
    'ObservedDopplerRMSEHz','RelativeSearchOperations'});

studies.PeriodicPhase=localPeriodicPhaseStudy(cfg,bundles.W0);
studies.TimingUpdate=localTimingUpdateStudy(cfg,bundles.W0);
studies.CFOUpdate=localCFOStudy(cfg,bundles.W0);
studies.PortPhase=localPortPhaseStudy(cfg,bundles.W0);
studies.Interference=localInterferenceStudy(cfg,bundles);
studies.ISIICI=localISIICIStudy(cfg,bundles);
studies.Overhead=localOverheadStudy(studies.EffectivePatterns,bundles.W0);
studies.EventSummary=localEventSummary(studies);

studies.Fairness = table(["Equal occupied RE";"Equal sensing energy"; ...
    "Equal bandwidth";"Equal observation time";"Equal antenna ports"; ...
    "Paired target/channel seed";"Equal receiver knowledge"],true(7,1), ...
    repmat("enforced_by_joint_master_yaml",7,1), ...
    'VariableNames',{'Criterion','Satisfied','Evidence'});
end

function c = localCandidate(name,segments,minLength,phase,timing,frequency,cost,crossPort)
c = struct("Name",name,"CoherentSegmentCount",segments, ...
    "MinimumSegmentLength",minLength,"ResidualPhaseDeg",phase, ...
    "ResidualTimingBins",timing,"ResidualFrequencyHz",frequency, ...
    "Cost",cost,"CrossPortRelationAvailable",crossPort);
end

function tableOut = localBeamStudy(cfg)
ages = double(cfg.beamManagement.informationAgeMs(:));
mode = lower(string(cfg.run.activeMode));
modeCfg = sixgr.util.structGet(cfg,"run.modes."+mode,struct());
nTrials = max(1,double(modeCfg.targetTrials));
prior = rng; cleanup = onCleanup(@() rng(prior)); %#ok<NASGU>
rng(double(cfg.run.masterSeed)+7100,"twister");
angleRange = double(cfg.beamManagement.targetInitialAngleRangeDeg(:));
rateRange = double(cfg.beamManagement.angularRateRangeDegPerSecond(:));
narrowRange = double(cfg.beamManagement.narrowAngleRangeDeg(:));
nBeams = double(cfg.beamManagement.narrowBeamCount);
beamAngles = linspace(narrowRange(1),narrowRange(2),nBeams);
rows = cell(numel(ages),1);
for i = 1:numel(ages)
    initial = angleRange(1)+(angleRange(2)-angleRange(1))*rand(nTrials,1);
    rate = rateRange(1)+(rateRange(2)-rateRange(1))*rand(nTrials,1);
    actual = initial+rate*ages(i)/1000;
    sensed = initial+randn(nTrials,1)*double(cfg.beamManagement.sensingAngleErrorStdDeg);
    predicted = sensed+rate*ages(i)/1000;
    [~,actualBeam] = min(abs(actual-beamAngles),[],2);
    [~,predictedBeam] = min(abs(predicted-beamAngles),[],2);
    included = abs(actualBeam-predictedBeam) <= 2;
    angleGap = abs(actual-predicted);
    fallback = angleGap > double(cfg.beamManagement.confidenceGateStdMultiplier)* ...
        double(cfg.beamManagement.sensingAngleErrorStdDeg);
    rows{i} = table(ages(i),nTrials,mean(included),median(angleGap), ...
        prctile(angleGap,90),mean(fallback), ...
        mean(4+fallback*double(cfg.beamManagement.wideBeamCount)), ...
        'VariableNames',{'InformationAgeMs','Trials','Top1NeighborhoodInclusion', ...
        'MedianAngleGapDeg','P90AngleGapDeg','FallbackRate', ...
        'MeanCommunicationMeasurements'});
end
tableOut = vertcat(rows{:});
end

function [grid,evidenceClass]=localExecutedSensingGrid(bundle,state,response,powerScalingDb)
grid=complex(zeros(size(bundle.SensingGrid)));
existing=state.EffectiveMask & bundle.ConfiguredMask;
grid(existing)=bundle.SensingGrid(existing);
added=state.EffectiveMask & ~bundle.ConfiguredMask;
[rows,cols]=find(added);
for i=1:numel(rows)
    source=[];
    if contains(response,"time_relocation") || response=="recoverable_relocation"
        candidates=find(bundle.ConfiguredMask(rows(i),1:max(1,cols(i)-1)),1,"last");
        if ~isempty(candidates), source=sub2ind(size(grid),rows(i),candidates); end
    elseif response=="frequency_relocation" || response=="comb_pattern_selection"
        candidates=find(bundle.ConfiguredMask(1:max(1,rows(i)-1),cols(i)),1,"last");
        if ~isempty(candidates), source=sub2ind(size(grid),candidates,cols(i)); end
    end
    if isempty(source)
        error("sixgr:isac:CollisionRelocationSourceMissing", ...
            "No configured source RE exists for relocated target (%d,%d).",rows(i),cols(i));
    end
    grid(rows(i),cols(i))=bundle.SensingGrid(source);
end
if response=="known_ratio_power_scaling"
    grid=grid*10^(powerScalingDb/20);
end
switch response
    case {"sensing_puncture","time_relocation","frequency_relocation", ...
            "comb_pattern_selection","known_ratio_power_scaling", ...
            "occasion_drop_defer","recoverable_relocation"}
        evidenceClass="executed_sensing_resource_action_cp_ofdm_waveform";
    case "share_reuse"
        evidenceClass="executed_shared_sensing_waveform_communication_decode_evaluated_elsewhere";
    case "communication_muting"
        evidenceClass="executed_sensing_waveform_communication_muting_not_in_this_component_trial";
    case "beam_precoder_change"
        evidenceClass="executed_sensing_waveform_spatial_precoder_requires_array_trial";
    otherwise
        error("sixgr:isac:UnknownCollisionResponse", ...
            "No execution-evidence classification exists for %s.",response);
end
end

function digest=localComplexHash(value)
digest=sixgr.util.sha256Hex(typecast([real(value(:));imag(value(:))],"uint8"));
end

function result=localPeriodicPhaseStudy(cfg,bundle)
halfPeriods=double(cfg.events.periodicHalfPeriodOccasions(:));
phaseSteps=intersect(double(cfg.events.commonPhaseStepDeg(:)),[10;20;30;45;60;90]);
nOccasions=double(cfg.events.periodicObservationCount);
nFFT=double(cfg.events.periodicFFTLength);
spectrumParts=cell(numel(halfPeriods)*numel(phaseSteps),1);
summaryParts=cell(numel(spectrumParts),1); index=0;
x=bundle.SensingWaveform(:); energy=sum(abs(x).^2);
for halfPeriod=halfPeriods.'
    state=mod(floor((0:nOccasions-1)'/halfPeriod),2);
    for phaseStep=phaseSteps.'
        index=index+1;
        weights=exp(1i*deg2rad(phaseStep)*state);
        observations=complex(zeros(nOccasions,1));
        for occasion=1:nOccasions
            received=x*weights(occasion);
            observations(occasion)=x'*received/energy;
        end
        power=fftshift(abs(fft(observations,nFFT)).^2);
        power=power/max(power);
        bins=((-nFFT/2):(nFFT/2-1)).'/nFFT;
        linePower=fftshift(abs(fft(observations,nOccasions)).^2);
        linePower=linePower/max(linePower);
        lineBins=((-nOccasions/2):(nOccasions/2-1)).'/nOccasions;
        nonzero=abs(lineBins)>0;
        [ghostPower,ghostIndex]=max(linePower(nonzero));
        nonzeroBins=lineBins(nonzero); measured=abs(nonzeroBins(ghostIndex));
        digest=string(localComplexHash(observations));
        spectrumParts{index}=table(repmat(halfPeriod,nFFT,1), ...
            repmat(phaseStep,nFFT,1),bins,power,10*log10(max(power,realmin)), ...
            repmat(digest,nFFT,1), ...
            'VariableNames',{'HalfPeriodOccasions','PhaseStepDeg', ...
            'NormalizedDopplerOffset','PowerNormalized','PowerDb', ...
            'MatchedObservationSHA256'});
        summaryParts{index}=table(halfPeriod,phaseStep,1/(2*halfPeriod), ...
            measured,ghostPower,digest, ...
            "executed_periodic_phase_on_time_domain_waveform", ...
            'VariableNames',{'HalfPeriodOccasions','PhaseStepDeg', ...
            'ExpectedGhostOffsetNormalized','MeasuredGhostOffsetNormalized', ...
            'GhostPowerNormalized','MatchedObservationSHA256','EvidenceClass'});
    end
end
result=struct("Spectrum",vertcat(spectrumParts{1:index}), ...
    "Summary",vertcat(summaryParts{1:index}));
end

function result=localTimingUpdateStudy(cfg,bundle)
offsets=double(cfg.events.timingOffsetBins(:)); models=string(cfg.events.timingModels(:));
x=bundle.SensingWaveform(:); n=numel(x); cut=floor(n/2); energy=sum(abs(x).^2);
parts=cell(numel(offsets)*numel(models),1); index=0;
for model=models.'
    for offset=offsets.'
        index=index+1; received=x;
        shifted=localFractionalCircularDelay(x(cut+1:end),offset);
        if model=="rf_time_reference_shift"
            shifted=shifted*exp(-1i*2*pi*double(bundle.CarrierProfile.frequencyHz)* ...
                offset/double(bundle.OFDMInfo.SampleRate));
        end
        received(cut+1:end)=shifted;
        gain=abs(x'*received)^2/energy^2;
        parts{index}=table(model,offset,gain,10*log10(max(gain,realmin)), ...
            string(localComplexHash(received)), ...
            "executed_midpoint_timing_update_on_time_domain_waveform", ...
            'VariableNames',{'TimingModel','OffsetNativeBins','CoherentGainLinear', ...
            'CoherentGainDb','ExecutedWaveformSHA256','EvidenceClass'});
    end
end
result=vertcat(parts{1:index});
end

function result=localCFOStudy(cfg,bundle)
offsets=double(cfg.events.residualFrequencyHz(:));
x=bundle.SensingWaveform(:); n=numel(x); cut=floor(n/2); fs=double(bundle.OFDMInfo.SampleRate);
energy=sum(abs(x).^2); parts=cell(numel(offsets),1);
lambda=double(cfg.channel.propagationSpeedMps)/double(bundle.CarrierProfile.frequencyHz);
for i=1:numel(offsets)
    received=x; time=(0:n-cut-1)'/fs;
    received(cut+1:end)=received(cut+1:end).*exp(1i*2*pi*offsets(i)*time);
    gain=abs(x'*received)^2/energy^2;
    parts{i}=table(offsets(i),gain,10*log10(max(gain,realmin)), ...
        abs(offsets(i))*lambda/2,string(localComplexHash(received)), ...
        "executed_midpoint_residual_frequency_update", ...
        'VariableNames',{'ResidualFrequencyHz','CoherentGainLinear', ...
        'CoherentGainDb','EquivalentMonostaticVelocityBiasMps', ...
        'ExecutedWaveformSHA256','EvidenceClass'});
end
result=vertcat(parts{:});
end

function result=localPortPhaseStudy(cfg,bundle)
slopes=double(cfg.events.portPhaseSlopeDeg(:)); n=double(cfg.beamManagement.arrayElements);
spacing=double(cfg.antenna.elementSpacingWavelength);
expected=double(cfg.events.portPhaseReferenceAzimuthDeg);
steering=exp(1i*2*pi*spacing*(0:n-1).'*sind(expected));
angles=(double(cfg.antenna.angleEstimation.minimumDeg): ...
    double(cfg.antenna.angleEstimation.stepDeg): ...
    double(cfg.antenna.angleEstimation.maximumDeg)).';
scan=exp(1i*2*pi*spacing*(0:n-1).'*sind(angles.'));
parts=cell(numel(slopes),1);
for i=1:numel(slopes)
    snapshot=steering.*exp(1i*deg2rad(slopes(i))*(0:n-1).');
    power=abs(snapshot'*scan).^2; [~,peak]=max(power);
    measured=angles(peak); errorDeg=mod(measured-expected+180,360)-180;
    parts{i}=table(slopes(i),n,expected,measured,errorDeg, ...
        string(localComplexHash(snapshot)), ...
        "executed_multiport_snapshot_and_beam_scan", ...
        'VariableNames',{'PortPhaseSlopeDeg','ArrayElements','ExpectedAzimuthDeg', ...
        'MeasuredAzimuthDeg','AzimuthErrorDeg','SnapshotSHA256','EvidenceClass'});
end
result=vertcat(parts{:});
end

function result=localInterferenceStudy(cfg,bundles)
if ~logical(cfg.interferenceStudy.enabled), result=table(); return; end
desired=bundles.W0; interferer=bundles.W1;
x=desired.Waveform(:); z=interferer.Waveform(:); fs=double(desired.OFDMInfo.SampleRate);
cp=min(double(desired.CPLengths)); dataMask=~desired.TransmittedMask;
txData=desired.Grid(dataMask); parts=cell(0,1); index=0;
for powerDb=double(cfg.interferenceStudy.intercellRelativePowerDb(:)).'
    for delayRatio=double(cfg.interferenceStudy.asynchronousDelayOverCP(:)).'
        for cfo=double(cfg.interferenceStudy.asynchronousFrequencyOffsetHz(:)).'
            index=index+1; delay=round(delayRatio*cp);
            interference=10^(powerDb/20)*localDelayDoppler(z,delay,cfo,fs);
            received=x+interference;
            grid=nrOFDMDemodulate(desired.Carrier,received);
            evm=sqrt(mean(abs(grid(dataMask)-txData).^2)/mean(abs(txData).^2));
            parts{index}=table("intercell_async",powerDb,delayRatio,cfo,evm, ...
                mean(abs(interference).^2)/mean(abs(x).^2), ...
                string(localComplexHash(received)), ...
                "executed_asynchronous_intercell_cp_ofdm_waveform", ...
                'VariableNames',{'InterferenceType','RelativePowerDb','DelayOverCP', ...
                'FrequencyOffsetHz','CommunicationEVMRMS','InterferencePowerRatio', ...
                'ReceivedWaveformSHA256','EvidenceClass'});
        end
    end
end
for residualDb=double(cfg.interferenceStudy.selfInterferenceResidualDb(:)).'
    index=index+1; delay=round(double(cfg.interferenceStudy.sensingEchoDelayOverCP)*cp);
    residual=10^(residualDb/20)*x;
    echo=10^(double(cfg.channel.targetPathGainDb)/20)*localDelayDoppler( ...
        desired.SensingWaveform(:),delay,0,fs);
    received=residual+echo;
    parts{index}=table("monostatic_self",residualDb, ...
        double(cfg.interferenceStudy.sensingEchoDelayOverCP),0,NaN, ...
        mean(abs(residual).^2)/max(mean(abs(echo).^2),realmin), ...
        string(localComplexHash(received)), ...
        "executed_residual_self_interference_plus_target_echo", ...
        'VariableNames',parts{1}.Properties.VariableNames);
end
result=vertcat(parts{:});
end

function result=localISIICIStudy(cfg,bundles)
modeCfg=cfg.run.modes.(char(cfg.run.activeMode));
delays=double(modeCfg.delayOverCP(:)); dopplers=double(modeCfg.normalizedDoppler(:));
profiles=string(cfg.interferenceStudy.isiIciWaveformProfiles(:)).';
alpha=10^(double(cfg.interferenceStudy.multipathEchoRelativePowerDb)/20);
parts=cell(numel(profiles)*numel(delays)*numel(dopplers),1); index=0;
for profile=profiles
    bundle=bundles.(profile); x=bundle.Waveform(:); fs=double(bundle.OFDMInfo.SampleRate);
    cp=min(double(bundle.CPLengths)); nFFT=double(bundle.OFDMInfo.Nfft);
    nSC=size(bundle.Grid,1); k=(-floor(nSC/2):ceil(nSC/2)-1).'+12*double(bundle.Carrier.NStartGrid);
    symbolLengths=double(bundle.CPLengths(:))+nFFT; starts=[0;cumsum(symbolLengths)];
    times=(starts(1:end-1)+double(bundle.CPLengths(:))+nFFT/2)/fs;
    dataMask=~bundle.TransmittedMask; txData=bundle.Grid(dataMask);
    for delayRatio=delays.'
        delay=round(delayRatio*cp);
        for normalizedDoppler=dopplers.'
            index=index+1; cfo=normalizedDoppler*double(bundle.Carrier.SubcarrierSpacing)*1e3;
            echo=localDelayDoppler(x,delay,cfo,fs); received=x+alpha*echo;
            rxGrid=nrOFDMDemodulate(bundle.Carrier,received);
            H=1+alpha*exp(-1i*2*pi*k*delay/nFFT).*exp(1i*2*pi*times.'*cfo);
            equalized=rxGrid./H; evm=sqrt(mean(abs(equalized(dataMask)-txData).^2)/ ...
                mean(abs(txData).^2));
            parts{index}=table(profile,delayRatio,normalizedDoppler,delay,cfo,evm, ...
                string(localComplexHash(received)), ...
                "executed_two_path_cp_ofdm_with_diagonal_equalizer", ...
                'VariableNames',{'WaveformProfile','DelayOverCP','NormalizedDoppler', ...
                'DelaySamples','DopplerHz','ResidualEVMRMS','ReceivedWaveformSHA256', ...
                'EvidenceClass'});
        end
    end
end
result=vertcat(parts{1:index});
end

function result=localOverheadStudy(patterns,bundle)
totalRE=numel(bundle.ConfiguredMask);
result=table(patterns.Response,patterns.CollisionRatioPercent, ...
    100*patterns.ConfiguredObservations/totalRE, ...
    100*(patterns.ConfiguredObservations-patterns.RetainedObservations)./ ...
        max(patterns.ConfiguredObservations,1), ...
    100*patterns.RetainedObservations./max(patterns.ConfiguredObservations,1), ...
    'VariableNames',{'Response','CollisionRatioPercent','Overhead1RelativeToBaselinePercent', ...
    'Overhead2LostObservationPercent','RetainedObservationPercent'});
end

function result=localEventSummary(studies)
parts=cell(5,1);
t=studies.EventPhase;
parts{1}=table(repmat("common_phase_step",height(t),1),repmat("phase_step",height(t),1), ...
    t.PhaseStepDeg,repmat("deg",height(t),1),t.WaveformCoherentGainLinear, ...
    t.MeasuredDopplerBiasHz,t.SourceWaveformSHA256,t.EvidenceClass, ...
    'VariableNames',{'EventType','Parameter','Value','Units','MeasuredCoherentGain', ...
    'MeasuredBias','EvidenceSHA256','EvidenceClass'});
t=studies.TimingUpdate;
parts{2}=table(repmat("timing_update",height(t),1),t.TimingModel,t.OffsetNativeBins, ...
    repmat("native_delay_bin",height(t),1),t.CoherentGainLinear,t.OffsetNativeBins, ...
    t.ExecutedWaveformSHA256,t.EvidenceClass,'VariableNames',parts{1}.Properties.VariableNames);
t=studies.CFOUpdate;
parts{3}=table(repmat("residual_frequency_update",height(t),1), ...
    repmat("frequency_offset",height(t),1),t.ResidualFrequencyHz,repmat("Hz",height(t),1), ...
    t.CoherentGainLinear,t.EquivalentMonostaticVelocityBiasMps,t.ExecutedWaveformSHA256, ...
    t.EvidenceClass,'VariableNames',parts{1}.Properties.VariableNames);
t=studies.PortPhase;
parts{4}=table(repmat("port_phase_slope",height(t),1),repmat("phase_per_port",height(t),1), ...
    t.PortPhaseSlopeDeg,repmat("deg_per_port",height(t),1),nan(height(t),1), ...
    t.AzimuthErrorDeg,t.SnapshotSHA256,t.EvidenceClass, ...
    'VariableNames',parts{1}.Properties.VariableNames);
t=studies.PeriodicPhase.Summary;
parts{5}=table(repmat("periodic_two_state_phase",height(t),1), ...
    "half_period_"+string(t.HalfPeriodOccasions),t.PhaseStepDeg,repmat("deg",height(t),1), ...
    t.GhostPowerNormalized,t.MeasuredGhostOffsetNormalized,t.MatchedObservationSHA256, ...
    t.EvidenceClass,'VariableNames',parts{1}.Properties.VariableNames);
result=vertcat(parts{:});
end

function shifted=localFractionalCircularDelay(x,delay)
n=numel(x); bins=(0:n-1).';
shifted=ifft(fft(x).*exp(-1i*2*pi*bins*delay/n));
end

function y=localDelayDoppler(x,delaySamples,dopplerHz,fs)
x=x(:); delaySamples=max(0,round(delaySamples));
n=numel(x);
if delaySamples>=n
    error("sixgr:isac:InterferenceDelayOutsideWaveform", ...
        "Delay %d exceeds waveform length %d.",delaySamples,n);
end
shifted=[complex(zeros(delaySamples,1));x(1:n-delaySamples)];
time=(0:numel(x)-1)'/fs;
y=shifted.*exp(1i*2*pi*dopplerHz*time);
end
