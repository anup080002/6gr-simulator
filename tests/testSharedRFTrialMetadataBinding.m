function ok=testSharedRFTrialMetadataBinding()
% Actual bounded TX -> RX RF stream, then the production post-decode binder.
cfg=struct(); cfg.rf.rx.cfo_Hz=400; cfg.rf.rx.timingOffsetSamples=1;
cfg.rf.adc.enable=true; cfg.rf.adcBits=12; cfg.rf.adc.fullScale=1;
cfg.rf.frontend.dac=struct('enabled',true,'profile_id','rf_binding_test', ...
    'version','1','bits',12,'full_scale',1,'convention','signed_midrise', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0);
fs=122.88e6; first=100;
x=complex([.2*ones(8,2);2*ones(24,2)],.1*ones(32,2));
for direction=["DL","UL"]
    tx=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,2,first,1,false);
    rx=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx',direction,fs,2,first,1,false);
    y=zeros(size(x),'like',x); z=y; segments=cell(2,1); offset=0;
    for k=1:2
        stop=[8 32]; stop=stop(k);
        a=tx.apply(sixgr.phy.waveform.WaveformChunk(x(offset+1:stop,:),first+offset),1);
        b=rx.apply(sixgr.phy.waveform.WaveformChunk(a.Waveform,first+offset),1);
        y(offset+1:stop,:)=a.Waveform; z(offset+1:stop,:)=b.Waveform;
        e=struct('StartSample',first+offset,'EndSampleExclusive',first+stop, ...
            'TX',struct('ID',"transmitter",'Replay',a.Replay), ...
            'RX',struct('ID',"receiver",'Replay',b.Replay));
        segments{k}=struct('Execution',e); offset=stop;
    end
    planes=[localPlane(y,"transmitter:tx",first,fs,segments), ...
        localPlane(y,"receiver:pre_rf",first,fs,segments), ...
        localPlane(z,"receiver:post_rf",first,fs,segments)];
    T=table(1,false,false,NaN,NaN,'VariableNames', ...
        {'Slot','CFOApplied','TimingOffsetApplied','ADCBits','DACBits'});
    T=sixgr.truth.bindSharedRFExecutionEvidence(T,planes);
    assert(T.CFOApplied==1 && T.TimingOffsetApplied==1 && T.ADCBits==12 && T.DACBits==12);
    assert(T.ADCQuantizationExecuted==1 && T.DACQuantizationExecuted==1);
    assert(T.ADCClippingSampleCount==numel(x) && T.DACClippingSampleCount==numel(x));
    assert(T.RxRFOutputWaveformSHA256==sixgr.rf.waveformSHA256(z));
    assert(T.TxRFOutputWaveformSHA256==sixgr.rf.waveformSHA256(y));
    assert(T.RFStrictOk && contains(T.RxRFExecutionStatus,'validation_passed'));
    missing=planes;
    missing(3).Segments{2}.Execution.RX.Replay=rmfield(b.Replay,'CFOApplied');
    missingT=sixgr.truth.bindSharedRFExecutionEvidence(T,missing);
    assert(isnan(missingT.CFOApplied),'Missing execution metadata is not disabled RF.');
end
ok=true; disp('SHARED_RF_TRIAL_METADATA_BINDING_PASS');
end
function plane=localPlane(wave,id,first,fs,segments)
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(wave,1),fs,size(wave,2));
o.append(sixgr.phy.waveform.WaveformChunk(wave,first),fs);
plane=struct('ReceiverID',id,'Observation',o,'Segments',{segments});
end
