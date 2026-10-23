function ok=testULHARQReceiverScopeBeamContinuity(outputRoot)
% Actual isolated PDCCH TX/RX plus a DECLARED gNB soft-state contract.
% No shared PUSCH capture, physical gNB command receipt, or PUSCH decode is
% fabricated. The process/NDI/TB buffer below is declared test state. This
% reproduces the installed-key/scope seam, not a scheduled HARQ RF campaign.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname(fullfile(pwd,'logs')); end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier receiver-scope evidence.');
mkdir(outputRoot);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
scope="actual_isolated_PDCCH_decode_declared_gNB_buffer_and_clocks_no_PUSCH_capture";
runtimeVersion=version; toolboxVersions=ver;
assert(installed.phy.pdsch.qclTCI.enabled && installed.phy.harq.nProcesses>3);

% Use the existing received-UL beam-change fixture's legal connected layout.
% Only ActiveTCIStateID changes in the installed DCI context; the runtime
% slot progresses and the second actual command carries RV2, same NDI/TB.
cfgA=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,31);
cfgB=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,41);
cfgA.phy.pdsch.qclTCI.state_id=17;
cfgB.phy.pdsch.qclTCI.state_id=18;
contextA=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfgA,'0_1');
contextB=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfgB,'0_1');
semanticA=sixgr.phy.pdcch.harqContextDigest(contextA);
semanticB=sixgr.phy.pdcch.harqContextDigest(contextB);
assert(contextA.Digest~=contextB.Digest && semanticA==semanticB && ...
    isequaln(rmfield(contextA.Data,'ActiveTCIStateID'), ...
        rmfield(contextB.Data,'ActiveTCIStateID')));
fields=localFields(contextA,cfgA);
[grantA,packedA]=localGrant(cfgA,fields,1);
fieldsB=fields; fieldsB.rv=2;
[grantB,packedB]=localGrant(cfgB,fieldsB,1);
controlA=localReceiveControl(cfgA,packedA);
controlB=localReceiveControl(cfgB,packedB);
a=controlA.Assignment; b=controlB.Assignment;
assert(a.ContextDigest==contextA.Digest && b.ContextDigest==contextB.Digest && ...
    a.HARQProcess==b.HARQProcess && a.NDI==b.NDI && a.RV==0 && b.RV==2 && ...
    a.ControlAbsoluteSlot<b.ControlAbsoluteSlot && a.DataAbsoluteSlot<b.DataAbsoluteSlot);
[keyA,identityA]=sixgr.truth.scheduledULHARQReceiverKey(cfgA,grantA);
[keyB,identityB]=sixgr.truth.scheduledULHARQReceiverKey(cfgB,grantB);
attemptA=localAttempt(keyA,identityA,a,controlA,1);
attemptB=localAttempt(keyB,identityB,b,controlB,2);

% A canonical-shaped, explicitly DECLARED retained mother-code buffer.
% It is not produced by the isolated PDCCH receiver and is never represented
% as PUSCH IQ, a measured decoder failure, or a transmitted payload oracle.
declaredTB=int8(mod((1:512).',2));
layout=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
    'TransportBlockSize',numel(declaredTB),'TargetCodeRate',.3,'RV',0, ...
    'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',3600);
declaredLLR=ones(double(layout.MotherCodeLength),double(layout.NumCodeBlocks));
[~,combineInfo]=sixgr.phy.harq.combineSoftLLR(declaredLLR,[], ...
    'CurrentLayout',layout,'HARQKey',keyA,'CodewordIndex',1);
soft=combineInfo.SoftBuffer;
[~,priorA,tokenA]=sixgr.truth.resolveULHARQReceiverState({},attemptA);
assert(isempty(priorA));
declaredDecision=struct('ReceiverAttempt',tokenA,'DecodeAttempted',true, ...
    'CRCPass',false,'SoftBuffer',soft);
records=sixgr.truth.resolveULHARQReceiverState({},attemptA,declaredDecision);
[unchanged,priorB,tokenB]=sixgr.truth.resolveULHARQReceiverState(records,attemptB);
assert(isequaln(unchanged,records));

% Control: RV changes do not make a new retained TB even before the fix.
[rvGrant,~]=localGrant(cfgA,fieldsB,1);
[rvKey,rvIdentity]=sixgr.truth.scheduledULHARQReceiverKey(cfgA,rvGrant);
rvAttempt=localAttempt(rvKey,rvIdentity,b,controlB,3);
[~,rvPrior]=sixgr.truth.resolveULHARQReceiverState(records,rvAttempt);
assert(rvKey==keyA && isequaln(rvPrior,soft));

% Fresh-command full-context validation must remain strict even though the
% lifetime HARQ context excludes active TCI. Replaying the old command into
% the new beam installation is not the valid same-TB continuation above.
localReject(@()sixgr.truth.scheduledULHARQReceiverKey(cfgB,grantA), ...
    'sixgr:truth:ULHARQReceiverContextMismatch');
bad=grantA; bad.RNTI=bad.RNTI+1;
localReject(@()sixgr.truth.scheduledULHARQReceiverKey(cfgA,bad), ...
    'sixgr:truth:ULHARQReceiverContextMismatch');
bad=grantA; bad.HARQ.HarqID=bad.HARQ.HarqID+1;
localReject(@()sixgr.truth.scheduledULHARQReceiverKey(cfgA,bad), ...
    'sixgr:truth:ULHARQReceiverWireIdentityMismatch');
bad=grantA; bad.HARQ.NDI=~bad.HARQ.NDI;
localReject(@()sixgr.truth.scheduledULHARQReceiverKey(cfgA,bad), ...
    'sixgr:truth:ULHARQReceiverWireIdentityMismatch');

% Legitimate different process, RNTI, NDI epoch, or installed configuration
% must not gain access to the declared prior from the original process.
newFields=fieldsB; newFields.harq_process=3;
[processGrant,~]=localGrant(cfgA,newFields,1);
[processKey,processIdentity]=sixgr.truth.scheduledULHARQReceiverKey(cfgA,processGrant);
processAttempt=localAttempt(processKey,processIdentity,b,controlB,4);
[~,processPrior]=sixgr.truth.resolveULHARQReceiverState(records,processAttempt);
assert(processKey~=keyA && isempty(processPrior));

rntiCfg=cfgA; rntiCfg.phy.pdsch.RNTI=rntiCfg.phy.pdsch.RNTI+1;
rntiCfg.phy.pusch.RNTI=rntiCfg.phy.pdsch.RNTI;
[rntiGrant,~]=localGrant(rntiCfg,fieldsB,1);
[rntiKey,rntiIdentity]=sixgr.truth.scheduledULHARQReceiverKey(rntiCfg,rntiGrant);
rntiAttempt=localAttempt(rntiKey,rntiIdentity,b,controlB,5);
[~,rntiPrior]=sixgr.truth.resolveULHARQReceiverState(records,rntiAttempt);
assert(rntiKey~=keyA && isempty(rntiPrior));

newFields=fieldsB; newFields.ndi=0;
[ndiGrant,~]=localGrant(cfgA,newFields,2);
[ndiKey,ndiIdentity]=sixgr.truth.scheduledULHARQReceiverKey(cfgA,ndiGrant);
ndiAttempt=localAttempt(ndiKey,ndiIdentity,b,controlB,6);
[~,ndiPrior,ndiToken]=sixgr.truth.resolveULHARQReceiverState(records,ndiAttempt);
assert(ndiKey~=keyA && isempty(ndiPrior));
newEpoch=sixgr.truth.resolveULHARQReceiverState(records,ndiAttempt, ...
    struct('ReceiverAttempt',ndiToken,'DecodeAttempted',false,'CRCPass',false,'SoftBuffer',[]));
stale=rvAttempt; stale.DataAbsoluteSlot=stale.DataAbsoluteSlot+10;
stale.StartSample=stale.StartSample+100; stale.EndSampleExclusive=stale.EndSampleExclusive+100;
stale.AvailableAtSample=stale.EndSampleExclusive;
localReject(@()sixgr.truth.resolveULHARQReceiverState(newEpoch,stale), ...
    'sixgr:truth:StaleULHARQReceiverEpoch');

epochCfg=cfgA;
epochCfg.phy.pdcch.operatorControl.connected_dci.configuration_epoch= ...
    contextA.Data.ConfigurationEpoch+1;
epochCfg.phy.pdsch.qclTCI.configuration_epoch=contextA.Data.ConfigurationEpoch+1;
[epochGrant,~]=localGrant(epochCfg,fieldsB,1);
[epochKey,epochIdentity]=sixgr.truth.scheduledULHARQReceiverKey(epochCfg,epochGrant);
epochAttempt=localAttempt(epochKey,epochIdentity,b,controlB,7);
[~,epochPrior]=sixgr.truth.resolveULHARQReceiverState(records,epochAttempt);
epochContext=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(epochCfg,'0_1');
assert(epochKey~=keyA && isempty(epochPrior) && ...
    sixgr.phy.pdcch.harqContextDigest(epochContext)~=semanticA);
localReject(@()sixgr.truth.scheduledULHARQReceiverKey(epochCfg,grantA), ...
    'sixgr:truth:ULHARQReceiverContextMismatch');
invalidCfg=cfgA; invalidCfg.phy.pusch.RNTI=invalidCfg.phy.pusch.RNTI+1;
localReject(@()sixgr.truth.scheduledULHARQReceiverKey(invalidCfg,grantA), ...
    'sixgr:phy:pdcch:ConnectedRuntimeMismatch');

comparison=struct('FullContextDigestA',contextA.Digest,'FullContextDigestB',contextB.Digest, ...
    'HARQContextDigestA',semanticA,'HARQContextDigestB',semanticB, ...
    'ReceiverKeyA',keyA,'ReceiverKeyB',keyB,'ScopeKeyA',attemptA.ScopeKey, ...
    'ScopeKeyB',attemptB.ScopeKey,'BeamChangePriorRetained',isequaln(priorB,soft), ...
    'RVOnlyPriorRetained',isequaln(rvPrior,soft),'PUSCHCaptureExecuted',false, ...
    'ReceiverSoftStateSource',"declared_contract_fixture_not_PUSCH_decode");
save(fullfile(outputRoot,'ul_harq_beam_scope.mat'),'scope','installed','cfgA','cfgB', ...
    'contextA','contextB','grantA','grantB','controlA','controlB','identityA','identityB', ...
    'declaredTB','layout','declaredLLR','soft','records','attemptA','attemptB', ...
    'priorB','tokenB','comparison','rvPrior','processPrior','rntiPrior','ndiPrior','epochPrior', ...
    'runtimeVersion','toolboxVersions');
fprintf('UL_HARQ_BEAM_SCOPE same_semantic_context=%d same_receiver_key=%d same_scope=%d retained_prior=%d evidence=%s\n', ...
    semanticA==semanticB,keyA==keyB,attemptA.ScopeKey==attemptB.ScopeKey, ...
    comparison.BeamChangePriorRetained,outputRoot);
assert(keyA==keyB && attemptA.ScopeKey==attemptB.ScopeKey && isequaln(priorB,soft), ...
    'sixgr:test:ULHARQBeamScopeDiscontinuity', ...
    'Active-TCI-only installation changed the same-TB receiver scope or dropped prior; evidence: %s',outputRoot);
ok=true;
end

function fields=localFields(context,cfg)
defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
fields=struct(); for d=defs(:).', fields.(d.Name)=d.ValueMin; end
fields.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*(6-1)+3;
fields.mcs=10; fields.rv=0; fields.ndi=1; fields.harq_process=2;
fields.antenna_ports=3; fields.precoding_information_and_number_of_layers=3;
fields.dmrs_sequence_initialization=1;
end

function [grant,packed]=localGrant(cfg,fields,epoch)
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
% This is the key function's installed command contract, not a scheduled
% frozen PHY grant or a claim of actual transmitted PUSCH authorization.
grant=struct('Direction','UL','UEIndex',1,'ServingCell',1,'RNTI',context.Data.RNTIValue, ...
    'HARQ',struct('HarqID',fields.harq_process,'NDI',logical(fields.ndi), ...
        'NDIEpoch',epoch,'RV',fields.rv), ...
    'DCI',struct('Bits',packed.Bits,'ContextData',context.Data));
end

function result=localReceiveControl(cfg,packed)
tx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits,'RNTI',cfg.phy.pdsch.RNTI);
[rx,rxInfo]=sixgr.phy.dl.PDCCH_Rx(tx.TransmitSamples,cfg,'SampleRate_Hz',tx.SampleRateHz);
assignment=sixgr.phy.pdcch.materializeConnectedDCI(rx,rxInfo,cfg);
assert(rx.Ok && rx.ErrFlag==0 && isequal(rx.DCIBits,packed.Bits) && ...
    assignment.PayloadHash==packed.PayloadHash);
result=struct('Assignment',assignment,'Receiver',rx,'ReceiverInfo',rxInfo, ...
    'TransmitSamples',tx.TransmitSamples,'SampleRateHz',tx.SampleRateHz, ...
    'WaveformSHA256',sixgr.phy.waveform.WaveformHash.numeric(tx.TransmitSamples), ...
    'Scope',"actual_isolated_control_decode_not_shared_command_receipt");
end

function attempt=localAttempt(key,identity,assignment,control,ordinal)
% Mirror prepareSharedULHARQReception's scope projection, but do not claim
% that helper ran: no physical owner/command receipt/capture is supplied.
processIdentity=rmfield(identity,{'NDI','NDIEpoch'});
attempt=struct('ScopeKey',"gNB-UL-process-"+sixgr.phy.pucch.PUCCHUtil.hash(processIdentity), ...
    'ReceiverKey',key,'NDIEpoch',identity.NDIEpoch, ...
    'DataAbsoluteSlot',assignment.DataAbsoluteSlot,'ObservationID',"declared-PUSCH-rx-"+ordinal, ...
    'GrantContextID',"declared-grant-"+ordinal, ...
    'CommandObservationID',"declared-reducer-command-"+ordinal, ...
    'StartSample',1000*ordinal,'EndSampleExclusive',1000*ordinal+100, ...
    'SampleRateHz',control.SampleRateHz,'AvailableAtSample',1000*ordinal+100);
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
