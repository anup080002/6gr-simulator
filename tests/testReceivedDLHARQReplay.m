function ok=testReceivedDLHARQReplay()
% Replay committed real captures; no newly generated transmission or channel.
setup6GRSimToolkit('Verbose',false);
root=fullfile('docs','lls','evidence_20260913','received_dl_harq');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
for k=1:4
    saved=load(fullfile(root,sprintf('attempt_%d.mat',k)));
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
    [rx,decision,after]=saved.before.receive(cfg,saved.a,saved.delayed, ...
        'TimingSearchWindowSamples',[0 60]);
    assert(isequaln(decision,saved.decision) && ...
        after.Processes{3}.Attempts==saved.entity.Processes{3}.Attempts);
    if k==3
        assert(isempty(rx) && ~decision.DecodeAttempted && ~decision.DeliverTransportBlock);
    else
        assert(rx.CRCPass==saved.rx.CRCPass && rx.TimingOffset==saved.rx.TimingOffset && ...
            isequal(rx.TransportBlock,saved.rx.TransportBlock));
        if k~=1, assert(isequal(rx.TransportBlock,saved.bits)); end
    end
    if k==2
        bad=rx.Assignment.toStruct(); bad.NominalReceivedMCSTargetCodeRate=.5;
        localReject(@()sixgr.pdsch.PDSCHSchedulingAssignment(bad), ...
            'sixgr:pdsch:ReceivedDLHARQRateDomainMismatch');
        bad=rx.Assignment.toStruct(); bad.HARQProcessId=1;
        localReject(@()sixgr.pdsch.PDSCHSchedulingAssignment(bad), ...
            'sixgr:pdsch:ReceivedDLHARQIdentityMismatch');
        bad=rx.Assignment.toStruct(); bad.RNTIType="CS-RNTI";
        localReject(@()sixgr.pdsch.PDSCHSchedulingAssignment(bad), ...
            'sixgr:pdsch:ReceivedDLHARQIdentityMismatch');
        localReject(@()sixgr.phy.dl.PDSCH_Rx(saved.delayed,cfg, ...
            'ReceiverHARQState',saved.before), ...
            'sixgr:pdsch:ReceivedDLHARQAssignmentRequired');
        % Existing raw soft-buffer prohibition is intact.
        localReject(@()sixgr.phy.dl.PDSCH_Rx(saved.delayed,cfg, ...
            'ExecutionProfile','connected_strict','Assignment',rx.Assignment, ...
            'ResourcePlan',rx.ResourcePlan,'Carrier',rx.Carrier, ...
            'ReferenceSignalConfig',rx.ReferenceConfig,'ReceiverConfig',rx.ReceiverConfig, ...
            'CodingPlan',rx.CodingPlans,'HARQSoftBufferLLR',saved.before.Processes{3}.SoftBuffer), ...
            'sixgr:pdsch:LegacyOverrideNotAllowed');
        disabled=cfg; disabled.phy.harq.enable=false;
        localReject(@()sixgr.link.ReceivedDLHARQState(disabled,1), ...
            'sixgr:link:ReceivedDLHARQDisabled');
        localReject(@()saved.before.receive(disabled,saved.a,saved.delayed), ...
            'sixgr:link:ReceivedDLHARQContextMismatch');
    end
    fprintf('RECEIVED_DL_HARQ_REPLAY_PASS sequence=%d ack=%d deliver=%d\n', ...
        k,decision.ACK,decision.DeliverTransportBlock);
end
fprintf('RECEIVED_DL_HARQ_REPLAY_GUARDS_PASS count=7\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
