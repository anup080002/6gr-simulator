function ok=testSLSDeferredReferenceFeedback()
% Causal native-channel SRS model with finite shared-data disturbance.
% This tests production observation/buffer plumbing, not calibrated BLER.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/finite_shared_data_feedback.yaml'));
cfg.run=struct('seed',113,'executionID','deferred_reference_feedback');
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.phy.srs=struct('enable',true,'nPorts',2,'period_slots',5,'period_offset',4, ...
    'CSRS',0,'BSRS',0,'BHop',0,'bandwidthRB',4,'expectedNumRB',4, ...
    'SymbolStart',13,'NumSRSSymbols',1,'resourceSetUsage','codebook');
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('D',5,14);
cfg.phy.frameStructure.SlotState.CommonDirection(5,:)='U';
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("DL",5,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection(5,:)="UL";
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=23;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.spatialFeedback.allowedRanks=[1 2];
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
large=struct('Pathloss_dB',[80 85;87 81],'TxPower_dBm',30*ones(2));
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
for slot=0:3
    state.TTI=slot+1; state.AbsoluteSlot0=slot;
    provider.commitSlotPopulation(state);
    assert(isempty(provider.observeSRS(state)));
end
state.TTI=5; state.AbsoluteSlot0=4;
% Frequency-disjoint source relative to the four-PRB sounding resource;
% finite filtering must still account for its nonzero leakage.
g=struct('RNTI',4661,'UEIndex',2,'PRBSet',5,'SymbolAllocation',[13 1],'NumLayers',1, ...
    'PHYGrant',struct('PrecodingState',struct('MatrixPorts',[1;1i]/sqrt(2))));
state.GrantsUL=g; state.GrantCellsUL=2;
provider.commitSlotPopulation(state);
assert(isempty(provider.observeSRS(state)), ...
    'Last-symbol narrow-grid SRS must wait for following committed samples.');
pending=provider.referenceFeedbackPending();
assert(height(pending)==2 && all(pending.SourceAbsoluteSlot0==4) && ...
    all(pending.RequiredThroughAbsoluteSlot0==5) && all(pending.LastCommittedAbsoluteSlot0==4) && ...
    all(pending.Status=="awaiting_committed_receive_window") && all(~pending.WaveformBacked));
state.TTI=6; state.AbsoluteSlot0=5;
state.GrantsUL=struct([]); state.GrantCellsUL=[];
state.LargeScaleState.Pathloss_dB=large.Pathloss_dB+3;
provider.commitSlotPopulation(state);
received=provider.observeSRS(state);
assert(numel(received)==2);
assert(isempty(provider.referenceFeedbackPending()));
o=received(1);
assert(o.SourceAbsoluteSlot0==4 && o.CompletionAbsoluteSlot0==5 && ...
    o.PublicationAbsoluteSlot0==5 && o.AvailableAbsoluteSlot0==6);
expectedChannel=provider.channel("UL",1,1,4,large,o.Coordinates0Based);
assert(isequal(o.ChannelEstimate,expectedChannel), ...
    'Deferred completion must preserve the source-slot channel, not the later propagation state.');
noise=10^((-174+10*log10(30000)+7-30)/10);
disturbance=o.ExternalCovariance-noise*eye(2);
assert(norm(disturbance(:))>0,'Executed disjoint-resource interference must not become thermal-only feedback.');
sixgr.system.abstraction.validateFeedbackCompletionClock(o,5);
queue=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(cfg.system.linkAbstraction.spatialFeedback);
queue.append(o,5);
assert(isempty(queue.select(1,1,5,6)));
r=queue.select(1,1,6,6);
assert(~isempty(r) && r.CompletionAbsoluteSlot0==5 && ~r.WaveformBacked && ...
    r.ReferenceCompletionEvidence.ReceiveWindow.RequiredCommittedThroughTTI==6);
bad=rmfield(o,'ReferenceCompletionEvidence');
reject(@()sixgr.system.abstraction.validateFeedbackCompletionClock(bad,5));
bad=o; bad.AvailableAbsoluteSlot0=5;
reject(@()sixgr.system.abstraction.validateFeedbackCompletionClock(bad,5));
bad=o; bad.SourceAbsoluteSlot0=3;
reject(@()sixgr.system.abstraction.validateFeedbackCompletionClock(bad,5));
bad=o; bad.ReferenceCompletionEvidence.ReceiveWindow.TTIs=5;
reject(@()sixgr.system.abstraction.validateFeedbackCompletionClock(bad,5));
reject(@()provider.observeSRS(state));
state.TTI=7; state.AbsoluteSlot0=6; provider.commitSlotPopulation(state);
assert(isempty(provider.observeSRS(state)),'A reference completion must not be published twice.');
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
save(fullfile(folder,'deferred_srs.mat'),'cfg','received','r','disturbance');
fprintf('SLS_DEFERRED_REFERENCE_FEEDBACK_PASS source=4 completion=5 delivery=6 evidence=%s\n',folder);
ok=true;
end
function reject(fn)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,'sixgr:abstraction:FeedbackCaptureClock'),'%s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Invalid reference completion was accepted.');
end
