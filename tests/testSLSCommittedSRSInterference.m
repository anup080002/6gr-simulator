function ok=testSLSCommittedSRSInterference()
% Native emitted pilots -> finite network covariance -> causal SRS feedback.
% An independent aggregate waveform checks the modeled propagation result.
cfg=sixgr.config.defaultConfig();
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/calibrated_link_abstraction.yaml'));
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/finite_srs_interference.yaml'));
cfg.run.seed=113; cfg.run.executionID='committed_srs_interference';
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.phy.srs=struct('enable',true,'nPorts',2,'period_slots',5,'period_offset',4, ...
    'CSRS',0,'BSRS',0,'BHop',0,'bandwidthRB',4,'expectedNumRB',4, ...
    'SymbolStart',13,'NumSRSSymbols',1,'resourceSetUsage','codebook');
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('U',5,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("UL",5,14);
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=[23 17];
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false,'awgnOnly',false);
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.spatialFeedback.allowedRanks=[1 2];
cfg.phy.pusch.transformPrecoding=false;
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
old=cfg; old.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_grants_only';
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(old);
large=struct('Pathloss_dB',[80 85;87 81],'TxPower_dBm',30*ones(2));
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2],'RNTIByUE',[4660 4661], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
for slot=0:4
    state.TTI=slot+1; state.AbsoluteSlot0=slot;
    provider.commitSlotPopulation(state); baseline.commitSlotPopulation(state);
    assert(isempty(provider.observeSRS(state)) && isempty(baseline.observeSRS(state)));
    e=provider.committedSRSEmissions(slot+1);
    if slot<4, assert(isempty(e)); else, assert(numel(e)==2); end
end
emissions=provider.committedSRSEmissions(5);
for e=emissions
    actual=sum(abs((e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.').^2,'all');
    assert(abs(actual-e.ConfiguredTotalPower_W)<1e-12);
    assert(e.SymbolSource=="nrSRS_and_nrSRSIndices" && e.AbsoluteSlot0==4);
end
provider.commitSlotPopulation(state); % same committed event is idempotent
bad=state; bad.RNTIByUE(1)=99;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:SlotHistoryMutation');
state.TTI=6; state.AbsoluteSlot0=5;
provider.commitSlotPopulation(state); baseline.commitSlotPopulation(state);
received=provider.observeSRS(state); thermal=baseline.observeSRS(state);
assert(numel(received)==2 && numel(thermal)==2);
o=received(1); coords=o.Coordinates0Based;
assert(o.ReferenceResourceID==emissions(1).ResourceID && ...
    o.ReferenceEmissionSHA256==emissions(1).SHA256 && o.ReferenceRNTI==4660 && ...
    ~isfield(thermal,'ReferenceEmissionSHA256'), ...
    'Retain the desired native SRS, not an interfering pilot or a fabricated thermal-only emission.');
sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(cfg,o);
ctx=struct('TTI',5,'Direction',"UL",'UEIndex',1,'ServingCellID',1);
finite=provider.evaluateReferenceInterference(ctx,coords);
assert(finite.SRSInterferenceIncluded && numel(finite.SRSEmissionPopulation)==1 && ...
    finite.SRSEmissionPopulation.UEIndex==2 && ~finite.WaveformMeasured);
assert(norm(o.ExternalCovariance(:)-thermal(1).ExternalCovariance(:))>0);
assert(o.ReferenceCompletionEvidence.InterferencePopulation=="scheduled_shared_data_and_srs" && ...
    o.CompletionAbsoluteSlot0==5 && o.AvailableAbsoluteSlot0==6);
expected=independentWaveform(cfg,emissions(2),finite.ReceiveWindow,coords,large);
error=norm(expected-finite.ExplicitReferenceResponse,'fro')/norm(expected,'fro');
assert(error<2e-11,'test:SRSNetworkWaveformMismatch','Native network SRS differs by %g.',error);
for k=1:size(coords,1)
    v=expected(:,k); actual=o.ExternalCovariance(:,:,k)-thermal(1).ExternalCovariance(:,:,k);
    assert(norm(actual-v*v','fro')<1e-10*max(norm(v*v','fro'),realmin));
end
q=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(cfg.system.linkAbstraction.spatialFeedback);
q.append(o,5); assert(isempty(q.select(1,1,5,6)));
feedback=q.select(1,1,6,6);
assert(~isempty(feedback) && ~feedback.WaveformBacked && ...
    feedback.ReferenceCompletionEvidence.SRSInterferenceIncluded && ...
    feedback.ReferenceResourceID==o.ReferenceResourceID && ...
    feedback.ReferenceEmissionSHA256==o.ReferenceEmissionSHA256 && feedback.ReferenceRNTI==4660);
bound=feedback; bound.RNTI=4660;
bound.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(bound)),'UTF-8'))));
grant=struct('ModeledSRSFeedback',bound,'RNTI',4660,'SRI',bound.SRI, ...
    'ControlAbsoluteSlot',6,'ScheduledAbsoluteSlot',6);
checking=cfg; checking.system.linkAbstraction.spatialFeedback.enabled=true;
sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant( ...
    checking,grant,bound.RI,bound.NumPorts,bound.TPMI);
wrongWaveform=grant; wrongWaveform.TransformPrecoding=true;
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant( ...
    checking,wrongWaveform,bound.RI,bound.NumPorts,bound.TPMI), ...
    'sixgr:abstraction:FeedbackWaveform');
for population=["scheduled_shared_data_and_srs", "scheduled_shared_data_and_srs_and_csirs", ...
        "scheduled_shared_data_and_srs_and_csirs_and_pdcch"]
    checking.system.linkAbstraction.networkSpatial.interferencePopulation=population;
    missing=rmfield(o,'ReferenceEmissionSHA256');
    reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(checking,missing), ...
        'sixgr:abstraction:SRSFeedbackEmissionBinding');
    wrong=o; wrong.ReferenceResourceID=o.ReferenceResourceID+1;
    reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(checking,wrong), ...
        'sixgr:abstraction:SRSFeedbackEmissionBinding');
    wrong=grant; wrong.ModeledSRSFeedback.ReferenceRNTI=4661;
    reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant( ...
        checking,wrong,bound.RI,bound.NumPorts,bound.TPMI), ...
        'sixgr:abstraction:SRSFeedbackEmissionBinding');
end
% No data reservation or table row may manufacture a transmission.
off=cfg; off.phy.srs.enable=false;
assert(isempty(sixgr.system.abstraction.buildScheduledSRSEmissions(off,state)));
g=struct('RNTI',4660,'UEIndex',1,'SymbolAllocation',[12 2]);
bad=state; bad.TTI=5; bad.AbsoluteSlot0=4; bad.GrantsUL=g;
reject(@()sixgr.system.abstraction.buildScheduledSRSEmissions(cfg,bad), ...
    'sixgr:abstraction:SRSEmissionPUSCHCollision');
% The channel identity must not permit a shared-data-only BLER package to
% stand in for a different emitted pilot population and power policy.
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30); infoOFDM=nrOFDMInfo(carrier);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,infoOFDM.SampleRate,"DL");
newID=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,native.Object);
oldID=sixgr.system.abstraction.networkChannelCalibrationIdentity(old,native.Object);
assert(newID.ProfileID~=oldID.ProfileID);
configuredUEIntegration(cfg,large,native.Object);
dataIntegration(cfg,large);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
save(fullfile(folder,'srs_network_interference.mat'),'cfg','emissions','received','thermal','finite','expected','error');
fprintf('SLS_COMMITTED_SRS_PASS emitted_UEs=2 excluded_desired_pilot=1 causal_delivery=1 relative_waveform_error=%g evidence=%s\n',error,folder);
ok=true;
end
function configuredUEIntegration(cfg,large,channel)
% Same-cell UEs must use their actual individually installed pilot resources
% through emission, observation, causal delivery and calibration identity.
fragment=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/srs_two_ue_frequency_bindings.yaml');
boundCfg=sixgr.util.mergeStruct(cfg,fragment);
boundCfg.phy.srs.ueResourceBindings(2).resource_id=37;
a=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,channel);
b=sixgr.system.abstraction.networkChannelCalibrationIdentity(boundCfg,channel);
assert(a.ProfileID~=b.ProfileID);
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(boundCfg);
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 1],'RNTIByUE',[4660 4661], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
for slot=0:5
    state.TTI=slot+1; state.AbsoluteSlot0=slot;
    provider.commitSlotPopulation(state);
    % Capture at source-slot commitment and complete only after the receive
    % window exists. A one-off poll after slot 5 cannot create slot 4 pilots.
    o=provider.observeSRS(state);
    if slot<5, assert(isempty(o)); end
end
e=provider.committedSRSEmissions(5);
assert(numel(e)==2 && isequal([e.ResourceID],[0 37]) && all([e.SRI]==0));
assert(isempty(intersect(e(1).Coordinates0Based,e(2).Coordinates0Based,'rows')));
assert(numel(o)==2);
for u=1:2
    one=o([o.UEIndex]==u);
    assert(isscalar(one) && one.SRI==0 && one.ReferenceResourceID==e(u).ResourceID && ...
        one.ReferenceEmissionSHA256==e(u).SHA256 && ...
        isequal(sortrows(one.Coordinates0Based),sortrows(e(u).Coordinates0Based)));
    sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(boundCfg,one);
    buffer=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(boundCfg.system.linkAbstraction.spatialFeedback);
    buffer.append(one,5); received=buffer.select(u,1,6,6);
    assert(~isempty(received) && received.SRI==0 && ~received.WaveformBacked);
    sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(boundCfg,received);
    received.RNTI=state.RNTIByUE(u);
    received.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(received)),'UTF-8'))));
    g=struct('ModeledSRSFeedback',received,'RNTI',received.RNTI,'SRI',0, ...
        'ControlAbsoluteSlot',6,'ScheduledAbsoluteSlot',6);
    checking=boundCfg; checking.system.linkAbstraction.spatialFeedback.enabled=true;
    sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant( ...
        checking,g,received.RI,received.NumPorts,received.TPMI);
end
wrong=o(2); wrong.ReferenceResourceID=0;
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(boundCfg,wrong), ...
    'sixgr:abstraction:SRSFeedbackEmissionBinding');
wrong=o(2); wrong.SRI=37;
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(boundCfg,wrong), ...
    'sixgr:abstraction:SRSFeedbackEmissionBinding');
% Deliberately identical pilots remain identical, not silently randomized.
collision=boundCfg; collision.phy.srs.ueResourceBindings(2).comb_offset=0;
state.TTI=5; state.AbsoluteSlot0=4;
ce=sixgr.system.abstraction.buildScheduledSRSEmissions(collision,state);
assert(isequal(ce(1).Coordinates0Based,ce(2).Coordinates0Based) && ...
    isequal(ce(1).Symbols,ce(2).Symbols));
fprintf('SLS_CONFIGURED_UE_SRS_RESOURCE_PASS same_cell_UEs=2 native_emission_and_causal_consumer=1\n');
end
function dataIntegration(cfg,large)
% Frozen native PUSCH begins in the slot following SRS. Previous-slot pilot
% tails belong in the actual data receiver disturbance, not only CSI/SRS.
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2; cfg.channel.nTxAnt=2; cfg.channel.nRxAnt=2;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.phy.ssb.enable=false; cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
for name=["pdsch","pusch"]
    cfg.phy.(name).numLayers=2; cfg.phy.(name).nLayers=2;
    cfg.phy.(name).numPorts=2; cfg.phy.(name).nPorts=2;
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
    cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
    cfg.phy.(name).dmrs.portSet=0:1; cfg.phy.(name).enablePTRS=false;
end
cfg.phy.pusch.transformPrecoding=false; cfg.phy.pusch.mappingType='B';
cfg.phy.pusch.dmrs.numCDMGroupsWithoutData=1;
g=struct('Direction','UL','Frame',0,'Slot',5,'ScheduledAbsoluteSlot',5, ...
    'RNTI',4660,'UEIndex',1,'ServingCell',1,'PRBSet',0,'SymbolAllocation',[0 2], ...
    'Modulation','QPSK','NumLayers',2,'Layers',2,'NumLogicalPorts',2,'NumRFChains',2, ...
    'TargetCodeRate',mcs.TargetCodeRate,'MCSIndex',1,'MCSTable','qam64_table1', ...
    'PrecodingMatrixLogicalPorts',eye(2)/sqrt(2),'PrecodingMatrix',eye(2)/sqrt(2), ...
    'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','numerical_contract_fixture');
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"UL",g,'Frame',0,'Slot',5);
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
old=cfg; old.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_grants_only';
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(old);
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2],'RNTIByUE',[4660 4661], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
for slot=0:5
    state.TTI=slot+1; state.AbsoluteSlot0=slot;
    if slot==5, state.GrantsUL=g; state.GrantCellsUL=1; end
    provider.commitSlotPopulation(state); baseline.commitSlotPopulation(state);
end
ctx=struct('TTI',6,'Direction',"UL",'Grant',g,'ServingCellID',1);
a=provider.evaluate(ctx,state); b=baseline.evaluate(ctx,state);
assert(a.SRSInterferenceIncluded && a.SRSEmissionCount==2 && ...
    a.ChannelProfileID~=b.ChannelProfileID && ~a.ReferenceSignalInterferenceQualified);
expected=zeros(size(a.FiniteWindow.ExplicitReferenceResponse));
for e=provider.committedSRSEmissions(5)
    expected=expected+independentWaveform(cfg,e,a.FiniteWindow.ReceiveWindow,a.Coordinates0Based,large);
end
assert(norm(expected,'fro')>0,'The data regression must exercise actual previous-slot SRS leakage.');
error=norm(a.FiniteWindow.ExplicitReferenceResponse-expected,'fro')/norm(expected,'fro');
assert(error<2e-10);
assert(norm(a.ExternalCovariance(:)-b.ExternalCovariance(:))>0);
assert(any(a.FiniteWindow.SpatialResult.SINRLinear<b.FiniteWindow.SpatialResult.SINRLinear,'all'));
fprintf('SLS_SRS_DATA_INTERFERENCE_PASS native_frozen_PUSCH=1 prior_slot_SRS=2 waveform_error=%g\n',error);
end
function expected=independentWaveform(cfg,e,window,coords,large)
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30);
first=window.AbsoluteSlots0(1); carrier.NSlot=mod(first,carrier.SlotsPerFrame);
ofdm=nrOFDMInfo(carrier); nsym=numel(window.TTIs)*14;
grid=complex(zeros(72,nsym,2)); source=e.Coordinates0Based;
source(:,2)=source(:,2)+(e.AbsoluteSlot0-first)*14;
values=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
for port=1:2
    indices=sub2ind(size(grid),source(:,1)+1,source(:,2)+1,repmat(port,size(source,1),1));
    grid(indices)=values(:,port);
end
wave=nrOFDMModulate(carrier,grid,'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'Windowing',0);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
ch=native.Object; release(ch); ch.ChannelFiltering=false; ch.ChannelResponseOutput='path-gains';
ch.PathGainSampleRate='signal'; ch.RandomStream='mt19937ar with seed';
hash=char(sixgr.util.sha256Hex(uint8(char(string(cfg.run.seed)+"_network_link_"+e.UEIndex+"_1"))));
ch.Seed=mod(hex2dec(hash(1:8)),2^32-1);
ch.InitialTime=sixgr.phy.frame.slotStartSample(carrier,first,ofdm.SampleRate)/ofdm.SampleRate;
swapTransmitAndReceive(ch); metadata=info(ch); trim=metadata.ChannelFilterDelay;
padding=trim+ceil(max(metadata.PathDelays)*ofdm.SampleRate);
ch.NumTimeSamples=size(wave,1)+padding; [gains,~]=ch();
gains=gains*10^(-large.Pathloss_dB(e.UEIndex,1)/20); filters=getPathFilters(ch);
rx=sixgr.phy.waveform.applySampledFadingChannel([wave;zeros(padding,2)],filters,gains, ...
    complex(zeros(size(filters,1)-1,2,size(filters,2))));
demod=nrOFDMDemodulate(carrier,rx(trim+(1:size(wave,1)),:), ...
    'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'CyclicPrefixFraction',.5);
coords(:,2)=coords(:,2)+(window.ObservationTTI-1-first)*14;
demod=reshape(demod,72*nsym,2);
expected=demod(sub2ind([72 nsym],coords(:,1)+1,coords(:,2)+1),:).';
end
function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
