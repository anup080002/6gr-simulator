function ok=testSLSFinitePredictorBinding(options)
% Runtime plumbing uses deliberately labeled numerical calibration only.
arguments
    options.Deferred (1,1) logical=false
end
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run=struct('seed',113,'executionID','finite_predictor_binding_fixture');
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=23;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.spatialProviderClass='sixgr.system.abstraction.NetworkSpatialGrantProvider';
cfg.system.linkAbstraction.allowDevelopmentFixtures=true;
cfg.system.linkAbstraction.networkSpatial.sinrPredictorModel='finite_committed_shared_data';
g=struct('RNTI',4660,'UEIndex',1,'PRBSet',0,'SymbolAllocation',[6 4],'NumLayers',1, ...
    'Modulation','QPSK','TBSBits',24,'MCSIndex',0,'MCSTable','qam64', ...
    'HARQ',struct('HarqID',0,'RV',0), ...
    'PHYGrant',struct('PrecodingState',struct('MatrixPorts',[1;1i]/sqrt(2))));
ctx=struct('TTI',1,'Direction',"DL",'Grant',g,'ServingCellID',1, ...
    'TransportBlockIdentity',"finite_predictor_fixture_tb",'IsRetransmission',false, ...
    'TBSBits',24,'NumLayers',1,'TargetCodeRate',.12,'SCS_kHz',30,'ChannelModel',"TDL-A");
if options.Deferred
    g.SymbolAllocation=[11 3]; ctx.Grant=g;
end
slot=struct('TTI',1,'GrantsDL',g,'GrantsUL',struct([]),'GrantCellsDL',1, ...
    'GrantCellsUL',[],'LargeScaleState',struct('Pathloss_dB',100,'TxPower_dBm',30));
p=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg); p.commitSlotPopulation(slot);
following=slot; following.TTI=2; following.GrantsDL=struct([]); following.GrantCellsDL=[];
if options.Deferred, p.commitSlotPopulation(following); end
o=p.evaluate(ctx,slot);
assert(o.ResidualISIICIIncluded && o.SINRPredictorModel=="finite_committed_shared_data");
key=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,o);
diagonal=cfg; diagonal.system.linkAbstraction.networkSpatial.sinrPredictorModel='diagonal_nominal_fft';
old=sixgr.system.abstraction.NetworkSpatialGrantProvider(diagonal);
oldObservation=old.evaluate(ctx,slot);
oldKey=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,oldObservation);
assert(key.ReceiverProfileID~=oldKey.ReceiverProfileID && ~isequaln(key,oldKey));
curve=struct('CurveID',"numerical_fixture_only",'Key',key,'RVSequence',0, ...
    'SINRAxes_dB',{{[-100;100]}},'BetaLinear',1,'TrialCount',[2000;2000], ...
    'ErrorCount',[2000;2000],'ValidationTrialCount',[2000;2000], ...
    'ValidationErrorCount',[2000;2000]);
calibration=struct('Schema',"sixgr.calibrated_sls_link/v1", ...
    'CalibrationID',"finite_binding_numerical_fixture_not_measurements", ...
    'SourceClassification',"development_fixture_not_physical_calibration",'Curves',curve);
folder=tempname; mkdir(folder);
cfg=saveFixture(cfg,calibration,fullfile(folder,'finite_fixture.mat'));
params=struct('SpatialGrantProvider',p);
if options.Deferred
    p=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    params.SpatialGrantProvider=p;
end
phy=sixgr.system.PhyFactory.create(cfg,params,'Seed',99); phy.setSlotContext(slot);
if options.Deferred
    % The real runner adds the already-owned payload ID after publishing
    % the scheduled PHY population; no other grant mutation is permitted.
    ctx.Grant.TransportBlockIdentity=ctx.TransportBlockIdentity;
    assert(~phy.isReceptionReady(ctx) && isempty(fieldnames(phy.LastReplay)));
    reject(@()phy.decode(ctx),'sixgr:abstraction:ReceiveWindowNotAvailable');
    assert(isempty(fieldnames(phy.LastReplay)),'Pending reception must not manufacture an ACK/BLER draw.');
    badCtx=ctx; badCtx.Grant.RNTI=2;
    reject(@()phy.isReceptionReady(badCtx),'sixgr:abstraction:NetworkPopulation');
    badCtx=ctx; badCtx.Grant.TransportBlockIdentity="another_payload";
    reject(@()phy.isReceptionReady(badCtx),'sixgr:abstraction:NetworkPopulation');
    badCtx=ctx; badCtx.Grant.PHYGrant.PrecodingState.MatrixPorts=[1;0];
    reject(@()phy.isReceptionReady(badCtx),'sixgr:abstraction:NetworkPopulation');
    phy.setSlotContext(following);
    assert(phy.isReceptionReady(ctx));
end
[ack,bler]=phy.decode(ctx);
assert(~ack && bler==1 && ~phy.CalibrationQualified && phy.LastReplay.ResidualISIICIIncluded && ...
    phy.LastReplay.SINRPredictorModel=="finite_committed_shared_data" && ...
    phy.LastReplay.SourceClassification=="development_fixture_not_study_result");
assert(isequal(phy.LastReplay.ModeledSINRPerResourceLayer_dB,o.FiniteWindow.SpatialResult.SINR_dB));
assert(phy.LastReplay.TransmissionAbsoluteSlot0==0 && ...
    phy.LastReplay.ReceiveCompletionAbsoluteSlot0==double(options.Deferred));
assert(height(phy.NetworkSpatialTrace)==1 && phy.NetworkSpatialTrace.ResidualISIICIIncluded && ...
    phy.NetworkSpatialTrace.SINRPredictorModel=="finite_committed_shared_data");
assert(~phy.NetworkSpatialTrace.CSIRSInterferenceIncluded && ...
    phy.NetworkSpatialTrace.CSIRSEmissionCount==0 && ...
    ~phy.NetworkSpatialTrace.ReferenceSignalInterferenceQualified, ...
    'Shared-data-only evaluation must not claim emitted or qualified CSI-RS interference.');
snapshot=phy.publishLiveEvidence(folder);
persisted=jsondecode(fileread(fullfile(folder,'live','sls_evidence.json')));
assert(snapshot.CommittedThroughAbsoluteSlot0==double(options.Deferred) && ...
    ~persisted.PrimaryStudyAccepted && ~persisted.CalibrationQualified && ...
    persisted.Evidence.NetworkSpatial.TotalRows==1 && ...
    persisted.Evidence.NetworkSpatial.Rows.CSIRSEmissionCount==0 && ...
    isempty(persisted.Evidence.PendingReference.Rows));
calibration.Curves.Key=oldKey;
bad=saveFixture(cfg,calibration,fullfile(folder,'diagonal_fixture.mat'));
params.SpatialGrantProvider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
wrong=sixgr.system.PhyFactory.create(bad,params,'Seed',99); wrong.setSlotContext(slot);
if options.Deferred, wrong.setSlotContext(following); end
reject(@()wrong.decode(ctx),'sixgr:abstraction:CalibrationCoverage');
bad=cfg; bad.system.linkAbstraction.networkSpatial.sinrPredictorModel='auto_fallback';
reject(@()sixgr.system.abstraction.NetworkSpatialGrantProvider(bad),'sixgr:abstraction:NetworkSINRModel');
% A declared finite model without the complete executed recipe cannot bind.
e=struct('CalibrationReceiverIdentity',struct('SINRPredictorModel',"finite_committed_shared_data"), ...
    'CalibrationReceiverExecution',struct('RecipeExecutionChecked',true), ...
    'Propagation',struct('Metadata',struct('CalibrationChannelIdentity',struct())));
reject(@()sixgr.system.waveform.extractGrantCalibrationBinding(e),'sixgr:calibration:GrantPredictorModel');
fprintf('SLS_FINITE_PREDICTOR_BINDING_PASS runtime_branch=1 export_identity=1 wrong_curve_rejected=1 calibration_fixture_only=1\n');
ok=true;
end
function cfg=saveFixture(cfg,calibration,file)
save(file,'calibration');
cfg.system.linkAbstraction.calibrationFile=file;
cfg.system.linkAbstraction.calibrationSHA256=sixgr.csi.studyFileSHA256(file);
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
