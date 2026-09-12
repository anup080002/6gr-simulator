function ok=testReceivedDLRetainedACK(outputRoot)
% Real archived coded receptions qualify the UE protocol transition only.
% This is not evidence of shared scheduler/PUCCH execution or current CRC.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve previous evidence.');
setup6GRSimToolkit('Verbose',false);
root=fullfile('docs','lls','evidence_20260913','received_dl_harq');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
rows=table();
for k=1:4
    saved=load(fullfile(root,sprintf('attempt_%d.mat',k)));
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
    before=saved.before;
    assert(before.requiresDecode(cfg,saved.a)==(k~=3));
    if k~=3
        localReject(@()before.acknowledgeRetained(cfg,saved.a), ...
            'sixgr:link:ReceivedDLRetainedACKUnavailable');
        localReject(@()before.receive(cfg,saved.a,[]), ...
            'sixgr:link:ReceivedDLWaveformRequired');
        continue;
    end
    [decision,after,protocol]=before.acknowledgeRetained(cfg,saved.a);
    [rx,viaReceive,afterReceive,viaReceiveProtocol]=before.receive(cfg,saved.a,[]);
    assert(isempty(rx) && isequaln(decision,saved.decision) && ...
        isequaln(decision,viaReceive) && isequaln(protocol,viaReceiveProtocol));
    index=saved.a.HARQProcess+1;
    prior=before.Processes{index}; current=after.Processes{index};
    assert(isequaln(current,afterReceive.Processes{index}));
    assert(current.Attempts==prior.Attempts+1 && ...
        before.Processes{index}.Attempts==prior.Attempts && ...
        current.LastAssignmentDigest==saved.a.AssignmentDigest && ...
        isequal(current.SoftBuffer,prior.SoftBuffer) && ...
        current.HARQKey==prior.HARQKey && ...
        current.History.InitialAssignment.AssignmentDigest== ...
        prior.History.InitialAssignment.AssignmentDigest);
    other=setdiff(1:numel(before.Processes),index);
    assert(isequaln(before.Processes(other),after.Processes(other)));
    assert(protocol.ACK && ~protocol.DecodeAttempted && ...
        ~protocol.DeliverTransportBlock && ~protocol.FeedbackTransmissionQualified && ...
        protocol.PriorAcknowledgedAssignmentDigest==prior.LastAssignmentDigest && ...
        protocol.RetainedTBSBits==prior.History.TBSBits && ...
        protocol.ControlAbsoluteSlot==saved.a.ControlAbsoluteSlot && ...
        protocol.DataAbsoluteSlot==saved.a.DataAbsoluteSlot);
    assert(~any(isfield(protocol,{'CRCPass','SINR_dB','EVM_pct','TimingOffsetSamples', ...
        'DataDecodeAvailableAtSample','TransportBlock','DecodedBits'})));
    localReject(@()after.acknowledgeRetained(cfg,saved.a), ...
        'sixgr:link:ReceivedDLHARQNoncausalAssignment');
    localReject(@()after.requiresDecode(cfg,saved.a), ...
        'sixgr:link:ReceivedDLHARQNoncausalAssignment');
    disabled=cfg; disabled.phy.harq.enable=false;
    localReject(@()before.acknowledgeRetained(disabled,saved.a), ...
        'sixgr:link:ReceivedDLHARQContextMismatch');
    localRejectAny(@()before.receive(cfg,saved.a,[],'NoiseVariance',1));
    corrupted=saved.a; corrupted.NDI=~corrupted.NDI;
    localReject(@()before.acknowledgeRetained(cfg,corrupted), ...
        'sixgr:phy:pdcch:ReceivedAssignmentDigestMismatch');
    rows=struct2table(protocol,'AsArray',true);
end
mkdir(outputRoot);
sixgr.util.csvWriteTable(fullfile(outputRoot,'received_dl_protocol_decisions.csv'),rows,'PreserveSchema',true);
fprintf('RECEIVED_DL_RETAINED_ACK_PASS actual_archived_sequence=3 no_IQ_required=1 no_new_PHY_row=1 guards=11 folder=%s\n',outputRoot);
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end

function localRejectAny(fn)
try, fn(); catch, return; end
error('test:MissingRejection','Invalid receiver input must be rejected.');
end
