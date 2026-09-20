function ok=testSharedAWGNTRSReceiveCompletion()
% Four-port shared AWGN receiver regression, not full access/data acceptance.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
root=fullfile(pwd,'results','lls','shared_awgn_trs_completion', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),9);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
p=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',8);
owner.queueDownlink("TRS",1,p,struct('Config',dl,'Slot',8));
seen=false;
for slot=1:9
    state.CurrentSlot=slot;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    [state,items]=owner.advanceSlot(state,current);
    for item=items
        if item.Kind~="TRS", continue; end
        assert(~seen); seen=true;
        p=item.Context.Prepared;
        [~,~,~,replay,observation]=sixgr.truth.sharedObservationEvidence(item.Planes);
        [~,~,captures]=sixgr.truth.sharedLinkScoringObservation( ...
            item.Planes,p,item.Context.DesiredReferencePlane);
        before=owner.Events.NextSampleIndex;
        ch=owner.directionalChannelState(1,"DL");
        out=sixgr.link.completeTRSReception(p,observation,replay,ch, ...
            'ScoringChannelReferences',captures);
        receivedWaveform=observation.readComplete();
        save(fullfile(root,'received_trs.mat'),'p','replay','ch','captures', ...
            'out','receivedWaveform','-v7.3');
        fprintf('SHARED_AWGN_TRS_CAPTURE=%s\n',root);
        assert(~out.Crash,'%s',out.FailureReason);
        assert(out.ObservationStartSample==observation.StartSample && ...
            out.ObservationEndSampleExclusive==observation.EndSampleExclusive && ...
            out.ObservationSampleRateHz==observation.SampleRateHz && ...
            out.ObservationCompletionTime_s==observation.EndSampleExclusive/observation.SampleRateHz);
        assert(owner.Events.NextSampleIndex==before,'Receiver must not advance the channel.');
        assert(out.DetectionAttempted && out.TRSRuntimeEvidenceUsable && ...
            out.NMSEScoringAvailable && out.StrictOk,'%s',out.FailureReason);
    end
end
assert(seen && ~owner.hasPending("TRS",1));
fprintf('SHARED_AWGN_TRS_RECEIVE_COMPLETION_PASS\n');
ok=true;
end
