function ok=testHARQPhysicalPopulationAccounting()
trials=table(ones(4,1)*2,[41;42;43;44],'VariableNames',{'Frame','Slot'});
feedback=table(["tx41";"tx42";"tx43";"tx44"],repmat("ACK",4,1), ...
    'VariableNames',{'TransmissionID','FeedbackOutcome'});
pucch=table(["p1";"p2"],[1;1],[4;1], ...
    'VariableNames',{'PhysicalPUCCHOccasionId','PUCCHTransmissionPrepared','ExpectedBitCount'});
out=sixgr.truth.summarizeHARQPhysicalPopulations(trials,feedback,pucch);
assert(out.TransportAttemptsObserved==4 && out.DistinctRadioFrames==1 && ...
    out.LogicalFeedbackAssociations==4 && out.LogicalACKAssociations==4 && ...
    out.LogicalACKRate==1 && out.PhysicalPUCCHTransmissions==2 && out.PhysicalPUCCHInformationBits==5);
dup=sixgr.truth.summarizeHARQPhysicalPopulations(trials,[feedback;feedback(1,:)],[pucch;pucch(1,:)]);
assert(isequaln(out,dup));
feedback.FeedbackOutcome(2:3)=["NACK";"DTX"];
out=sixgr.truth.summarizeHARQPhysicalPopulations(trials,feedback,pucch);
assert(out.LogicalACKRate==.5 && out.LogicalFeedbackAssociations==4);
unsent=pucch; unsent.PUCCHTransmissionPrepared(:)=0; unsent.ExpectedBitCount(:)=NaN;
out=sixgr.truth.summarizeHARQPhysicalPopulations(trials,feedback,unsent);
assert(out.PhysicalPUCCHTransmissions==0 && out.PhysicalPUCCHInformationBits==0);
bad=pucch(1,:); bad.ExpectedBitCount=10;
try, sixgr.truth.summarizeHARQPhysicalPopulations(trials,feedback,[pucch;bad]); error('test:MissingGuard');
catch cause, assert(string(cause.identifier)=="sixgr:truth:ConflictingPUCCHPopulation"); end
% Exercise the runtime summary owner too, not just the independent exporter.
% These are declared accounting rows; no measured PHY campaign is implied.
runtime=trials;
runtime.Direction=repmat("DL",4,1); runtime.HarqID=(0:3).';
runtime.IsRetransmission=false(4,1); runtime.CombinedDecodeOK=true(4,1);
runtime.MeasuredSINR_dB=nan(4,1); runtime.WidebandCQI=nan(4,1);
runtime.CQIDerivedMCS=nan(4,1);
summary=sixgr.truth.CoupledTruthRuntime.harqSummaryRuntime(struct('HARQTimelineTable',runtime));
assert(summary.FramesObserved==1,'test:HARQAttemptsMislabelledAsFrames', ...
    'Four attempts in one radio frame must not be exported as four frames.');
assert(summary.TransportAttemptsObserved==4 && summary.ReceiverCRCPassRate==1 && ...
    isnan(summary.AckRate) && summary.FeedbackObservationCount==0);
runtime.SweepPointIndex=[1;1;2;2];
summary=sixgr.truth.CoupledTruthRuntime.harqSummaryRuntime(struct('HARQTimelineTable',runtime));
assert(summary.FramesObserved==2 && summary.TransportAttemptsObserved==4);
runtime=removevars(runtime,'Frame');
summary=sixgr.truth.CoupledTruthRuntime.harqSummaryRuntime(struct('HARQTimelineTable',runtime));
assert(isnan(summary.FramesObserved) && summary.TransportAttemptsObserved==4, ...
    'Missing radio-frame identity cannot be replaced by an attempt count.');
ok=true;
end
