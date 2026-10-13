function ok=testCFOReceivedCoherenceWindow()
% Independent receiver-algorithm checks, not a statistical qualification.
% These seeds/filters do not come from the retained failed PDSCH captures.
setup6GRSimToolkit('Verbose',false);
stream=RandStream('mt19937ar','Seed',731093);
policy=struct('Policy',"received_coherence_window", ...
    'WindowFraction',0.5,'FalseAlarmProbability',0.001);
exactCount=0; noisyError=zeros(32,2); noiseAccepted=0;
for spacing=[15 30 60 120]
    carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',spacing);
    [wave,info,firstSlot]=makeBurst(carrier,stream);
    fs=info.SampleRate; cp=min(info.OFDMSamplingResolution.CyclicPrefixLengthsPerSlot);
    % Explicit test channel with independently chosen precursor/postcursor
    % support. The receiver gets samples/clock only, not the filter or crop.
    h=complex(zeros(ceil(0.30*cp)+1,2));
    h(1,:)=[0.7 0.4i]; h(ceil(.15*cp)+1,:)=[1 0.8];
    h(end,:)=[-.45i .55];
    propagated=filter(h(:,1),1,wave(:,1))+filter(h(:,2),1,wave(:,2));
    propagated=[propagated,filter(flipud(h(:,1)),1,wave(:,1))];
    crop=floor(.125*cp);
    indices=firstSlot+crop+(1:info.OFDMSamplingResolution.CurrentSlotSamples);
    for cfo=[0 -430 710]
        phase=exp(2i*pi*cfo*(0:size(propagated,1)-1)'/fs);
        received=propagated.*phase; received=received(indices,:);
        [estimated,e]=sixgr.phy.rx.estimateCFOFromCyclicPrefix(received,info,fs,policy);
        assert(e.EstimateAvailable && abs(estimated-cfo)<1e-6, ...
            'sixgr:test:CPWindowMultipath','Noiseless SCS=%g CFO=%g returned %g.',spacing,cfo,estimated);
        assert(e.ObservationPairCount>0 && e.ObservationCoherenceSquared>1-1e-12);
        assert(e.ObservationStartFromUsefulSymbol_samples>=-cp && ...
            e.ObservationStartFromUsefulSymbol_samples+e.ObservationLength_samples<=0);
        % Amplitude, receiver-branch ordering and nuisance source fields
        % cannot supply CFO or alter the selected physical frequency.
        audit=info; audit.InjectedCFO_Hz=-9999; audit.TruePathDelays=[1 999];
        other=sixgr.phy.rx.estimateCFOFromCyclicPrefix(received(:,[2 1])*1e-9,audit,fs,policy);
        assert(abs(other-estimated)<1e-6);
        exactCount=exactCount+1;
    end
end

% Independent noisy multipath trials compare estimation errors, not CRC-
% chosen windows. Fixed population and receiver policy are declared above.
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',30);
for trial=1:size(noisyError,1)
    [wave,info,firstSlot]=makeBurst(carrier,stream);
    cp=min(info.OFDMSamplingResolution.CyclicPrefixLengthsPerSlot);
    h=zeros(ceil(.30*cp)+1,1); h(1)=.7; h(ceil(.15*cp)+1)=1; h(end)=-.6i;
    wave=filter(h,1,wave);
    fs=info.SampleRate; cfo=300*(-1)^trial;
    wave=wave.*exp(2i*pi*cfo*(0:size(wave,1)-1)'/fs);
    power=mean(abs(wave).^2,'all');
    wave=wave+sqrt(power*1e-3/2)*complex(randn(stream,size(wave)),randn(stream,size(wave)));
    received=wave(firstSlot+floor(.125*cp)+(1:info.OFDMSamplingResolution.CurrentSlotSamples),:);
    full=sixgr.phy.rx.estimateCFOFromCyclicPrefix(received,info,fs);
    [window,e]=sixgr.phy.rx.estimateCFOFromCyclicPrefix(received,info,fs,policy);
    assert(e.EstimateAvailable);
    noisyError(trial,:)=[full-cfo window-cfo];
end
rmse=sqrt(mean(noisyError.^2,1));
assert(rmse(2)<rmse(1),'sixgr:test:CPWindowNoiseRegression', ...
    'Independent multipath RMSE did not improve: full=%g window=%g Hz.',rmse(1),rmse(2));

% Null checks are deterministic regression coverage, not enough episodes to
% claim the configured false-alarm probability is statistically qualified.
for trial=1:128
    empty=complex(randn(stream,size(received)),randn(stream,size(received)));
    [estimate,e]=sixgr.phy.rx.estimateCFOFromCyclicPrefix(empty,info,fs,policy);
    noiseAccepted=noiseAccepted+double(e.EstimateAvailable);
    assert(e.EstimateAvailable || isnan(estimate));
end
assert(noiseAccepted<=2,'sixgr:test:CPWindowNoiseOnly','Unexpected noise-only CFO acceptance: %d/128.',noiseAccepted);
[estimate,e]=sixgr.phy.rx.estimateCFOFromCyclicPrefix(zeros(size(received)),info,fs,policy);
assert(~e.EstimateAvailable && isnan(estimate));

scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/validation/lls_100mhz_tdlc_cp_cfo_diagnostic.yaml');
% The resolved-YAML contract must reject missing/invalid policy before the
% builder or receiver runs. Raw inheritance fragments may still be partial.
for field=["cfo_cp_observation_policy","cfo_cp_window_fraction","cfo_cp_false_alarm_probability"]
    missing=scfg.toStruct(); missing.impairments=rmfield(missing.impairments,field);
    mustRejectConfig(missing,"sixgr:lls6g:config:MissingField");
end
for boundary=[0 1]
    invalid=scfg.toStruct(); invalid.impairments.cfo_cp_false_alarm_probability=boundary;
    mustRejectConfig(invalid,"sixgr:lls6g:config:CFOCPObservationPolicy");
end
invalid=scfg.toStruct(); invalid.impairments.cfo_cp_window_fraction=0;
mustRejectConfig(invalid,"sixgr:lls6g:config:CFOCPObservationPolicy");
cfg=sixgr.lls6g.buildInternalConfig(scfg,tempdir);
assert(isequal(sixgr.phy.rx.resolveCFOCPObservation(cfg),policy));
cfg.phy.impairments.cfoCPObservation.WindowFraction=.9; caught=false;
try, sixgr.phy.rx.resolveCFOCPObservation(cfg);
catch ME, caught=strcmp(ME.identifier,'sixgr:phy:rx:CFOCPPolicyAuthorityMismatch'); end
assert(caught,'Installed receiver policy mismatch must be rejected.');
empty=sixgr.link.addCFOObservationColumns(table(),cell(0,1));
assert(height(empty)==0 && ismember('CFOCPCoherenceSquared',empty.Properties.VariableNames));
[~,measured]=sixgr.phy.rx.estimateCFOFromCyclicPrefix(received,info,fs,policy);
published=sixgr.link.addCFOObservationColumns(table((1:2)','VariableNames',{'Trial'}),{measured;struct()});
assert(published.CFOCPCoherenceSquared(1)==measured.ObservationCoherenceSquared && ...
    isnan(published.CFOCPCoherenceSquared(2)) && ...
    published.CFOCPObservationStatus(2)=="not_reported_by_receiver");
assert(testDataReceiverSynchronizationAuthority("both",policy));
fprintf('CFO_CP_WINDOW_PASS exact=%d independent_noisy=%d RMSE_Hz=[%g %g] noise_accept=%d/128\n', ...
    exactCount,size(noisyError,1),rmse,noiseAccepted);
ok=true;
end

function mustRejectConfig(cfg,identifier)
try
    sixgr.lls6g.config.validateScenarioConfig(cfg);
catch ME
    assert(string(ME.identifier)==identifier,'%s: %s',ME.identifier,ME.message);
    return;
end
error('testCFOReceivedCoherenceWindow:MissingPolicyRejection', ...
    'Missing or invalid receiver policy must not reach execution.');
end

function [wave,info,firstSlot]=makeBurst(carrier,stream)
wave=complex(zeros(0,2)); firstSlot=0;
for slot=0:2
    carrier.NSlot=slot;
    dims=[12*carrier.NSizeGrid,carrier.SymbolsPerSlot,2];
    grid=((2*randi(stream,[0 1],dims)-1)+1i*(2*randi(stream,[0 1],dims)-1))/sqrt(2);
    [part,current]=sixgr.phy.waveform.ofdmModulate(carrier,grid,'Windowing',0);
    if slot==0, firstSlot=size(part,1); end
    if slot==1, info=current; end
    wave=[wave;part]; %#ok<AGROW>
end
end
