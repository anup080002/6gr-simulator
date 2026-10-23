function ok=testReceiveBranchLayout()
% Actual native installed array + actual retained RF execution on declared
% samples. No propagation/SRS reception, standardized branch or hardware claim.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempdir);
a=sixgr.rf.AntennaArrayFactory.build(cfg,'bs');
assert(a.NumElements==64&&cfg.antenna.bs.numRxRFChains==64);
% Declared endpoint placement is separate from the real native array object.
cfg.lls6g.userContext.RuntimeServingBSAntenna=a;
cfg.lls6g.userContext.RuntimeServingBSAntennaMeta=struct('Azimuth_deg',0, ...
    'Heading_deg',NaN,'Tilt_deg',0,'PositionX_m',0,'PositionY_m',0,'PositionZ_m',25);
carrier=sixgr.phy.grid.makeCarrier(cfg); native=nrOFDMInfo(carrier);
fs=double(native.SampleRate); epoch=double(cfg.rf.configurationEpoch); endpoint="gnb_1_rx";
layout=sixgr.rf.ReceiveBranchLayout.freeze(cfg,endpoint,'UL',64,fs,epoch);
assert(~layout.ExecutionVerified&&~layout.StandardizedReferencePointQualified&& ...
    ~layout.HardwareConformanceVerified&&layout.RFReference.RFType=="1-O"&& ...
    isequal(layout.PhysicalElementIndexByRFInput0,0:63)&& ...
    isequal(layout.Geometry.ElementPositions_m,double(getElementPosition(a.ArrayObj).')));
again=sixgr.rf.ReceiveBranchLayout.freeze(orderfields(cfg),endpoint,'UL',64,fs,epoch);
assert(isequaln(layout,again),'Canonical freeze must not depend on input struct field order.');
% TX/logical mappings and current rank are not receive branch authority.
inactive=cfg; inactive.phy.pusch.NumLayers=2;
inactive.lls6g.userContext.RuntimeServingBSAntenna.PortToElementMatrix=complex(NaN(64,3));
inactive.lls6g.userContext.RuntimeServingBSAntenna.ElementToPortMatrix=complex(NaN(3,64));
same=sixgr.rf.ReceiveBranchLayout.freeze(inactive,endpoint,'UL',64,fs,epoch);
assert(isequaln(layout,same));
before=rng;
stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',fs,64,0,epoch,false);
x=complex(reshape(1:2048,32,64)*1e-7,reshape(2048:-1:1,32,64)*2e-7);
chunk=sixgr.phy.waveform.WaveformChunk(x,0);
actual=stream.apply(chunk,epoch);
receipt=sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,actual,stream,endpoint);
assert(receipt.ExecutionVerified&&receipt.OriginalSampleOrderingPreserved&& ...
    receipt.LayoutSHA256==layout.LayoutSHA256&&receipt.StartSample==0&& ...
    receipt.EndSampleExclusive==32&&receipt.NonzeroElementSampleCount==numel(x)&& ...
    ~receipt.StandardizedReferencePointQualified&&~receipt.HardwareConformanceVerified);
assert(receipt.RFInputSHA256==string(actual.Replay.RFInputWaveformSHA256)&& ...
    receipt.RFOutputSHA256==string(actual.Replay.RFOutputWaveformSHA256));
assert(isequal(rng,before),'Retained RF execution must not disturb global RNG.');
bad=cfg; bad.antenna.bs.numRxRFChains=32;
reject(@()sixgr.rf.ReceiveBranchLayout.freeze(bad,endpoint,'UL',64,fs,epoch), ...
    'RF:ReceiveBranchIdentityUnsupported');
bad=cfg; bad.lls6g.userContext.RuntimeServingBSAntenna.ElementPositions_m(1,1)=123;
reject(@()sixgr.rf.ReceiveBranchLayout.freeze(bad,endpoint,'UL',64,fs,epoch), ...
    'RF:ReceiveBranchInstallation');
bad=cfg; bad.lls6g.userContext.RuntimeServingBSAntenna.Fc_Hz=a.Fc_Hz+1;
reject(@()sixgr.rf.ReceiveBranchLayout.freeze(bad,endpoint,'UL',64,fs,epoch), ...
    'RF:ReceiveBranchInstallation');
bad=cfg; bad.rf=rmfield(bad.rf,'bsPowerReference');
reject(@()sixgr.rf.ReceiveBranchLayout.freeze(bad,endpoint,'UL',64,fs,epoch), ...
    'RF:ReceiveBranchInstallation');
bad=layout; bad.PhysicalElementIndexByRFInput0([1 2])=[1 0];
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(bad,chunk,chunk,actual,stream,endpoint), ...
    'RF:ReceiveBranchLayoutDigest');
other=sixgr.rf.ReceiveBranchLayout.freeze(cfg,endpoint,'UL',64,fs,epoch+1);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(other,chunk,chunk,actual,stream,endpoint), ...
    'RF:ReceiveBranchOwnerMismatch');
other=sixgr.rf.ReceiveBranchLayout.freeze(cfg,endpoint,'UL',64,fs*2,epoch);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(other,chunk,chunk,actual,stream,endpoint), ...
    'RF:ReceiveBranchOwnerMismatch');
bad=cfg; bad.lls6g.userContext.RuntimeServingBSAntennaMeta.Azimuth_deg=1;
other=sixgr.rf.ReceiveBranchLayout.freeze(bad,endpoint,'UL',64,fs,epoch);
assert(other.LayoutSHA256~=layout.LayoutSHA256);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(other,chunk,chunk,actual,stream,endpoint), ...
    'RF:ReceiveBranchOwnerMismatch');
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,actual,stream,"gnb_2_rx"), ...
    'RF:ReceiveBranchOwnerMismatch');
permuted=sixgr.phy.waveform.WaveformChunk(x(:,[2 1 3:64]),0);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,permuted,actual,stream,endpoint), ...
    'RF:ReceiveBranchIdentityNotExecuted');
changed=sixgr.phy.waveform.WaveformChunk(x*2,0);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,changed,actual,stream,endpoint), ...
    'RF:ReceiveBranchIdentityNotExecuted');
bad=actual; bad.ExecutionStage="configured_not_executed";
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,bad,stream,endpoint), ...
    'RF:ReceiveBranchExecution');
bad=actual; bad.Replay.RFInputWaveformSHA256=repmat('0',1,64);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,bad,stream,endpoint), ...
    'RF:ReceiveBranchExecution');
bad=actual; bad.Replay.RFStreamEndSampleExclusive=33;
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,bad,stream,endpoint), ...
    'RF:ReceiveBranchExecution');
fresh=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',fs,64,0,epoch,false);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,actual,fresh,endpoint), ...
    'RF:ReceiveBranchExecution');
% Actual silence is an executed interval, not missing geometry or no receipt.
silent=sixgr.phy.waveform.WaveformChunk(complex(zeros(16,64)),32);
next=stream.apply(silent,epoch);
zero=sixgr.rf.ReceiveBranchLayout.bindExecution(layout,silent,silent,next,stream,endpoint);
assert(zero.ExecutionVerified&&zero.NonzeroElementSampleCount==0&&zero.LayoutSHA256==layout.LayoutSHA256);
reject(@()sixgr.rf.ReceiveBranchLayout.bindExecution(layout,chunk,chunk,actual,stream,endpoint), ...
    'RF:ReceiveBranchExecution');
assert(isequal(rng,before));
fprintf('RECEIVE_BRANCH_LAYOUT_PASS branches=64 actual_RF_intervals=2 shared_runtime_integration=0 standardized_qualification=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s got %s',id,cause.identifier); return; end
error('test:ReceiveBranchExpectedError','Expected %s.',id);
end
