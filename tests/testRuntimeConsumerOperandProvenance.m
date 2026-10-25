function ok = testRuntimeConsumerOperandProvenance()
% Actual producer calls must be observed; matching config alone proves none.
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()sixgr.runtime.RuntimeCallLedger.reset()); %#ok<NASGU>
sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId','operand_test', ...
    'ExecutionID','operand_execution','ConfigHash',repmat('a',1,64)));
assert(isempty(sixgr.runtime.RuntimeCallLedger.snapshot()));
cfg=struct('phy',struct('linkAdaptation',struct('feedbackDelaySlots',2)));
assert(isempty(sixgr.runtime.RuntimeCallLedger.snapshot()), ...
    'Configured operands must not fabricate consumption.');
sixgr.link.resolveLinkAdaptationFeedbackDelay(cfg);
cfg.phy.linkAdaptation.feedbackDelaySlots=3;
sixgr.link.resolveLinkAdaptationFeedbackDelay(cfg);
T=sixgr.runtime.RuntimeCallLedger.snapshot();
assert(height(T)==2 && numel(unique(T.ContextSHA256))==2, ...
    'Changed actual delay operands must produce distinct retained contexts.');
assert(all(endsWith(replace(T.SourceFile,"\","/"), ...
    '+sixgr/+link/resolveLinkAdaptationFeedbackDelay.m')));
assert(testTimingRelationEngine());
assert(testPRACHRACHCommonFDM());
% Use the selected supported NR tuple. The historical oversampled-SSB
% scenario has an unrelated obsolete Type-I CSI panel tuple and cannot
% serve as this runtime-consumer fixture.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    'simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
executed=sixgr.lls6g.buildInternalConfig(scenario,fullfile(folder,'n40_config'));
weights=executed.phy.ssb.precoderMatrices;
assert(size(weights,1)==executed.phy.ssb.Lmax && ...
    size(weights,2)==scenario.get('initial_access.ssb.precoder_codebook.physical_element_count') && ...
    all(abs(sum(abs(weights).^2,2)-1)<1e-12));
% Explicit active-beam count owns the transmitted bitmap, not Lmax.
timing=struct('Lmax',4,'CandidateStartSymbolsWithinHalfFrame',[2 8 16 22], ...
    'SelectedSSBIndex',0,'HalfFrameIndex',0,'SSBSubcarrierSpacingKHz',30, ...
    'BlockPattern',"Case B",'Case',"B",'PeriodicityMs',20);
ssb=struct('phy',struct('ssb',struct('activeBitmap',"1010",'beamCount',2)));
plan=sixgr.phy.ia.SSBBurstPlan.fromConfig(ssb,timing);
assert(nnz(plan.ActiveBitmap)==2);
ssb.phy.ssb.beamCount=3;
before=height(sixgr.runtime.RuntimeCallLedger.snapshot());
reject(@()sixgr.phy.ia.SSBBurstPlan.fromConfig(ssb,timing), ...
    'sixgr:phy:ia:SSBBeamCountBitmapMismatch');
assert(height(sixgr.runtime.RuntimeCallLedger.snapshot())==before);
% The actual selected mode, including an explicit call-site override, is
% part of the context. Legacy arbitrary beam count is not strict PMI size.
pmi=struct('phy',struct('csi',struct('pmiCodebookMode',"noncodebook")));
sixgr.phy.dl.pmiCodebookCandidates(pmi,1,2);
sixgr.phy.dl.pmiCodebookCandidates(pmi,1,2,'Mode','type1_su_mimo');
T=sixgr.runtime.RuntimeCallLedger.snapshot();
P=T(T.FunctionName=="sixgr.phy.dl.pmiCodebookCandidates.selectedMode",:);
assert(height(P)==2 && numel(unique(P.ContextSHA256))==2);
localNativeOrientation();
T=sixgr.runtime.RuntimeCallLedger.snapshot();
sixgr.runtime.RuntimeCallLedger.flush();
save(fullfile(folder,'consumer_ledger_snapshot.mat'),'T');
fprintf('RUNTIME_CONSUMER_OPERAND_PROVENANCE_EVIDENCE %s\n',folder);
required=["sixgr.phy.frame.TimingRelationEngine.resolveK0", ...
    "sixgr.phy.frame.TimingRelationEngine.resolveK1", ...
    "sixgr.phy.frame.TimingRelationEngine.resolveK2", ...
    "sixgr.phy.ra.generateMsg1PRACHWaveform", ...
    "sixgr.lls6g.buildInternalConfig.materializeSSBPrecoder", ...
    "sixgr.phy.ia.SSBBurstPlan.activeBeamCount", ...
    "sixgr.channel.ChannelFactory.applyCDLArrayOrientation"];
assert(all(ismember(required,string(T.FunctionName))), ...
    'Real timing, PRACH and codebook producers must retain execution receipts.');
invalid=strlength(T.ContextSHA256)~=64 | ...
    T.RunId~="operand_test" | T.ExecutionID~="operand_execution";
if any(invalid)
    disp(T(invalid,{'FunctionName','SourceFile','ContextSHA256','RunId','ExecutionID'}));
end
assert(~any(invalid),'test:InvalidConsumerProvenance', ...
    'Invalid context or lifecycle for: %s',strjoin(string(T.FunctionName(invalid)),', '));
sixgr.runtime.RuntimeCallLedger.flush();
fprintf('RUNTIME_CONSUMER_OPERAND_PROVENANCE_PASS evidence=%s\n',folder);
ok=true;
end

function localNativeOrientation()
cfg=sixgr.config.defaultConfig();
cfg.channel.model='CDL-D'; cfg.channel.cdlProfile='CDL-D';
cfg.channel.delayProfile='CDL-D'; cfg.channel.fading.profile='CDL-D';
cfg.channel.fading.model='CDL-D';
meta=struct('NumRows',2,'NumCols',1,'NumPolarizations',1, ...
    'PanelRows',1,'PanelCols',1,'SpacingH_lambda',0.5,'SpacingV_lambda',0.5, ...
    'Azimuth_deg',10,'Tilt_deg',2,'BoresightAzimuth_deg',3, ...
    'BoresightElevation_deg',4,'BoresightSlant_deg',5);
args={'SampleRate',30.72e6,'NumTxAnt',2,'NumRxAnt',2,'Fc_Hz',3.5e9,'Seed',11};
T=sixgr.runtime.RuntimeCallLedger.snapshot(); n=height(T);
% No runtime geometry: native default geometry is valid but cannot claim
% the configured-boresight operation was executed.
sixgr.channel.ChannelFactory.create(cfg,args{:});
T=sixgr.runtime.RuntimeCallLedger.snapshot();
assert(~any(T.FunctionName(n+1:end)=="sixgr.channel.ChannelFactory.applyCDLArrayOrientation"));
ch=sixgr.channel.ChannelFactory.create(cfg,args{:}, ...
    'TransmitAntennaMeta',meta,'ReceiveAntennaMeta',meta);
assert(isequal(double(ch.Object.TransmitArrayOrientation(:)),[13;-2;5]) && ...
    isequal(double(ch.Object.ReceiveArrayOrientation(:)),[13;-2;5]));
T=sixgr.runtime.RuntimeCallLedger.snapshot();
assert(nnz(T.FunctionName=="sixgr.channel.ChannelFactory.applyCDLArrayOrientation")==2);
bad=cfg; bad.channel.model='not_a_channel'; n=height(T);
try
    sixgr.channel.ChannelFactory.create(bad,args{:}, ...
        'TransmitAntennaMeta',meta,'ReceiveAntennaMeta',meta);
    error('test:MissingFailure','Invalid channel must fail before orientation application.');
catch cause
    assert(~strcmp(cause.identifier,'test:MissingFailure'));
end
T=sixgr.runtime.RuntimeCallLedger.snapshot();
assert(~any(T.FunctionName(n+1:end)=="sixgr.channel.ChannelFactory.applyCDLArrayOrientation"));
end

function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier);
    return;
end
error('test:MissingFailure','Expected %s.',id);
end
