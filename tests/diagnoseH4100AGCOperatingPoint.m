function ok=diagnoseH4100AGCOperatingPoint(inputPath)
% Paired RF execution on retained real channel samples; NOT held-out evidence.
setup6GRSimToolkit('Verbose',false);
saved=load(inputPath,'cfg','carrier','ofdm','antennaCapture','frontend','margin');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
folder=fullfile(pwd,'results','lls','h4_agc_operating_point', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
target=sixgr.lls6g.buildInternalConfig(s,folder);
candidate=saved.cfg;
candidate.rf.rx.agc=target.rf.rx.agc;
candidate.rf.frontend.receiver.agc=target.rf.frontend.receiver.agc;
configs={saved.cfg,candidate}; names=["retained_baseline","declared_burst_headroom_and_causal_guard"];
first=saved.frontend.Chunk.StartSample; fs=saved.ofdm.SampleRate;
rows=struct([]); paired=cell(2,1);
for k=1:2
    cfg=configs{k}; epoch=cfg.rf.configurationEpoch;
    owner=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','DL',fs,4,first,epoch,false);
    out=owner.apply(sixgr.phy.waveform.WaveformChunk(saved.antennaCapture,first),epoch);
    if k==1
        assert(isequal(out.Waveform,saved.frontend.Waveform), ...
            'The retained baseline must replay exactly before comparing an AGC change.');
    end
    obs=sixgr.phy.waveform.WaveformObservationBuffer(first, ...
        first+size(out.Waveform,1),fs,4);
    obs.append(out.Chunk,fs);
    segment=struct('StartSample',first,'EndSampleExclusive',first+size(out.Waveform,1), ...
        'Execution',struct('RX',struct('ID',"receiver",'Replay',out.Replay)));
    [digital,compensation]=sixgr.phy.rx.compensateReceivedAGC(obs,{segment},"receiver");
    assert(~compensation.ClippingReconstructed && ~compensation.QuantizationRemoved);
    rx=sixgr.phy.refsig.receiveCSIRSWaveform(saved.carrier,cfg,digital.readComplete(), ...
        saved.antennaCapture,[0 saved.margin],struct());
    [report,detail]=sixgr.phy.refsig.computeCSIRSFeedback(saved.carrier,cfg,rx);
    a=out.Replay.ADCSampleEvidence; t=out.Replay.AGCStreamTrace;
    gainPower=10.^(t.AppliedGain_dB/10);
    inputReferredError=sum(a.ErrorEnergy./gainPower);
    inputReferredEnergy=sum(a.InputEnergy./gainPower);
    row=struct('Case',names(k),'ADCClippedSamples',sum(a.ClippedCount), ...
        'ADCSampleCount',sum(repmat(a.NumChannels,numel(a.ClippedCount),1)), ...
        'ADCClippingPercent',100*out.Replay.ADCClippingRatio, ...
        'ADCRMSConverterErrorPercent',100*sqrt(sum(a.ErrorEnergy)/sum(a.InputEnergy)), ...
        'InputReferredConverterRMSPercent',100*sqrt(inputReferredError/inputReferredEnergy), ...
        'AGCTargetRMS',t.TargetRMS,'AGCGuardTriggers',t.OverloadGuardTriggerCount, ...
        'MeasuredCSIObjective_dB',report.SINR_dB,'RI',report.RI,'CQI',report.CQI, ...
        'CFOEstimateHz',rx.ReceiverTrackingCorrection.EstimatedCFO_Hz, ...
        'PhysicalScenarioAccepted',false,'IndependentQualification',false, ...
        'Scope',"paired_actual_retained_channel_IQ_RF_design_diagnostic_not_modulation_EVM");
    if k==1, rows=row; else, rows(k)=row; end %#ok<AGROW>
    paired{k}=struct('RF',out,'RX',rx,'Report',report,'Detail',detail);
    writetable(struct2table(rows),fullfile(folder,'paired_rf_measurements.csv'));
    save(fullfile(folder,char(names(k)+"_execution.mat")),'cfg','out','rx','report','detail','row','-v7.3');
    fprintf('H4_AGC_REPLAY case=%s clipping_pct=%g converter_error_pct=%g input_referred_error_pct=%g RI=%g CQI=%g\n', ...
        names(k),rows(k).ADCClippingPercent,rows(k).ADCRMSConverterErrorPercent, ...
        rows(k).InputReferredConverterRMSPercent,report.RI,report.CQI);
end
T=struct2table(rows);
writetable(T,fullfile(folder,'paired_rf_measurements.csv'));
source=struct('InputPath',string(inputPath),'SHA256',sixgr.util.sha256File(inputPath), ...
    'SameInputUsed',true,'AdditionalChannelExecutions',0,'IndependentQualification',false);
save(fullfile(folder,'paired_rf_execution.mat'),'configs','paired','source','T','-v7.3');
assert(rows(2).ADCClippedSamples<rows(1).ADCClippedSamples && ...
    rows(2).InputReferredConverterRMSPercent<rows(1).InputReferredConverterRMSPercent, ...
    'Retain negative findings: the declared receiver design did not improve converter distortion.');
fprintf('H4_AGC_OPERATING_POINT_PASS root=%s\n',folder);
ok=true;
end
