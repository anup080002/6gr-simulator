function ok=testHARQReplayBeamTransitionPreparation()
% Real TX preparation/replay; NACK and CSI/TCI are declared boundary inputs.
% No PDCCH/UCI reception, fading/RF execution, PDSCH RX, or BLER claim.
% The changed-beam case MUST prepare a coherent current B occasion. The
% current StaleAuthoredSchedulerDCIContext defect is NOT an expected PASS.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng;
restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
parent=fullfile(pwd,'results','validation','harq_replay_beam_transition_preparation');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('HARQ_REPLAY_BEAM_TRANSITION_PREPARATION artifacts=%s\n',folder);

scenarioPath=fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
scenario=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(folder,'configuration'));
assert(cfg.phy.carrier.NSizeGrid==51 && cfg.phy.carrier.SubcarrierSpacing==30 && ...
    size(cfg.phy.csirs.precoderMatrices,1)==64 && ...
    size(cfg.phy.csirs.precoderMatrices,2)==4 && cfg.phy.csirs.numResources==8);
% Isolate the preparation owner: this test never executes a channel. An
% explicit AWGN metadata configuration avoids allocating unrelated fading
% state when the production replay helper attaches its channel context.
% All scenario files and the live n40 campaign remain unchanged.
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.fading.enable=false;
cfg.channel.sharedIdentityAWGNEnabled=false;
cfg.channel.awgnSpatialMatrixDL=[];
cfg.phy.pdsch.prbSet=0:5; cfg.phy.pdsch.nPRB=6;
cfg.phy.pdsch.numLayers=1; cfg.phy.pdsch.nLayers=1;
cfg.phy.pdsch.dmrs.portSet=0; cfg.phy.pdsch.dmrs.DMRSPortSet=0;
cfg.lls6g.userContext.UEIndex=1;
cfg.lls6g.userContext.RuntimeUEIndex=1;
cfg.lls6g.userContext.RNTI=double(cfg.phy.pdsch.RNTI);
assert(~sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg));
[candidates,~]=sixgr.phy.dl.pmiCodebookCandidates(cfg,1,4,'Mode','type1_su_mimo');
assert(numel(candidates)>=2);
criA=0; criB=3;
pmiA=double(candidates(1).PMI); pmiB=double(candidates(2).PMI);
logicalA=double(candidates(1).W); logicalB=double(candidates(2).W);
basisA=double(cfg.phy.csirs.precoderMatrices(:,:,criA+1));
basisB=double(cfg.phy.csirs.precoderMatrices(:,:,criB+1));
physicalA=basisA*logicalA; physicalB=basisB*logicalB;
assert(~isequaln(physicalA,physicalB));
initialSlot=21; retrySlot=31;
cfgA=localConfiguration(cfg,criA,pmiA,initialSlot);
multi=struct('Enabled',true,'NumUsers',1, ...
    'RNTIStart',double(cfgA.phy.pdsch.RNTI),'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfgA,folder,multi,struct(),retrySlot);
state.CurrentServingIdx(:)=1;
state.CurrentSlot=initialSlot; state.CurrentFrame=2;
rnti=sixgr.truth.CoupledRadioIdentity.resolve(state,1);
assert(rnti==cfgA.phy.pdsch.RNTI);

% Native allocation owns the original TBS. The actual HARQ entity owns the
% process/NDI, and the following original TX really encodes these exact bits.
initial=sixgr.link.resolveWaveformGrant(cfgA,'DL',2, ...
    'Slot',initialSlot,'ControlAbsoluteSlot',initialSlot-1);
assert(initial.Valid && initial.ExactPHYFeasible);
allocation=state.DLHarq.allocate(rnti,initialSlot,initial.TBSBits/8,'NewData',true);
initial.HARQ=allocation.HARQ;
initial.HARQProcess=double(allocation.HARQ.HarqID);
initial.CRI=criA; initial.PMI=pmiA; initial.AppliedPrecoderPMI=pmiA;
initial.ServingCell=1;
initial.TransportBlockId='declared-preparation-original-TB';
initial.TBId=initial.TransportBlockId;
scheduler=sixgr.l2.mac.SchedulerPF(cfgA,'Direction','DL');
initial=scheduler.freezePHYGrantForGrant(initial, ...
    'TimingAlreadySelected',true,'ActiveConfig',cfgA);
initial.DCI=scheduler.buildDCIBitfield(initial,cfgA);
bits=int8(mod((0:double(initial.TBSBits)-1).',2));
[originalTX,originalInfo]=localTransmit(cfgA,initial,bits,initial.HARQ.RV);
localAssertTX(originalTX,initial,bits,physicalA,initialSlot);
localAssertSpatial(initial.PHYGrant,cfgA,logicalA,basisA,physicalA);
originalReceipt=localReceipt('original_A',cfgA,initial,originalTX,originalInfo);
save(fullfile(folder,'original_A.mat'),'originalReceipt','bits','-v7.3');
state.DLHarq.onTx(rnti,initial.HARQ.HarqID,uint8(originalTX.TransportBlock(:)), ...
    initial,initialSlot);
% Explicit control-boundary fixture, NOT an invented decoder/received ACK.
state.DLHarq.onFeedback(rnti,initial.HARQ.HarqID,'NACK', ...
    'SourceSlot',initialSlot,'FeedbackSlot',retrySlot);
state.CurrentSlot=retrySlot; state.CurrentFrame=2;
originalReplay=state.DLHarq.peekRetx(rnti,retrySlot);
assert(~isempty(originalReplay) && ...
    isequal(uint8(originalReplay.TB(:)),uint8(bits)) && ...
    originalReplay.HARQ.NDI==initial.HARQ.NDI && ...
    originalReplay.HARQ.HarqID==initial.HARQ.HarqID);
clear originalTX originalInfo

% Two independent preparation probes of the SAME outstanding HARQ retry.
% Preparation is not a transmitted/received commit and must not consume it.
labels=["unchanged_A","changed_A_to_B"];
for k=1:2
    if k==1
        cri=criA; pmi=pmiA; logical=logicalA; basis=basisA; physical=physicalA;
    else
        cri=criB; pmi=pmiB; logical=logicalB; basis=basisB; physical=physicalB;
    end
    currentCfg=localConfiguration(cfg,cri,pmi,retrySlot);
    requested=originalReplay.LastGrant;
    requested.Frame=2; requested.Slot=retrySlot;
    requested.ControlAbsoluteSlot=retrySlot-1;
    requested.HARQ=originalReplay.HARQ;
    requested.IsRetransmission=true;
    requested.GrantReason='harq_retx';
    requested.CRI=cri; requested.PMI=pmi; requested.AppliedPrecoderPMI=pmi;
    currentScheduler=sixgr.l2.mac.SchedulerPF(currentCfg,'Direction','DL');
    requested=currentScheduler.freezePHYGrantForGrant(requested,'ActiveConfig',currentCfg);
    % Check the scheduler boundary independently of runtime replay. A later
    % authored-DCI exception must not conceal an already mixed A-matrix /
    % B-QCL contract. Retain the exact failing scheduler result first.
    schedulerReceipt=struct('Scope',"declared_current_CSI_TCI_boundary_not_received_control", ...
        'Case',labels(k),'Grant',requested,'ExpectedLogicalPrecoder',logical, ...
        'ExpectedCSIBasis',basis,'ExpectedPhysicalPrecoder',physical);
    save(fullfile(folder,char(labels(k)+"_scheduler.mat")),'schedulerReceipt','-v7.3');
    localAssertSpatial(requested.PHYGrant,currentCfg,logical,basis,physical);
    requested.DCI=currentScheduler.buildDCIBitfield(requested,currentCfg);
    assert(requested.ExactPHYFeasible && requested.ScheduledAbsoluteSlot==retrySlot-1);
    authored=sixgr.phy.pdcch.decodeDCIPayload( ...
        requested.DCI.Bits,requested.DCI.Format,requested.DCI.ContextData);
    assert(authored.Fields.transmission_configuration_indication== ...
        currentCfg.phy.pdsch.qclTCI.codepoint);
    [~,context]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant( ...
        state,currentCfg,1,'DL',requested);
    assert(isequaln(context.GrantSnapshot.PHYGrant,requested.PHYGrant), ...
        'HARQ preparation must preserve the complete issued frozen PHY contract, not refreeze it.');
    context.PrepareOnly=true;
    job=sixgr.truth.GrantPreparation.buildJob(currentCfg,'DL',30,2,struct(),context);
    assert(job.PrepareOnly && isempty(fieldnames(job.ReceivedContext)));
    localAssertReplayIdentity(job,originalReplay,bits,retrySlot);
    localAssertSpatial(job.PHYGrant,currentCfg,logical,basis,physical);
    replayBoundary=struct('Case',labels(k),'CurrentRequestedGrant',requested, ...
        'ActualReplayPHYGrant',job.PHYGrant,'ActualReplayGrant',job.GrantSnapshot, ...
        'Scope',"actual_preparation_declared_control_boundary_no_reception");
    save(fullfile(folder,char(labels(k)+"_replay_boundary.mat")),'replayBoundary','-v7.3');
    assert(isequaln(job.PHYGrant.PrecodingState,requested.PHYGrant.PrecodingState) && ...
        isequaln(job.PHYGrant.ConfigurationAuthority.DLQCLTCIBinding, ...
            requested.PHYGrant.ConfigurationAuthority.DLQCLTCIBinding), ...
        'Runtime replay must preserve the scheduler current-attempt spatial/TCI authority.');
    proof=struct('Scope',"declared_control_boundaries_actual_native_TX_preparation", ...
        'Case',labels(k),'OriginalReceipt',originalReceipt, ...
        'RequestedGrant',requested,'ReplayGrant',job.GrantSnapshot, ...
        'ExpectedLogicalPrecoder',logical,'ExpectedCSIBasis',basis, ...
        'ExpectedPhysicalPrecoder',physical,'OriginalTBContext',originalReplay.TBContext, ...
        'PhysicalFeedbackExecuted',false,'ChannelExecuted',false,'ReceiverExecuted',false);
    path=fullfile(folder,char(labels(k)+".mat"));
    save(path,'proof','-v7.3');
    try
        % Exact TX leaf used by PrepareOnly, after the actual production
        % replay merge/buildJob. It invokes the authored-DCI/frozen-context
        % guard before LDPC/OFDM. No second fixture implementation of merge.
        [tx,info]=localTransmit(job.Cfg,job.GrantSnapshot,job.TransportBlockBits,job.RV);
    catch cause
        failure=struct('Identifier',string(cause.identifier),'Message',string(cause.message));
        save(path,'failure','-append');
        fprintf('HARQ_REPLAY_BEAM_TRANSITION_FAILURE case=%s id=%s artifact=%s\n', ...
            labels(k),string(cause.identifier),path);
        rethrow(cause); % Current defect must fail, never be accepted as PASS.
    end
    localAssertTX(tx,job.GrantSnapshot,bits,physical,retrySlot);
    localAssertSpatial(job.PHYGrant,currentCfg,logical,basis,physical);
    for field=["A","TBCRCType","BaseGraph","C","K","N","Zc", ...
            "FillerPositions","CombineSignature"]
        assert(isequaln(tx.CodingLayout.(field),originalReceipt.NativeCodingLayout.(field)), ...
            'The original TB coding/soft-combining operand %s must survive beam change.',field);
    end
    assert(isequaln(job.GrantSnapshot.DCI,requested.DCI), ...
        'Preparation must not silently reauthor the scheduled DCI to the old beam.');
    receipt=localReceipt(labels(k),job.Cfg,job.GrantSnapshot,tx,info);
    save(path,'receipt','-append');
    after=state.DLHarq.peekRetx(rnti,retrySlot);
    assert(isequaln(after,originalReplay), ...
        'Read-only retry preparation must not consume/mutate the original HARQ owner.');
    fprintf('HARQ_REPLAY_BEAM_TRANSITION_CASE_PASS case=%s tbs=%d rv=%d tci=%d\n', ...
        labels(k),numel(bits),job.RV,currentCfg.phy.pdsch.qclTCI.state_id);
end
ok=true;
fprintf('PASS testHARQReplayBeamTransitionPreparation: original plus two native TX preparations; no RX/RF/channel or received feedback claim.\n');
end

function cfg=localConfiguration(cfg,cri,pmi,slot)
cfg.phy.beamManagement.selectedCRI=cri; cfg.phy.csi.selectedCRI=cri;
cfg.phy.pdsch.PMI=pmi;
q=cfg.phy.pdsch.qclTCI;
q.state_id=cfg.phy.beamManagement.csiResourceToTCIStateIDs(cri+1);
q.codepoint=cfg.phy.beamManagement.csiResourceToTCICodepoints(cri+1);
q.spatial_source_resource_id=cfg.phy.csirs.resourceIDs(cri+1);
q.spatial_source_reference_signal='NZP-CSI-RS';
q.activation_absolute_slot0=slot-1;
q.initialization_source='declared_test_current_occasion_CSI_TCI_boundary';
cfg.phy.pdsch.qclTCI=q; cfg.phy.pdsch.activeTCIStateID=q.state_id;
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot,2);
end

function [tx,info]=localTransmit(cfg,grant,bits,rv)
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'ExecutionProfile','scheduler_truth', ...
    'PHYGrant',grant.PHYGrant,'SchedulerGrantContext',grant, ...
    'TransportBlockBits',int8(bits(:)),'RV',rv,'CompactOutput',false, ...
    'CellCommonSignalOwnershipMode','reserve_only');
end

function localAssertReplayIdentity(job,original,bits,slot)
g=job.GrantSnapshot; p=job.PHYGrant;
assert(isequal(int8(job.TransportBlockBits(:)),bits) && ...
    g.TBSBits==original.TBContext.TBSBits && ...
    p.CodingLayout.TBSBits==original.TBContext.TBSBits && ...
    g.HARQ.HarqID==original.HARQ.HarqID && ...
    g.HARQ.NDI==original.HARQ.NDI && g.HARQ.NDIEpoch==original.HARQ.NDIEpoch && ...
    g.HARQ.RV==original.HARQ.RV && job.RV==original.HARQ.RV && ...
    string(g.TransportBlockId)==string(original.LastGrant.TransportBlockId));
assert(isequal(g.PRBSet,original.LastGrant.PRBSet) && ...
    isequal(g.SymbolAllocation,original.LastGrant.SymbolAllocation) && ...
    g.NumLayers==original.LastGrant.NumLayers && g.MCS==original.LastGrant.MCS && ...
    g.Slot==slot && g.ScheduledAbsoluteSlot==slot-1);
for field=["TBSBits","Modulation","TargetCodeRate","DMRSPortSet"]
    assert(isequaln(p.CodingLayout.(field),original.LastGrant.PHYGrant.CodingLayout.(field)), ...
        'Changing beam must not change retained coding operand %s.',field);
end
end

function localAssertSpatial(phy,cfg,logical,basis,physical)
q=phy.ConfigurationAuthority.DLQCLTCIBinding;
assert(q.Available && q.ActiveTCIStateID==cfg.phy.pdsch.qclTCI.state_id && ...
    q.TCICodepoint==cfg.phy.pdsch.qclTCI.codepoint && ...
    q.SpatialSourceResourceID==cfg.phy.pdsch.qclTCI.spatial_source_resource_id);
localClose(phy.PrecodingState.MatrixLogicalPorts,logical,'logical PMI matrix');
localClose(phy.PrecodingState.HybridElementToPortMatrix,basis,'selected CSI basis');
localClose(phy.PrecodingState.MatrixPhysicalPorts,physical,'physical B(CRI)*W(PMI)');
end

function localAssertTX(tx,grant,bits,physical,slot)
assert(~isempty(tx.Waveform) && size(tx.Waveform,2)==64 && ...
    isequal(int8(tx.TransportBlock(:)),bits) && ...
    tx.Carrier.NFrame*tx.Carrier.SlotsPerFrame+tx.Carrier.NSlot==slot-1 && ...
    isequal(double(tx.PDSCH.PRBSet(:)),double(grant.PRBSet(:))) && ...
    isequal(double(tx.PDSCH.SymbolAllocation),double(grant.SymbolAllocation)) && ...
    tx.PDSCH.NumLayers==1 && isequal(double(tx.PDSCH.DMRS.DMRSPortSet),0));
localClose(tx.PDSCHAntennaSymbols,tx.PDSCHSymbols*physical.','actual data projection');
localClose(tx.DMRSAntennaSymbols,tx.DMRSSymbols*physical.','actual DMRS projection');
end

function localClose(actual,expected,label)
assert(isequal(size(actual),size(expected)) && ...
    norm(double(actual)-double(expected),'fro')<= ...
    128*eps*max(norm(double(expected),'fro'),realmin), ...
    'HARQ current-occasion %s must match the exact selected spatial operator.',label);
end

function r=localReceipt(label,cfg,grant,tx,info)
r=struct('Case',string(label),'Source',"original_native_TX_preparation", ...
    'AbsoluteSlot0',double(grant.ScheduledAbsoluteSlot), ...
    'TransportBlockSHA256',string(sixgr.util.sha256Hex(uint8(tx.TransportBlock(:)))), ...
    'WaveformSHA256',sixgr.phy.waveform.WaveformHash.runtimeArray(tx.Waveform), ...
    'PHYGrant',grant.PHYGrant,'DCI',grant.DCI,'Precoding',info.Precoding, ...
    'NativeCodingLayout',tx.CodingLayout, ...
    'ConfiguredQCL',cfg.phy.pdsch.qclTCI,'TBSBits',numel(tx.TransportBlock), ...
    'NativeDataProjectionChecked',true,'NativeDMRSProjectionChecked',true, ...
    'PhysicalFeedbackExecuted',false,'ChannelExecuted',false,'ReceiverExecuted',false);
end
