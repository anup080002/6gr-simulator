function ok=testReceiveElementExecutionEvidence()
% Actual installed native UE array and original shared-owner RF intervals.
% Declared disconnected TX: noise-only RX, no channel/CSI/access qualification.
% The separate testCSIRSComponentIsolationEvidence exercises actual CSI.
setup6GRSimToolkit('Verbose',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempdir);
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,30);
cfg.lls6g.userContext.RuntimeUEAntenna=sixgr.rf.AntennaArrayFactory.build(cfg,'ue');
cfg.lls6g.userContext.RuntimeUEAntennaMeta=struct('Azimuth_deg',NaN, ...
    'Heading_deg',0,'Tilt_deg',0,'PositionX_m',1,'PositionY_m',2,'PositionZ_m',1.5);
assert(~isfield(cfg.rf,'uePowerReference'),'Do not invent UE RF-type authority for this component.');
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
fs=double(info.SampleRate); epoch=cfg.rf.configurationEpoch;
owner=makeOwner(cfg); binding=owner.receiveElementLayout('ue_rx');
assert(binding.Available&&~binding.Layout.ExecutionVerified&& ...
    ~binding.Layout.RFReferenceQualified&&~binding.Layout.PowerUnitQualified&& ...
    ~binding.Layout.HardwareConformanceVerified&&~owner.receiveBranchLayout('ue_rx').Available);
assert(isequal(binding.Layout.Geometry.ElementPositions_m, ...
    cfg.lls6g.userContext.RuntimeUEAntenna.ElementPositions_m));
owner.validateReceiverInstallation('ue_rx',cfg,'DL',2);
changed=cfg; changed.lls6g.userContext.RuntimeUEAntenna.ElementPositions_m(1,1)=999;
reject(@()owner.validateReceiverInstallation('ue_rx',changed,'DL',2),'RF:ReceiveBranchInstallation');
% Absence remains absence. The same physical noise/RF path without optional
% installed geometry is the independent numerical parity control.
without=cfg;
without.lls6g.userContext=rmfield(without.lls6g.userContext, ...
    {'RuntimeUEAntenna','RuntimeUEAntennaMeta'});
control=makeOwner(without);
assert(~control.receiveElementLayout('ue_rx').Available);
pre=sixgr.phy.waveform.WaveformObservationBuffer(0,32,fs,2);
segments=cell(2,1); controlSegments=cell(2,1); before=rng;
for k=1:2
    first=(k-1)*16; stop=k*16;
    input=struct('ID',"gnb",'Chunk', ...
        sixgr.phy.waveform.WaveformChunk(complex(zeros(16,4)),first));
    [outputs,execution]=owner.process(input,first,stop,[]);
    [baseline,other]=control.process(input,first,stop,[]);
    assert(isequal(string({outputs.ID}),string({baseline.ID})));
    for j=1:numel(outputs)
        assert(isequal(outputs(j).Chunk.Samples,baseline(j).Chunk.Samples)&& ...
            outputs(j).Chunk.SHA256==baseline(j).Chunk.SHA256, ...
            'Element receipt retention must not change original IQ or physical random streams.');
    end
    received=outputs(string({outputs.ID})=="ue_rx:pre_rf");
    pre.append(received.Chunk,fs);
    r=execution.RX.Replay; original=r.ReceiveElementExecution;
    assert(original.ExecutionVerified&&original.OriginalSampleOrderingPreserved&& ...
        original.RFInputSHA256==string(r.RFInputWaveformSHA256)&& ...
        original.RFOutputSHA256==string(r.RFOutputWaveformSHA256)&& ...
        original.LayoutSHA256==binding.Layout.LayoutSHA256&& ...
        original.StartSample==first&&original.EndSampleExclusive==stop&& ...
        r.NoiseStreamSeed==other.RX.Replay.NoiseStreamSeed&& ...
        string(r.RFInputWaveformSHA256)==string(other.RX.Replay.RFInputWaveformSHA256)&& ...
        isempty(fieldnames(other.RX.Replay.ReceiveElementExecution)));
    segments{k}=struct('StartSample',first,'EndSampleExclusive',stop,'Execution',execution);
    controlSegments{k}=struct('StartSample',first,'EndSampleExclusive',stop,'Execution',other);
end
replay=struct('ReceiverID',"ue_rx",'RuntimeChannelStartSample',0, ...
    'RuntimeChannelEndSample',32,'ReceiveStreamExecutionSegments',{segments});
storage=pre.storageInfo(); originalRNG=rng;
e=sixgr.rf.validateReceiveElementObservation(pre,replay,binding);
assert(e.Available&&numel(e.IntervalReceipts)==2&& ...
    e.ReferencePlane=="internal_physical_receive_element_before_RX_front_end"&& ...
    ~e.RFReferenceQualified&&~e.PowerUnitQualified&&~e.StandardizedReferencePointQualified&& ...
    ~e.HardwareConformanceVerified&&~e.AccuracyQualified&& ...
    isequal(storage,pre.storageInfo())&&isequal(originalRNG,rng)&&isequal(before,rng), ...
    'Value-only validation must not read/compact/hash IQ, change RNG or expand qualification.');
noBinding=sixgr.rf.validateReceiveElementObservation(pre,replay,control.receiveElementLayout('ue_rx'));
assert(~noBinding.Available);
% Configured geometry cannot repair historical missing original receipts.
bad=replay; bad.ReceiveStreamExecutionSegments=controlSegments;
reject(@()sixgr.rf.validateReceiveElementObservation(pre,bad,binding),'RF:ReceiveElementObservation');
for mutation=1:6
    bad=replay;
    switch mutation
        case 1, bad.ReceiverID="different_rx";
        case 2, bad.ReceiveStreamExecutionSegments{2}.StartSample=17;
        case 3, bad.ReceiveStreamExecutionSegments{1}.Execution.ConfigurationEpoch=epoch+1;
        case 4, bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.RFInputWaveformSHA256="changed";
        case 5
            receipt=bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.ReceiveElementExecution;
            receipt.RFReferenceQualified=true; receipt=reseal(receipt);
            bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.ReceiveElementExecution=receipt;
        case 6
            receipt=bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.ReceiveElementExecution;
            receipt.EndSampleExclusive=15; receipt=reseal(receipt);
            bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.ReceiveElementExecution=receipt;
    end
    reject(@()sixgr.rf.validateReceiveElementObservation(pre,bad,binding),'RF:ReceiveElementObservation');
end
bad=binding; bad.Layout.PhysicalElementIndexByInputColumn0=[1 0];
reject(@()sixgr.rf.validateReceiveElementObservation(pre,replay,bad),'RF:ReceiveElementObservation');
% The no-rehash execution binder is restricted to the actual physical owner.
definition=?sixgr.rf.ReceiveElementLayout;
method=definition.MethodList(string({definition.MethodList.Name})=="bindOriginalOwnerExecution");
assert(isscalar(method)); access=method.Access;
if iscell(access), assert(isscalar(access)); access=access{1}; end
assert(isa(access,'meta.class')&&string(access.Name)=="sixgr.truth.SharedWaveformPhysicalRuntime");
fprintf('RECEIVE_ELEMENT_EXECUTION_PASS original_RF_intervals=2 branches=2 channel_execution=0 RF_reference=0 hardware=0\n');
ok=true;

    function result=makeOwner(configuration)
        result=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
        result.addTransmitter('gnb',configuration,'DL',4,false);
        result.addReceiver('ue_rx',configuration,'DL',2,false);
    end
end

function value=reseal(value)
value=rmfield(value,'ReceiptSHA256');
value.ReceiptSHA256=string(sixgr.util.sha256Hex(unicode2native(jsonencode(value),'UTF-8')));
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingReceiveElementRejection','Expected %s.',id);
end
