function ok=testCalibratedLinkPHY()
% Test-only tables are never admitted as physical calibration/study evidence.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run.seed=7;
cfg.system.linkAbstraction.allowDevelopmentFixtures=true;
cfg.system.linkAbstraction.spatialProviderClass='SLSAbstractionFixtureProvider';
provider=SLSAbstractionFixtureProvider();
params=struct('SpatialGrantProvider',provider);
g=struct('RNTI',1,'PRBSet',0:4,'SymbolAllocation',[0 14], ...
    'Modulation','QPSK','TBSBits',160,'HARQ',struct('HarqID',0,'RV',0));
ctx=struct('Grant',g,'Direction',"UL",'ServingCellID',1,'TTI',1, ...
    'TransportBlockIdentity',"fixture_tb1",'IsRetransmission',false, ...
    'TBSBits',160,'NumLayers',1,'TargetCodeRate',.12,'SCS_kHz',30,'ChannelModel',"AWGN");
slot=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',g, ...
    'GrantCellsDL',[],'GrantCellsUL',1);
o=provider.evaluate(ctx,slot);
key=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,o);
curve=struct('CurveID',"first",'Key',key,'RVSequence',0, ...
    'SINRAxes_dB',{{[-10;10]}},'BetaLinear',1,'TrialCount',[2000;2000], ...
    'ErrorCount',[2000;2000],'ValidationTrialCount',[2000;2000], ...
    'ValidationErrorCount',[2000;2000]);
second=curve; second.CurveID="second"; second.RVSequence=[0 2];
second.SINRAxes_dB={[-10;10],[-10;10]};
second.TrialCount=2000*ones(2); second.ValidationTrialCount=2000*ones(2);
second.ErrorCount=[1400 1000;600 200]; second.ValidationErrorCount=second.ErrorCount;
second.BetaLinear=2;
calibration=struct('Schema',"sixgr.calibrated_sls_link/v1", ...
    'CalibrationID',"numerical_fixture_not_measurements", ...
    'SourceClassification',"development_fixture_not_physical_calibration", ...
    'Curves',[curve second]);
folder=tempname; mkdir(folder);
file=fullfile(folder,'calibration.mat'); save(file,'calibration');
cfg.system.linkAbstraction.calibrationFile=file;
cfg.system.linkAbstraction.calibrationSHA256=sixgr.csi.studyFileSHA256(file);
phy=sixgr.system.PhyFactory.create(cfg,params,'Seed',99); phy.setSlotContext(slot);
[ack,p]=phy.decode(ctx);
assert(~ack && p==1 && ~phy.CalibrationQualified && ~phy.LastReplay.WaveformReplayExecuted);
assert(phy.LastReplay.SourceClassification=="development_fixture_not_study_result");
ctx.TTI=2; ctx.IsRetransmission=true; ctx.Grant.HARQ.RV=2; slot.TTI=2;
phy.setSlotContext(slot); [ack,p]=phy.decode(ctx); %#ok<ASGLU>
assert(abs(p-.4)<1e-12 && isequal(phy.LastReplay.HARQSINRHistory_dB,[0 0]));
assert(isequal(phy.LastReplay.HARQRVHistory,[0 2]));
assert(phy.LastReplay.HARQHistoryMappingBetaLinear==2);
feature={{[.1;10],[.2;8]}};
mapped=sixgr.system.abstraction.mapHARQHistory(feature{1},second);
assert(abs(mapped(1)-10*log10(sixgr.util.eesmLinear([.1;10],2)))<1e-12 && ...
    abs(mapped(2)-10*log10(sixgr.util.eesmLinear([.2;8],2)))<1e-12);
% No first-TX lookup rescue for another sequence.
fresh=sixgr.system.PhyFactory.create(cfg,params,'Seed',99);
ctx.TTI=1; ctx.IsRetransmission=false; ctx.Grant.HARQ.RV=0; slot.TTI=1;
fresh.setSlotContext(slot); fresh.decode(ctx);
ctx.TTI=2; ctx.IsRetransmission=true; ctx.Grant.HARQ.RV=3; slot.TTI=2; fresh.setSlotContext(slot);
localReject(@()fresh.decode(ctx),'sixgr:abstraction:CalibrationCoverage');
ctx.Grant.HARQ.RV=2; ctx.TBSBits=168; ctx.Grant.TBSBits=168;
localReject(@()fresh.decode(ctx),'sixgr:abstraction:HARQIdentity');
ctx.TBSBits=160; ctx.Grant.TBSBits=160; ctx.IsRetransmission=false; ctx.TransportBlockIdentity="fixture_tb2";
ctx.Grant.HARQ.RV=0; provider.SINR_dB=11;
localReject(@()fresh.decode(ctx),'sixgr:abstraction:SINROutOfCalibration');
bad=cfg; bad.system.linkAbstraction.allowDevelopmentFixtures=false;
localReject(@()sixgr.system.PhyFactory.create(bad,params),'sixgr:abstraction:CalibrationSource');
bad=cfg; bad.system.linkAbstraction.calibrationSHA256=repmat('0',1,64);
localReject(@()sixgr.system.PhyFactory.create(bad,params),'sixgr:abstraction:CalibrationDigest');
bad=cfg; bad.system.linkAbstraction.requiredRFProfileID='assumed_PN_compensated_not_ideal';
rfMismatch=sixgr.system.PhyFactory.create(bad,params,'Seed',99); rfMismatch.setSlotContext(slot);
localReject(@()rfMismatch.decode(ctx),'sixgr:abstraction:RFProfileMismatch');
% Switching equalizer cannot silently reuse the LMMSE BLER calibration.
bad=cfg; bad.system.linkAbstraction.receiverType='zf';
zf=sixgr.system.PhyFactory.create(bad,params,'Seed',99); zf.setSlotContext(slot);
localReject(@()zf.decode(ctx),'sixgr:abstraction:CalibrationCoverage');
badCurve=second; badCurve.ValidationErrorCount(1)=0;
localReject(@()sixgr.system.abstraction.validateBLERCurve(badCurve,cfg.system.linkAbstraction), ...
    'sixgr:abstraction:CalibrationValidation');
% Sparse HARQ support is allowed only at measured vertices. Interpolation
% cannot cross an unsupported conditional-history corner.
sparse=second; sparse.SupportedMask=[true false;true true];
sparse.TrialCount(1,2)=0; sparse.ErrorCount(1,2)=0;
sparse.ValidationTrialCount(1,2)=0; sparse.ValidationErrorCount(1,2)=0;
sixgr.system.abstraction.validateBLERCurve(sparse,cfg.system.linkAbstraction);
rare=curve; rare.ErrorCount(2)=0; rare.ValidationErrorCount(2)=0;
sixgr.system.abstraction.validateBLERCurve(rare,cfg.system.linkAbstraction);
assert(rare.TrialCount(2)==2000 && rare.ErrorCount(2)==0, ...
    'Observed zero errors are valid evidence with a bounded confidence interval.');
sixgr.system.abstraction.assertSupportedSINRHistory(sparse.SINRAxes_dB,sparse.SupportedMask,[-10 -10]);
localReject(@()sixgr.system.abstraction.assertSupportedSINRHistory( ...
    sparse.SINRAxes_dB,sparse.SupportedMask,[-10 0]), ...
    'sixgr:abstraction:UnsupportedSINRHistory');
abstract=struct('Details',struct('ExecutionBackend',"CALIBRATED_LINK_ABSTRACTION"));
localReject(@()sixgr.truth.exportSystemLevelCanonicalArtifacts(folder,struct(),cfg,abstract), ...
    'sixgr:truth:AbstractSLSNotWaveformTrials');
% MIESM is actually executed by the backend, with its own retained lookup
% and calibration keys. The values here remain explicit numerical fixtures.
lookup=struct('SINRGrid_dB',[-10 0 10], ...
    'MutualInformation_bitsPerSymbol',[.1 .6 1.7],'ModulationOrder',4,'BetaLinear',1);
for k=1:numel(calibration.Curves)
    calibration.Curves(k).Key.EffectiveSINRMethod="calibrated_miesm";
    curveLookup=lookup;
    curveLookup.BetaLinear=calibration.Curves(k).BetaLinear;
    calibration.Curves(k).MILookup=curveLookup;
end
fileMI=fullfile(folder,'miesm_fixture.mat'); save(fileMI,'calibration');
cfg.system.linkAbstraction.calibrationFile=fileMI;
cfg.system.linkAbstraction.calibrationSHA256=sixgr.csi.studyFileSHA256(fileMI);
cfg.system.linkAbstraction.effectiveSINRMethod='calibrated_miesm';
provider.SINR_dB=0; ctx.TTI=1; ctx.TransportBlockIdentity="mi_tb";
ctx.IsRetransmission=false; ctx.Grant.HARQ.RV=0; slot.TTI=1;
miPHY=sixgr.system.PhyFactory.create(cfg,params,'Seed',99); miPHY.setSlotContext(slot);
[ack,p]=miPHY.decode(ctx); assert(~ack && p==1);
assert(miPHY.LastReplay.EffectiveSINRMethod=="calibrated_miesm");
ctx.TTI=2; ctx.IsRetransmission=true; ctx.Grant.HARQ.RV=2; slot.TTI=2;
miPHY.setSlotContext(slot); [~,p]=miPHY.decode(ctx); assert(abs(p-.4)<1e-12);
badCurve=calibration.Curves(1); badCurve.MILookup.ModulationOrder=16;
localReject(@()sixgr.system.abstraction.validateBLERCurve(badCurve,cfg.system.linkAbstraction), ...
    'sixgr:abstraction:CalibrationSchema');
% Keep fixture evidence for debugging under the named log, not study CSVs.
ok=true; fprintf('CALIBRATED_LINK_PHY_PASS fixture_only=1\n');
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:ExpectedError','Expected %s.',id);
end
