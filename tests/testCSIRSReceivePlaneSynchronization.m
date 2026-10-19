function ok=testCSIRSReceivePlaneSynchronization()
% Actual 100 MHz OFDM + retained RF operators. No injected offset is given
% to the receiver. Downstream RX RF must not alter antenna-plane scoring.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30,'NCellID',17,'NSlot',1);
cfg.run.strictMode=true; cfg.channel.model='AWGN';
cfg.phy.csirs=struct('enable',true,'period_slots',5,'offset_slots',1, ...
    'numResources',1,'nPorts',4,'density','one','resourceIDs',11, ...
    'rowNumbers',4,'symbolLocationsByResource',3, ...
    'subcarrierLocationsByResource',0,'rbOffsetsByResource',0, ...
    'numRBsByResource',273,'runtimeChannelEstimator','nr_channel_estimate');
cfg.phy.mimo=struct('strict',true,'measurementMaxAgeSlots',8);
cfg.phy.csi.reportConfiguration=struct('Ports',4);
cfg.phy.rx.cfoCorrectionEnabled=true;
cfg.phy.impairments.cfoEstimationMethod='cyclic_prefix';
cfg.lls6g.userContext=struct('RuntimeUEIndex',1,'RuntimeCurrentSlot',2);
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP','configured_snr_is_link_authority',true);
[indices,symbols]=sixgr.phy.refsig.csirs(carrier,cfg);
grid=nrResourceGrid(carrier,4); grid(indices)=symbols;
[waveform,info]=nrOFDMModulate(carrier,grid,'Windowing',0);
[waveform,cfg.lls6g.runtimePowerContext]=sixgr.rf.applyPowerContext( ...
    waveform,cfg,'DL',struct('OFDMInfo',info),'ApplyPA',false);
waveform=[waveform;zeros(64,4)];
txRF.rf.tx.cfo_Hz=700; txRF.rf.tx.timingOffsetSamples=13;
tx=sixgr.rf.runtime.RFImpairmentStream(txRF,'tx','DL',info.SampleRate,4,0,1,false);
antenna=tx.apply(sixgr.phy.waveform.WaveformChunk(waveform,0),1);
baseline=sixgr.phy.refsig.receiveCSIRSWaveform( ...
    carrier,cfg,antenna.Waveform,antenna.Waveform,[0 64],struct());
assert(baseline.ReceiveTiming.TimingOffsetSamples==13);
assert(abs(baseline.ReceiverTrackingCorrection.EstimatedCFO_Hz-700)<1e-6);
fields=["MeasurementRSRP_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSSI_dB_re_UnitOccupiedRE_Es","MeasurementRSRQ_dB"];
cases=[400 0;0 7;400 7;9000 7];
for k=1:size(cases,1)
    hz=cases(k,1); delay=cases(k,2);
    rxRF.rf.rx.cfo_Hz=hz; rxRF.rf.rx.timingOffsetSamples=delay;
    owner=sixgr.rf.runtime.RFImpairmentStream(rxRF,'rx','DL',info.SampleRate,4,0,1,false);
    impaired=owner.apply(sixgr.phy.waveform.WaveformChunk(antenna.Waveform,0),1);
    received=sixgr.phy.refsig.receiveCSIRSWaveform( ...
        carrier,cfg,impaired.Waveform,antenna.Waveform,[0 64],struct());
    assert(received.ReceiveTiming.TimingOffsetSamples==13+delay);
    assert(abs(received.ReceiverTrackingCorrection.EstimatedCFO_Hz-(700+hz))<1e-6);
    assert(received.PhysicalMeasurementReceiveTiming.TimingOffsetSamples==13 && ...
        abs(received.PhysicalMeasurementTrackingCorrection.EstimatedCFO_Hz-700)<1e-6);
    for field=fields
        a=baseline.CSIRSObservation.(field); b=received.CSIRSObservation.(field);
        fprintf('CSI_PLANE_CHECK RX_CFO=%g RX_delay=%g field=%s baseline=%.12g impaired=%.12g delta=%.12g\n',hz,delay,field,a,b,b-a);
        assert(isfinite(a) && isfinite(b) && abs(a-b)<1e-10, ...
            'test:CSIPhysicalPlaneContaminatedByReceiverRF', ...
            'Unchanged antenna samples changed %s after downstream RX RF: %.12g dB.',field,b-a);
    end
    % A changed scoring capture must not affect practical channel state.
    changedReference=sixgr.phy.refsig.receiveCSIRSWaveform( ...
        carrier,cfg,impaired.Waveform,.5*antenna.Waveform,[0 64],struct());
    assert(isequaln(received.CSIMeasurementState,changedReference.CSIMeasurementState) && ...
        isequaln(received.CSIChannelEstimateForPMI,changedReference.CSIChannelEstimateForPMI) && ...
        isequaln(received.RxGrid,changedReference.RxGrid), ...
        'test:CSIPhysicalPlaneUsedForFeedback','Scoring capture changed practical CSI state.');
    delta=changedReference.CSIRSObservation.(fields(1))-received.CSIRSObservation.(fields(1));
    assert(abs(delta-20*log10(.5))<1e-9,'Actual pre-front-end amplitude must change its own power measurement.');
end
% With compensation disabled, RF still changes the practical receiver.
% Keeping the pre-plane fixed must not conceal downstream impairment.
disabled=cfg; disabled.phy.rx.cfoCorrectionEnabled=false;
off=sixgr.phy.refsig.receiveCSIRSWaveform( ...
    carrier,disabled,impaired.Waveform,antenna.Waveform,[0 64],struct());
assert(~off.ReceiverTrackingCorrection.CFOCorrectionApplied && ...
    ~off.PhysicalMeasurementTrackingCorrection.CFOCorrectionApplied && ...
    norm(off.RxGrid(:)-received.RxGrid(:))>1, ...
    'test:CSICompensationPolicyIgnored','Actual impairment must remain when correction is disabled.');
% Deliberately false injected metadata cannot influence either estimator.
poison=sixgr.phy.refsig.receiveCSIRSWaveform(carrier,cfg, ...
    impaired.Waveform,antenna.Waveform,[0 64], ...
    struct('InjectedCFO_Hz',1e8,'InjectedTimingOffset_samples',999));
assert(isequaln(poison.CSIMeasurementState,received.CSIMeasurementState) && ...
    isequaln(poison.PhysicalMeasurementReceiveTiming,received.PhysicalMeasurementReceiveTiming) && ...
    isequaln(poison.PhysicalMeasurementTrackingCorrection,received.PhysicalMeasurementTrackingCorrection));
fprintf('CSI_RECEIVE_PLANE_SYNCHRONIZATION_PASS PRB=273 ports=4 RX=4\n');
ok=true;
end
