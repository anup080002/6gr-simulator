function ok=testReceivedDLCombiningEvidence()
% Actual capture replay: exports must project, not recompute, HARQ soft state.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
for k=[1 2 4]
    saved=load(fullfile('docs','lls','evidence_20260913','received_dl_harq_calendar_02',sprintf('attempt_%d.mat',k)));
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
    [rx,decision]=saved.before.receive(cfg,saved.a,saved.delayed,'TimingSearchWindowSamples',[0 60]);
    [combined,e]=sixgr.link.receivedDLHARQCombiningEvidence(rx);
    assert(isequaln(combined,rx.Decode.HARQCombinedLLR) && ...
        isequaln(e.SoftBuffer,rx.Decode.SoftBuffer));
    assert(e.CombiningApplied==(k==2) && e.CurrentLLRCount==numel(rx.RecLLR));
    assert(decision.ACK==saved.decision.ACK && ...
        isequaln(e.LLRCombiningGain_dB,rx.Decode.HARQCombineInfo.LLRCombiningGain_dB));
    bad=rx; bad.HARQCombinedLLR(1)=bad.HARQCombinedLLR(1)+1;
    localReject(@()sixgr.link.receivedDLHARQCombiningEvidence(bad),'sixgr:link:ReceivedDLHARQEvidenceMismatch');
    bad=rx; bad.SchedulingOwnership="scheduler_tx_plan";
    localReject(@()sixgr.link.receivedDLHARQCombiningEvidence(bad),'sixgr:link:ReceivedDLHARQEvidenceAuthority');
    fprintf('RECEIVED_DL_COMBINING_EVIDENCE_PASS attempt=%d prior=%d current=%d combined=%d\n', ...
        k,e.PreviousLLRCount,e.CurrentLLRCount,e.CombinedLLRCount);
end
ok=true;
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s.',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
