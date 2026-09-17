function ok=testResearchHARQRunner()
% End-to-end research runner accounting, without final-scenario assumptions.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
config=fullfile(pwd,'tests','fixtures','research_ideal_harq_runner.yaml');
root=fullfile(pwd,'results','component_validation');
tag="ideal_harq_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
out=run_6g_phy_lls_single(config,root,tag);
assert(out.Ok && out.ResultOk && out.Manifest.HARQEnabled);
T=out.TrialTable; S=out.SummaryTable;
assert(height(T)==7 && all(T.PerfectCSI) && all(T.LDPCBaseGraph==1));
assert(all(T.CRCPass & T.TBExact) && ~any(T.IsRetransmission));
assert(all(S.PendingTransportBlocks==0 & S.DroppedTransportBlocks==0));
assert(abs(out.Manifest.HorizonSeconds-0.0015)<1e-12);
clock=readtable(fullfile(out.RunFolder,'air_interface','csv','timeline.csv'),'Delimiter',',');
assert(height(clock)==12 && sum(clock.FeedbackDrainSlot)==4);
assert(all(ismember(clock.FeedbackDrainSlot,[0 1])));
drain=logical(clock.FeedbackDrainSlot);
assert(~any(clock.DLActive(drain)) && ~any(clock.ULActive(drain)));
for d=["DL","UL"]
    ledger=readtable(fullfile(out.RunFolder,'harq','csv',lower(d)+"_delivery_ledger.csv"),'Delimiter',',');
    feedback=readtable(fullfile(out.RunFolder,'harq','csv',lower(d)+"_feedback.csv"),'Delimiter',',');
    assert(all(feedback.AvailableSlot==feedback.SourceSlot+4));
    assert(all(feedback.DeliveredAtSlot==feedback.AvailableSlot));
    assert(sum(ledger.CountedGoodputBits)==sum(T.TBSBits(T.Direction==d)));
    assert(S.GoodputBitsPerSecond(S.Direction==d)==sum(ledger.CountedGoodputBits)/0.0015);
end
assert(isfile(fullfile(out.RunFolder,'reports','image','tdd_goodput.png')));
ok=true;
fprintf('RESEARCH_HARQ_RUNNER_PASS folder=%s data_slots=8 feedback_drain_slots=4 final_throughput_acceptance=0\n',out.RunFolder);
end
