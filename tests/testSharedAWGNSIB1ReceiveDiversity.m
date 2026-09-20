function ok=testSharedAWGNSIB1ReceiveDiversity()
% Real four-branch shared AWGN capture; no precombined RX or oracle channel.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
root=fullfile(pwd,'results','lls','shared_awgn_sib1_diversity', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root); cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),6);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',0);
p=prototype.PreparedBroadcast;
owner.queueDownlink("PBCH",1,p,struct('Config',dl,'Slot',1));
seen=false;
for slot=1:6
    state.CurrentSlot=slot;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    [state,items]=owner.advanceSlot(state,current);
    for item=items
        if item.Kind~="PBCH", continue; end
        assert(~seen); seen=true;
        p=item.Context.Prepared;
        [~,~,~,replay,observation]=sixgr.truth.sharedObservationEvidence(item.Planes);
        assert(observation.NumReceiveAntennas==4);
        before=owner.Events.NextSampleIndex;
        receivedWaveform=observation.readComplete();
        rx=sixgr.phy.broadcast.recoverSIB1FromWaveform(observation, ...
            p.ReceiverConfig,'CandidateSSBIndex',0);
        save(fullfile(root,'received_sib1.mat'),'p','replay','receivedWaveform','rx','-v7.3');
        fprintf('SHARED_AWGN_SIB1_CAPTURE=%s\n',root);
        assert(rx.BCHCrcPass && rx.MIBDecoded && rx.DCICrcPass && ...
            rx.DLSCHCrcPass && rx.SIB1ASN1DecodeOk && rx.StrictOk,'%s',rx.FailureReason);
        assert(rx.SIB1PDSCHStrictReceiverEvidenceOk);
        assert(owner.Events.NextSampleIndex==before,'Receiver must not advance the channel.');
    end
end
assert(seen && ~owner.hasPending("PBCH",1));
fprintf('SHARED_AWGN_SIB1_RECEIVE_DIVERSITY_PASS\n');
ok=true;
end
