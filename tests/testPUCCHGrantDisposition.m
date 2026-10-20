function ok = testPUCCHGrantDisposition()
%TESTPUCCHGRANTDISPOSITION Guard exact standalone/transfer/cancel semantics.

grants = table( ...
    ["g-transfer";"g-standalone";"g-cancel";"g-unresolved"], ...
    true(4,1), [false;true;false;false], [true;false;false;false], ...
    [true;false;false;false], [true;false;false;false], ...
    [true;false;false;false], [false;false;true;false], true(4,1), ...
    ["ctx-1";"";"";""], ...
    ["pusch_uci_feedback_applied";"standalone_pucch";"cancelled";"pending"], ...
    repmat("PASS",4,1), ...
    'VariableNames', {'PUCCHGrantId','GrantScheduledFlag','GrantExecutedFlag', ...
    'MultiplexedOnPUSCH','PUSCHUCIDecodeOk','UCIContentMatch', ...
    'RuntimeStateUpdated','CanceledAtSweepBoundary','FinalizedFlag', ...
    'PUSCHGrantContextId','PUCCHGrantState','Status'});
trials = table("g-standalone", true, true, true, true, true, false, false, ...
    'VariableNames', {'PUCCHGrantId','DetectionAttempted','DetectionUsable', ...
    'ReceiverUsable','PUCCHDecodeOk','UCIContentMatch','CRCApplicable','CRCPass'});

result = sixgr.truth.classifyPUCCHGrantDisposition(grants, trials);
assert(result.ScheduledCount == 4 && result.TransferredCount == 1 && ...
    result.StandaloneTrialCount == 1 && result.CancelledCount == 1 && ...
    result.UnresolvedCount == 1 && ~result.AllScheduledResolved, ...
    "Grant disposition must distinguish transfer, standalone decode, cancellation, and unresolved rows.");
assert(string(result.Rows.Disposition(1)) == "same_waveform_pusch_uci_decode_consumed" && ...
    string(result.Rows.Disposition(2)) == "matched_standalone_pucch_receiver_trial_success" && ...
    string(result.Rows.Disposition(3)) == "explicitly_finalized_cancellation", ...
    "Resolved feedback grants must preserve their exact causal disposition.");

allResolved = grants(1:3,:);
result = sixgr.truth.classifyPUCCHGrantDisposition(allResolved, trials);
assert(result.AllScheduledResolved && result.UnresolvedCount == 0, ...
    "A valid UCI-on-PUSCH transfer must not require a fake standalone PUCCH trial.");

badTransfer = grants(1,:);
badTransfer.PUSCHUCIDecodeOk = false;
result = sixgr.truth.classifyPUCCHGrantDisposition(badTransfer, table());
assert(~result.AllScheduledResolved && result.UnresolvedCount == 1, ...
    "A transfer reservation without receiver decode must fail closed.");

failedTrial=trials;
failedTrial.PUCCHGrantId="g-unresolved";
failedTrial.DetectionUsable=false;
failedTrial.DetectionAttempted=false;
failedResult=sixgr.truth.classifyPUCCHGrantDisposition(grants(4,:),failedTrial);
assert(failedResult.AllScheduledResolved && failedResult.UnresolvedCount==0 && ...
    failedResult.StandaloneObservedCount==1 && failedResult.StandaloneFailedCount==1 && ...
    failedResult.StandaloneTrialCount==0 && ...
    failedResult.Rows.StandalonePUCCHTrialObserved && ...
    failedResult.Rows.StandalonePUCCHTrialFailed && ...
    string(failedResult.Rows.Disposition)=="matched_standalone_pucch_receiver_trial_failed", ...
    ['An existing failed receiver trial, including a pre-detection failure, must retain its physical failure ' ...
     'disposition and must not be mislabeled as a missing trial row.']);

bundledGrants = grants(2:3,:);
bundledGrants.PUCCHGrantId = ["g-bundle-1";"g-bundle-2"];
bundledGrants.GrantExecutedFlag(:) = true;
bundledGrants.CanceledAtSweepBoundary(:) = false;
bundledGrants.PUCCHGrantState(:) = "waveform_observed_feedback_applied";
bundledTrials = trials;
bundledTrials.PUCCHGrantId = "pucchoccasion:due=14:ue=1";
bundledTrials.LogicalPUCCHGrantIdSet = "g-bundle-1|g-bundle-2|CSI:REPORT-1";
result = sixgr.truth.classifyPUCCHGrantDisposition(bundledGrants, bundledTrials);
assert(result.AllScheduledResolved && result.StandaloneTrialCount == 2 && ...
    all(result.Rows.StandalonePUCCHTrialMatched), ...
    ['A successfully decoded physical PUCCH occasion must resolve every ' ...
     'logical HARQ-ACK grant explicitly listed in its codebook identity set.']);

% Exact IDs are necessary but insufficient if independently exported UE,
% carrier/BWP or occasion fields contradict them. Test physical and bundled
% logical IDs, including a failed trial that must remain observed correctly.
for field=["UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"]
    goodGrants=bundledGrants; goodTrials=bundledTrials;
    goodGrants.(field)=ones(2,1); goodTrials.(field)=1;
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,goodTrials);
    assert(result.AllScheduledResolved && result.StandaloneTrialCount==2);
    wrong=goodTrials; wrong.(field)=2;
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,wrong);
    assert(result.UnresolvedCount==2 && result.StandaloneObservedCount==0, ...
        'A matching ID must not override inconsistent %s evidence.',field);
    wrong.(field)=NaN;
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,wrong);
    assert(result.UnresolvedCount==2,'Unknown identity cannot credit a received occasion.');
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,bundledTrials);
    assert(result.UnresolvedCount==2,'Missing independent identity cannot match.');
    % A wrong-UE success must not mask a same-UE physical failure.
    failed=goodTrials; failed.PUCCHDecodeOk=false;
    wrong=goodTrials; wrong.(field)=2;
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,[wrong;failed]);
    assert(result.StandaloneFailedCount==2 && result.StandaloneTrialCount==0 && ...
        result.AllScheduledResolved);
end
for field=["RunUUID","ConfigHash"]
    goodGrants=bundledGrants; goodTrials=bundledTrials;
    goodGrants.(field)=repmat("same",2,1); goodTrials.(field)="same";
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,goodTrials);
    assert(result.AllScheduledResolved);
    goodTrials.(field)="other";
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,goodTrials);
    assert(result.UnresolvedCount==2,'Never join different run/config identities.');
    goodTrials.(field)="";
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,goodTrials);
    assert(result.UnresolvedCount==2,'An empty identity cannot match a known run/config.');
    goodGrants.(field)(:)="";
    result=sixgr.truth.classifyPUCCHGrantDisposition(goodGrants,goodTrials);
    assert(result.AllScheduledResolved,'Legacy ID-only component provenance remains readable.');
end
unfinalized=bundledTrials; unfinalized.FinalizedFlag=false;
result=sixgr.truth.classifyPUCCHGrantDisposition(bundledGrants,unfinalized);
assert(result.UnresolvedCount==2,'An unfinished receiver row is not a disposition.');
for field=["Placeholder","PlaceholderFlag","Fallback","FallbackFlag"]
    proxy=bundledTrials; proxy.(field)=true;
    result=sixgr.truth.classifyPUCCHGrantDisposition(bundledGrants,proxy);
    assert(result.UnresolvedCount==2,'Neither alias may credit nonphysical feedback.');
end
proxy=bundledTrials; proxy.ApproximationMode="fast_proxy";
result=sixgr.truth.classifyPUCCHGrantDisposition(bundledGrants,proxy);
assert(result.UnresolvedCount==2,'Proxy evidence cannot close physical feedback grants.');

terminal = grants(4,:);
terminal.RightCensored = true;
terminal.CensorReason = "finite_runtime_horizon_reached";
terminal.Status = "RIGHT_CENSORED";
result = sixgr.truth.classifyPUCCHGrantDisposition(terminal, table());
assert(result.AllScheduledResolved && result.RightCensoredCount == 1 && ...
    string(result.Rows.Disposition) == "explicitly_finalized_right_censoring", ...
    ['A scheduled feedback occasion beyond the finite execution horizon ' ...
     'must be resolved by its explicit finalized right-censoring record.']);

terminal.FinalizedFlag = false;
result = sixgr.truth.classifyPUCCHGrantDisposition(terminal, table());
assert(~result.AllScheduledResolved && result.UnresolvedCount == 1, ...
    "An unfinalized right-censor marker must fail closed.");
ok = true;
end
