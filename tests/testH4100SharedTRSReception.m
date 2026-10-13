function ok=testH4100SharedTRSReception()
% Exact configured H4 RF/CDL TRS on the production shared sample clock.
% One TRS occasion only: not access, data, or scenario acceptance.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
folder=fullfile(pwd,'results','lls','h4_shared_trs', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(source,folder);
cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),40);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
carrier=sixgr.phy.grid.makeCarrier(dl);
assert(carrier.NSizeGrid==273 && carrier.SubcarrierSpacing==30 && ...
    dl.phy.fc_Hz==4e9 && dl.phy.nTxAnt==64 && dl.phy.nRxAnt==4 && ...
    owner.SampleRateHz==122.88e6);
% Resolve the installed calendar rather than repeating a legacy fixture's
% slot number in a full-band test.
firstSlot=NaN;
for candidate=1:cfg.phy.trs.period_slots
    window=sixgr.truth.resolveTRSObservationWindow(dl,candidate);
    if window.ObservationStarts, firstSlot=candidate; break; end
end
assert(isfinite(firstSlot));
lastSlot=max(window.AbsoluteSlotNumbers)+1;
prepared=sixgr.link.prepareTRSTransmission(dl,40,'RuntimeSlot',firstSlot);
owner.queueDownlink("TRS",1,prepared,struct('Config',dl,'Slot',firstSlot));
scope=struct('Scope',"exact_H4_shared_TRS_single_occasion_no_access_or_data", ...
    'ScenarioAccepted',false,'StatisticallyQualified',false,'SourceScenario',string(source.ConfigPath));
save(fullfile(folder,'configuration.mat'),'cfg','scope');
fprintf('H4_SHARED_TRS_ROOT=%s\n',folder);
seen=false;
for slot=1:lastSlot
    state.CurrentSlot=slot;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    [state,items]=owner.advanceSlot(state,current);
    fprintf('H4_SHARED_TRS_SLOT=%d/%d\n',slot,lastSlot);
    for item=items
        assert(item.Kind=="TRS" && ~seen,'Only the configured TRS receiver may complete.');
        seen=true;
        prepared=item.Context.Prepared;
        [~,~,~,replay,received]=sixgr.truth.sharedObservationEvidence(item.Planes);
        replay.PowerContext=prepared.PowerContext;
        [reference,referenceSource,captures]=sixgr.truth.sharedLinkScoringObservation( ...
            item.Planes,prepared,item.Context.DesiredReferencePlane);
        assert(isempty(captures),'TRS scoring must not run a second channel.');
        receivedWaveform=received.readComplete(); referenceWaveform=reference.readComplete();
        receivedStartSample=received.StartSample; referenceStartSample=reference.StartSample;
        % Save actual samples and executed RF metadata before receiver work,
        % so a failed receiver/scoring case remains independently replayable.
        save(fullfile(folder,'received.mat'),'prepared','replay','receivedWaveform', ...
            'referenceWaveform','receivedStartSample','referenceStartSample','referenceSource','scope','-v7.3');
        before=owner.Events.NextSampleIndex;
        out=sixgr.link.completeTRSReception(prepared,received,replay, ...
            owner.directionalChannelState(1,"DL"),'DesiredReferenceObservation',reference);
        save(fullfile(folder,'result.mat'),'out','scope','-v7.3');
        row=table(slot,out.Crash,out.Ok,out.NMSE_dB,out.NMSEScoringAvailable, ...
            string(out.ChannelNMSEReferencePlane),false,false, ...
            'VariableNames',{'CompletionSlot','Crash','StrictOk','NMSE_dB','NMSEScoringAvailable', ...
            'ChannelReferencePlane','ScenarioAccepted','StatisticallyQualified'});
        writetable(row,fullfile(folder,'trs_result.csv'));
        disp(row);
        assert(before==owner.Events.NextSampleIndex,'Scoring must not advance the channel/RF clock.');
        assert(~out.Crash && out.NMSEScoringAvailable && out.Ok, ...
            'sixgr:test:H4SharedTRSQualificationFailed', ...
            'Exact impaired H4 TRS failed: NMSE=%g dB. Retained evidence: %s',out.NMSE_dB,folder);
    end
end
assert(seen && ~owner.hasPending("TRS",1));
ok=true;
end
