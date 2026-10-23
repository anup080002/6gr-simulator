function ok=testSharedAGCConverterMeasurement()
% Real short RF streams; no scenario, data decoder or RF-conformance claim.
cfg=struct(); cfg.rf.rx.agc=struct('enable',true,'targetRms',.5, ...
    'minGain_dB',-60,'maxGain_dB',40);
cfg.rf.frontend.receiver.agc.stream_profile=struct( ...
    'control_model',"causal_windowed_joint_rms_attack_hold_release", ...
    'attack',1,'release',.5,'hold_samples',8,'update_period_samples',8);
cfg.rf.adc=struct('enable',true,'fullScale',1); cfg.rf.adcBits=12;
first=100; fs=122.88e6;
amplitude=[.001*ones(16,1);.1*ones(24,1);2*ones(56,1)];
x=amplitude.*[1+.3i,.2-.1i];
for direction=["DL","UL"]
    tx=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,2,first,1,false);
    rx=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx',direction,fs,2,first,1,false);
    y=zeros(size(x),'like',x); gains=zeros(size(x,1),1); segments=cell(3,1); offset=0;
    for k=1:3
        stop=[7 31 96]; stop=stop(k);
        a=tx.apply(sixgr.phy.waveform.WaveformChunk(x(offset+1:stop,:),first+offset),1);
        b=rx.apply(sixgr.phy.waveform.WaveformChunk(a.Waveform,first+offset),1);
        assert(a.Row.Endpoint=="tx" && a.Row.TxOrRxSide=="tx_output" && ...
            b.Row.Endpoint=="rx" && b.Row.TxOrRxSide=="rx_output", ...
            'RF evidence must identify its executed endpoint instead of inheriting rx_input for TX.');
        assert(isequal(a.Waveform,x(offset+1:stop,:)));
        y(offset+1:stop,:)=b.Waveform;
        gains(offset+1:stop)=b.Replay.AGCStreamTrace.AppliedGain_dB;
        e=struct('StartSample',first+offset,'EndSampleExclusive',first+stop, ...
            'TX',struct('ID',"transmitter",'Replay',a.Replay), ...
            'RX',struct('ID',"receiver",'Replay',b.Replay));
        segments{k}=struct('Execution',e); offset=stop;
    end
    planes=[localPlane(x,"transmitter:tx",first,fs,segments), ...
        localPlane(x,"receiver:pre_rf",first,fs,segments), ...
        localPlane(y,"receiver:post_rf",first,fs,segments)];
    T=sixgr.truth.bindSharedRFExecutionEvidence(table(1,'VariableNames',{'Slot'}),planes);
    compact=sixgr.truth.bindSharedRFExecutionEvidence(table(1,'VariableNames',{'Slot'}),planes,true);
    for field=["TxRFConfiguredStageCount","TxRFExecutedStageCount","TxRFAppliedStageCount", ...
            "RxRFConfiguredStageCount","RxRFExecutedStageCount","RxRFAppliedStageCount"]
        assert(isequaln(T.(field),compact.(field)),'Metadata-only publication lost actual RF counts.');
    end
    audit=jsondecode(compact.RxRFEndpointMetadataAuditJSON);
    assert(isfield(audit,'SampleRateHz') && audit.SampleRateHz==fs, ...
        'test:RFEndpointClockMissing','The actual endpoint audit must bind its sample rate.');
    assert(audit.Contract=="shared_rf_endpoint_observation/v2" && ...
        audit.PhysicalPortCount==size(x,2) && ...
        audit.ClockDomain=="shared_physical_absolute_sample_clock_zero_based");
    assert(numel(audit.StageCountIntervals)==3);
    assert(audit.StageCountIntervals(1).StartSample==first);
    assert(audit.StageCountIntervals(end).EndSampleExclusive==first+size(x,1));
    assert(all([audit.StageCountIntervals.ConfigurationEpoch]==1));
    localCheckIntervalPublication(compact,cfg,fs,first,size(x,1));
    assert(isequaln(T.PeakClippingEvents,T.DACClippedSampleCount) && ...
        T.PeakClippingEventsSource=="actual_TX_DAC_clipped_complex_samples" && ...
        T.PeakClippingEventsStatus==T.DACClippingStatus);
    actualInput=x.*10.^(gains/20); difference=y-actualInput;
    assert(T.AGCExecuted==1 && T.AGCDecisionCausal==1 && T.AGCGainIsTimeVarying==1);
    assert(isnan(T.AGCGain_dB) && T.AGCGainMin_dB==min(gains) && T.AGCGainMax_dB==max(gains));
    assert(T.AGCGainSampleCount==size(x,1) && T.AGCExecutionStatus=="executed_time_varying_sample_gain");
    assert(T.ADCErrorSampleCount==numel(x) && ...
        abs(T.ADCInputEnergy-sum(abs(actualInput(:)).^2))<1e-10 && ...
        abs(T.ADCErrorEnergy-sum(abs(difference(:)).^2))<1e-10 && ...
        abs(T.ADCErrorMeanSquare-mean(abs(difference(:)).^2))<1e-12);
    assert(T.ADCClippingRatio>0 && T.ADCErrorEnergy>0, ...
        'Preserve actual clipping and distortion; gain compensation does not remove them.');
    assert(contains(T.ADCErrorDomain,"not_post_equalization_EVM") && ...
        contains(T.ADCErrorDefinition,"including_clipping"));
    assert(T.DACErrorMeasurementStatus=="not_executed" && isnan(T.DACErrorMeanSquare));
    % The final gain decision is for future samples, not this capture.
    poisoned=planes(3);
    poisoned.Segments{3}.Execution.RX.Replay.AGCStreamTrace.Gain_dB=999;
    same=sixgr.truth.summarizeSharedRFEndpoint(poisoned,"RX");
    assert(same.AGCGainMax_dB==max(gains) && same.ADCErrorEnergy==T.ADCErrorEnergy);
    cropped=localPlane(y(2:end-1,:),"receiver:post_rf",first+1,fs,segments);
    partial=sixgr.truth.summarizeSharedRFEndpoint(cropped,"RX");
    assert(partial.AGCGainSampleCount==size(x,1)-2 && ...
        partial.AGCGainMin_dB==min(gains(2:end-1)) && partial.AGCGainMax_dB==max(gains(2:end-1)));
    cropInput=actualInput(2:end-1,:); cropError=difference(2:end-1,:);
    cropClipped=abs(real(cropInput))>=1 | abs(imag(cropInput))>=1;
    assert(partial.ADCErrorSampleCount==numel(cropInput) && ...
        abs(partial.ADCInputEnergy-sum(abs(cropInput(:)).^2))<1e-10 && ...
        abs(partial.ADCErrorEnergy-sum(abs(cropError(:)).^2))<1e-10 && ...
        partial.ADCClippedSampleCount==nnz(cropClipped) && ...
        partial.ADCClippingRatio==mean(double(cropClipped(:))) && ...
        partial.ADCErrorMeasurementStatus=="measured_actual_converter_samples_cropped_to_capture");
    % Backward compatibility must not manufacture missing sample evidence.
    old=cropped; old.Segments{2}.Execution.RX.Replay= ...
        rmfield(old.Segments{2}.Execution.RX.Replay,'ADCSampleEvidence');
    unknown=sixgr.truth.summarizeSharedRFEndpoint(old,"RX");
    assert(isnan(unknown.ADCErrorMeanSquare) && isnan(unknown.ADCClippingRatio));
    bad=cropped; bad.Segments{2}.Execution.RX.Replay.ADCSampleEvidence.StartSample=0;
    localReject(@()sixgr.truth.summarizeSharedRFEndpoint(bad,"RX"),'sixgr:truth:InvalidRFConverterSampleTrace');
    bad=cropped; bad.Segments{2}.Execution.RX.Replay.ADCSampleEvidence.ErrorEnergy(1)=999;
    localReject(@()sixgr.truth.summarizeSharedRFEndpoint(bad,"RX"),'sixgr:truth:InvalidRFConverterSampleTrace');
    absent=planes(3); absent.Segments{2}.Execution.RX.Replay= ...
        rmfield(absent.Segments{2}.Execution.RX.Replay,'AGCStreamTrace');
    unknown=sixgr.truth.summarizeSharedRFEndpoint(absent,"RX");
    assert(isnan(unknown.AGCGain_dB) && isnan(unknown.AGCGainMax_dB));
    bad=planes(3); bad.Segments{2}.Execution.RX.Replay.AGCStreamTrace.AppliedGain_dB=4;
    localReject(@()sixgr.truth.summarizeSharedRFEndpoint(bad,"RX"),'sixgr:truth:InvalidRFAGCTrace');
    bad=planes(3); bad.Segments{2}.Execution.RX.Replay.ADCErrorSampleCount=1;
    localReject(@()sixgr.truth.summarizeSharedRFEndpoint(bad,"RX"),'sixgr:truth:InvalidRFConverterErrorPopulation');
    fprintf('SHARED_AGC_ADC_MEASUREMENT direction=%s clipped=%g mse=%g gain_min=%g gain_max=%g\n', ...
        direction,T.ADCClippingRatio,T.ADCErrorMeanSquare,T.AGCGainMin_dB,T.AGCGainMax_dB);
end
% Independent quantizer arithmetic checks the TX/DAC cropped plane too.
dacCfg=struct(); dacCfg.rf.frontend.dac=struct('enabled',true, ...
    'profile_id','cropped_sample_evidence','version','1','bits',12, ...
    'full_scale',1,'convention','signed_midtread','dither_enabled',false, ...
    'dither_rms',0,'aperture_jitter_seconds',0);
for direction=["DL","UL"]
    tx=sixgr.rf.runtime.RFImpairmentStream(dacCfg,'tx',direction,fs,2,first,1,false);
    segments=cell(3,1); offset=0; y=zeros(size(x),'like',x);
    for k=1:3
        ends=[7 31 96]; stop=ends(k);
        r=tx.apply(sixgr.phy.waveform.WaveformChunk(x(offset+1:stop,:),first+offset),1);
        y(offset+1:stop,:)=r.Waveform;
        segments{k}=struct('Execution',struct('StartSample',first+offset, ...
            'EndSampleExclusive',first+stop,'TX',struct('ID',"transmitter",'Replay',r.Replay)));
        offset=stop;
    end
    step=1/(2^11-1);
    expected=complex(round(min(max(real(x),-1),1)/step), ...
        round(min(max(imag(x),-1),1)/step))*step;
    assert(isequal(y,expected),'Recording sample evidence must not change the converter output.');
    crop=2:93; sample=x(crop,:); err=expected(crop,:)-sample;
    mask=abs(real(sample))>=1 | abs(imag(sample))>=1;
    out=sixgr.truth.summarizeSharedRFEndpoint( ...
        localPlane(y(crop,:),"transmitter:tx",first+1,fs,segments),"TX");
    assert(out.DACClippingSampleCount==numel(sample) && ...
        out.DACClippedSampleCount==nnz(mask) && ...
        abs(out.DACInputEnergy-sum(abs(sample(:)).^2))<1e-10 && ...
        abs(out.DACErrorEnergy-sum(abs(err(:)).^2))<1e-10 && ...
        out.DACErrorMeasurementStatus=="measured_actual_converter_samples_cropped_to_capture");
end
ok=true; fprintf('SHARED_AGC_CONVERTER_MEASUREMENT_PASS actual_sample_energy=1 variable_gain=1 cropped_scope=1 negative_guards=1\n');
end
function plane=localPlane(wave,id,first,fs,segments)
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(wave,1),fs,size(wave,2));
o.append(sixgr.phy.waveform.WaveformChunk(wave,first),fs);
plane=struct('ReceiverID',id,'Observation',o,'Segments',{segments});
end
function localReject(action,identifier)
try, action(); catch cause, assert(string(cause.identifier)==identifier,cause.message); return; end
error('test:MissingGuard','Expected %s.',identifier);
end

function localCheckIntervalPublication(T,cfg,fs,first,count)
% Several physical-channel reports observe the SAME actually executed RF
% stream above. They must not multiply its time coverage. This is not a
% circuit-energy test or a claim that an RF observation implies TX activity.
T.SweepPointIndex=1;
raw=struct('DL',T,'PDCCH',T,'CSIRS',T,'TRS',T);
[O,U,C]=sixgr.truth.collectRFEndpointObservationIntervals(raw);
assert(height(O)==24 && height(U)==2 && height(C)==8 && all(C.Status=="BOUND"));
assert(all(U.StartSample==first & U.EndSampleExclusive==first+count) && ...
    all(U.Duration_s==count/fs) && all(U.SourceObservationCount==4));
assert(all(contains(U.SourceTablesJSON,'CSIRS') & contains(U.SourceTablesJSON,'TRS')));
assert(all(contains(U.IntervalMeaning,'not_radio_power_state_or_sleep')));
% Access/SI attribution can reference the same real RF capture. It must
% participate in provenance without multiplying endpoint execution time.
raw.CommonEnergyObservations=T;
[commonO,commonU,commonC]=sixgr.truth.collectRFEndpointObservationIntervals(raw);
assert(height(commonO)==30 && height(commonU)==2 && height(commonC)==10 && ...
    all(commonU.Duration_s==count/fs) && all(commonU.SourceObservationCount==5));
raw=rmfield(raw,'CommonEnergyObservations');
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
export=sixgr.truth.exportLLSEnergyDiagnostics(cfg,fullfile(root,'air_interface'),raw);
assert(isequaln(export.RFIntervalUnionTable,U) && isfile(export.RFIntervalUnionCSV));
persisted=sixgr.util.csvReadTable(export.RFIntervalUnionCSV);
assert(height(persisted)==2 && all(abs(persisted.Duration_s-count/fs)<1e-18));
% The integrated run has one execution but optional aliases vary by export
% schema. Empty/legacy display aliases must not multiply actual RF coverage.
scoped=T; scoped.ExecutionID="physical-execution-1";
scoped.ConfigHash="immutable-config-1"; scoped.RunID="same-run"; scoped.RunUUID="";
alias=scoped; alias.RunUUID="not_applicable_for_active_trs_runtime";
noAlias=removevars(scoped,{'RunID','RunUUID'});
[scopedObservations,united]=sixgr.truth.collectRFEndpointObservationIntervals( ...
    struct('PBCH',scoped,'CSIRS',noAlias,'TRS',alias));
assert(height(united)==2 && all(united.Duration_s==count/fs) && ...
    all(united.SourceObservationCount==3) && ...
    all(~contains(united.ScopeJSON,'not_applicable')));
for endpoint=["TX","RX"]
    field="TxRFEndpointMetadataAuditJSON";
    if endpoint=="RX", field="RxRFEndpointMetadataAuditJSON"; end
    expected=string(sixgr.util.sha256Hex(uint8(unicode2native(char(scoped.(field)),'UTF-8'))));
    selected=scopedObservations(scopedObservations.Endpoint==endpoint,:);
    assert(~isempty(selected) && all(selected.SourceAuditSHA256==expected), ...
        'RF source checksum must hash the retained audit JSON, not the execution config hash.');
end
scopedExport=sixgr.truth.exportLLSEnergyDiagnostics(cfg,fullfile(root,'scoped','air_interface'), ...
    struct('PBCH',scoped,'CSIRS',noAlias,'TRS',alias));
persisted=sixgr.util.csvReadTable(scopedExport.RFObservationCSV);
assert(isequal(string(persisted.SourceAuditSHA256),scopedObservations.SourceAuditSHA256), ...
    'Persisted RF observation checksums must retain original JSON identity.');
separateExecution=scoped; separateExecution.ExecutionID="physical-execution-2";
[~,separateRuns]=sixgr.truth.collectRFEndpointObservationIntervals( ...
    struct('PBCH',scoped,'TRS',separateExecution));
assert(height(separateRuns)==4,'Independent execution clocks must never merge.');
badScope=scoped; badScope.ExecutionID="not_applicable_for_active_trs_runtime";
localReject(@()sixgr.truth.collectRFEndpointObservationIntervals(struct('TRS',badScope)), ...
    'sixgr:truth:MissingRFIntervalScope');
badScope=scoped; badScope.ConfigHash="different-config";
localReject(@()sixgr.truth.collectRFEndpointObservationIntervals( ...
    struct('PBCH',scoped,'TRS',badScope)), ...
    'sixgr:truth:RFIntervalExecutionConfigMismatch');
% Independent points reuse the physical sample axis but must not merge.
other=T; other.SweepPointIndex=2; raw.DL=[T;other];
[~,separate]=sixgr.truth.collectRFEndpointObservationIntervals(raw);
assert(height(separate)==4 && abs(sum(separate.Duration_s)-4*count/fs)<1e-18);
% Conflicting sample rates or physical dimensions within one endpoint/epoch
% cannot be silently united. Gaps inside a completed observation reject.
bad=T; a=jsondecode(bad.RxRFEndpointMetadataAuditJSON);
a.SampleRateHz=2*fs; bad.RxRFEndpointMetadataAuditJSON=string(jsonencode(a));
localReject(@()sixgr.truth.collectRFEndpointObservationIntervals( ...
    struct('DL',T,'CSIRS',bad)),'sixgr:truth:RFIntervalClockOrPortMismatch');
a.SampleRateHz=fs; a.PhysicalPortCount=3;
bad.RxRFEndpointMetadataAuditJSON=string(jsonencode(a));
localReject(@()sixgr.truth.collectRFEndpointObservationIntervals( ...
    struct('DL',T,'TRS',bad)),'sixgr:truth:RFIntervalClockOrPortMismatch');
a.PhysicalPortCount=2; a.StageCountIntervals(2).StartSample=first+8;
bad.RxRFEndpointMetadataAuditJSON=string(jsonencode(a));
localReject(@()sixgr.truth.collectRFEndpointObservationIntervals( ...
    struct('TRS',bad)),'sixgr:truth:RFIntervalCoverageMismatch');
% A retained old audit is not upgraded from configured Fs or nominal Slot.
old=T;
for field=["TxRFEndpointMetadataAuditJSON","RxRFEndpointMetadataAuditJSON"]
    a=jsondecode(old.(field)); a=rmfield(a,{'Contract','SampleRateHz'});
    old.(field)=string(jsonencode(a));
end
[O,U,C]=sixgr.truth.collectRFEndpointObservationIntervals(struct('CSIRS',old));
assert(isempty(O)&&isempty(U)&&all(C.Status=="LEGACY"));
end
