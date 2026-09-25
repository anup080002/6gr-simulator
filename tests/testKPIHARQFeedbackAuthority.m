function ok=testKPIHARQFeedbackAuthority()
% Receiver CRC, received feedback, and DTX are different populations.
raw=struct(); raw.HARQFeedback=fixture();
r=row(raw);
assert(r.StrictOk && r.NumeratorValue==1 && r.DenominatorValue==2 && r.Value==.5);
assert(r.FeedbackObservedCount==3 && r.FeedbackDTXCount==1 && r.ExcludedRowCount==1);
% Poisoning decoder CRCs cannot change the independently received result.
raw.HARQTimeline=table(["DL";"DL";"DL"],[1;2;3],[0;0;0],[0;1;1],[0;0;0], ...
    'VariableNames',{'Direction','Slot','HarqID','IsRetransmission','CombinedDecodeOK'});
r2=row(raw); assert(r2.Value==r.Value && r2.DenominatorValue==r.DenominatorValue);
raw.HARQTimeline.CombinedDecodeOK(:)=NaN;
r2=row(raw); assert(r2.Value==r.Value);
without=rmfield(raw,'HARQFeedback'); r2=row(without);
assert(~r2.StrictOk && isnan(r2.Value));
out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(without);
retx=out.ReconstructionSummary(out.ReconstructionSummary.KPIName=="DL_Retransmission_Rate",:);
assert(retx.StrictOk && abs(retx.Value-2/3)<1e-12);
manifest=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw);
manifest=manifest.SourceManifest(manifest.SourceManifest.Direction=="HARQFeedback",:);
assert(manifest.RowCount==3 && manifest.DLSubsetRowCount==3 && manifest.ULSubsetRowCount==0);
assert(manifest.SourceTableName=="received_harq_feedback_observations");
changed=raw; changed.HARQFeedback=fixture();
changed.HARQFeedback.FeedbackOutcome(:)="DTX";
changed.HARQFeedback.ReceiverUsable(:)=0;
r2=row(changed); assert(isnan(r2.Value) && ~r2.StrictOk && r2.DenominatorValue==0 && r2.FeedbackDTXCount==3);
for field=["ObservedAck","ReceiverUsable","ReceiverVectorLengthMatches"]
    changed=raw; changed.HARQFeedback.(field)(1)=NaN; reject(changed);
end
changed=raw; changed.HARQFeedback.ObservedAck(1)=0; reject(changed);
changed=raw; changed.HARQFeedback.FeedbackOutcome(1)="garbage"; reject(changed);
changed=raw; changed.HARQFeedback=[raw.HARQFeedback;raw.HARQFeedback(1,:)]; reject(changed);
changed=raw; changed.HARQFeedback.AvailableAtSample(1)=99; reject(changed);
changed=raw; changed.HARQFeedback.AvailableAtSample(1)=100.5; reject(changed);
changed=raw; changed.HARQFeedback.ProxyUsed=[1;0;0]; reject(changed);
changed=raw; changed.HARQFeedback.BitIndex(1)=0; reject(changed);
changed=raw; changed.HARQFeedback.ObservationID(1)=""; reject(changed);
changed=raw; changed.HARQFeedback.FeedbackForDirection(1)="UNKNOWN"; reject(changed);
changed=raw; changed.HARQFeedback(:,"ObservationEndSampleExclusive")=[]; reject(changed);
fprintf('PASS testKPIHARQFeedbackAuthority: received ACK/NACK only; DTX separate; decoder CRC not feedback.\n');
ok=true;
end

function r=row(raw)
out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw);
r=out.ReconstructionSummary(out.ReconstructionSummary.KPIName=="DL_HARQ_NACK_Rate",:);
end

function reject(raw)
r=row(raw); assert(~r.StrictOk && isnan(r.Value));
end

function T=fixture()
T=table(["DL";"DL";"DL"],["ACK";"NACK";"DTX"],[1;0;0],[1;1;0],[1;1;0], ...
    ["obs1";"obs2";"obs3"],ones(3,1),ones(3,1),ones(3,1),100*ones(3,1),zeros(3,1),100*ones(3,1), ...
    'VariableNames',{'FeedbackForDirection','FeedbackOutcome','ObservedAck','ReceiverUsable', ...
    'ReceiverVectorLengthMatches','ObservationID','BitIndex','RNTI','SweepPointIndex', ...
    'AvailableAtSample','ObservationStartSample','ObservationEndSampleExclusive'});
end
