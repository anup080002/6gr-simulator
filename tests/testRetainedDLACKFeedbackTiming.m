function ok=testRetainedDLACKFeedbackTiming(outputRoot)
% Actual archived UE decode lineage, declared clock/reservation unit inputs.
% Does not claim a new shared PDCCH/PDSCH/PUCCH transmission.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve old evidence.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
saved=load('docs/lls/evidence_20260913/received_dl_harq/attempt_3.mat');
a=saved.a;
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,a.ControlAbsoluteSlot+1);
[~,~,e]=saved.before.acknowledgeRetained(cfg,a);
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=nrOFDMInfo(carrier).SampleRate;
e.ControlAvailableAtSample=sixgr.phy.frame.slotStartSample(carrier,a.ControlAbsoluteSlot+1,fs);
e.DecisionAvailableAtSample=e.ControlAvailableAtSample;
e.SampleRateHz=fs; e.HARQFeedbackAbsoluteSlot=a.HARQFeedbackAbsoluteSlot;
e.PUCCHResourceIndicator=a.PUCCHResourceIndicator;
row=sixgr.truth.copyHARQReceiveTimingFields(struct());
row.HARQProtocolDecisionEvidenceJSON=string(jsonencode(e));
row.UEIndex=1; row.RNTI=a.RNTI; row.HarqID=a.HARQProcess; row.NDI=a.NDI;
row.SourceSlot=a.DataAbsoluteSlot+1; row.DueSlot=a.HARQFeedbackAbsoluteSlot+1;
row.PRIValue=a.PUCCHResourceIndicator; row.TBSBits=e.RetainedTBSBits;
row.PUCCHGrantId="declared_retained_ack_timing_fixture";
row.Ack=true; row.Processed=false; row.CurrentDecodeOK=false; row.CombinedDecodeOK=false;
now=e.DecisionAvailableAtSample;
sixgr.truth.assertHARQFeedbackAvailable(row,now,fs);
trace=rmfield(row,{'DueSlot','Ack'}); trace.ScheduledAbsoluteSlot=row.DueSlot;
trace.ExpectedAck=true;
sixgr.truth.assertHARQFeedbackAvailable(struct2table(trace),now,fs);
ledger=struct('PendingFeedbackTable',struct2table(row));
collected=sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueHARQACKRuntime(ledger,row.DueSlot);
assert(isscalar(collected) && collected.AckBit==1);
sixgr.truth.assertHARQFeedbackAvailable(collected,now,fs);
trace.UCIType="harq_ack";
traceOnly=struct('PUCCHGrantTraceTable',struct2table(trace));
collected=sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueHARQACKRuntime(traceOnly,row.DueSlot);
assert(isscalar(collected) && collected.AckBit==1 && collected.DueSlot==row.DueSlot);
sixgr.truth.assertHARQFeedbackAvailable(collected,now,fs);
localReject(@()sixgr.truth.assertHARQFeedbackAvailable(row,now-1,fs), ...
    'sixgr:truth:FutureHARQFeedbackAtUCIEncoding');
localReject(@()sixgr.truth.assertHARQFeedbackAvailable(row,now,2*fs), ...
    'sixgr:truth:InvalidRetainedACKTiming');
for name=["RNTI","UEIndex","HarqID","SourceSlot","DueSlot","PRIValue","TBSBits"]
    bad=row; bad.(name)=bad.(name)+1;
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(bad,now,fs), ...
        'sixgr:truth:InvalidRetainedACKTiming');
end
for name=["Ack","NDI","CurrentDecodeOK","CombinedDecodeOK"]
    bad=row; bad.(name)=~bad.(name);
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(bad,now,fs), ...
        'sixgr:truth:RetainedACKDecisionMismatch');
end
bad=row; bad.DataDecodeAvailableAtSample=now;
localReject(@()sixgr.truth.assertHARQFeedbackAvailable(bad,now,fs), ...
    'sixgr:truth:RetainedACKClaimedCurrentDecode');
bad=row; bad.HARQProtocolDecisionEvidenceJSON="not JSON";
localReject(@()sixgr.truth.assertHARQFeedbackAvailable(bad,now,fs), ...
    'sixgr:truth:InvalidRetainedACKTiming');
mkdir(outputRoot);
sixgr.util.csvWriteTable(fullfile(outputRoot,'retained_ack_clock_fixture.csv'),struct2table(row),'PreserveSchema',true);
fprintf('RETAINED_DL_ACK_FEEDBACK_TIMING_PASS guards=15 collector_and_trace=1 fixture_clocks_not_main_run=1 folder=%s\n',outputRoot);
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
