function next=stageUnselectedPUCCHProducerDisposition(state,selection,producer,mapping,dispositions)
% Value-state bookkeeping only. gNB PUSCH feedback has its own independent
% mapping/commit; UE PUCCH TX is not relabeled as PUSCH TX or PUCCH decoding.
next=state;
identity=sixgr.truth.validateUnselectedPUCCHTransmission(state,selection,producer);
if isempty(fieldnames(identity)), return; end
assert(mapping.Digest==selection.HARQMappingDigest && ...
    numel(dispositions)==mapping.PhysicalAssignmentCount && ...
    all(string({dispositions.MappingDigest})==mapping.Digest), ...
    'sixgr:truth:UnselectedPUCCHDispositionMismatch','Use the independent scheduled PUSCH dispositions.');
rows=producer.FeedbackRows;
sixgr.truth.bindReceivedPUCCHCodebookRows(producer.UEHARQCodebook,rows);
indices=sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping.BaseMapping,rows);
pending=state.PendingFeedbackTable; trace=state.PUCCHGrantTraceTable;
pi=zeros(height(rows),1); ti=pi;
for k=1:height(rows)
    p=find(string(pending.PUCCHGrantId)==string(rows.PUCCHGrantId(k)));
    t=find(string(trace.PUCCHGrantId)==string(rows.PUCCHGrantId(k)));
    assert(isscalar(p) && isscalar(t) && ~pending.Processed(p) && ...
        string(pending.DeliveryMechanism(p))=="pucch" && ~trace.MultiplexedOnPUSCH(t) && ...
        ~trace.GrantExecutedFlag(t), ...
        'sixgr:truth:UnselectedPUCCHProducerAlreadyDisposed', ...
        'Bind each unprocessed PUCCH producer once; never relabel a PUSCH transfer.');
    pi(k)=p; ti(k)=t;
end
for name=["PUCCHTransmissionExecuted","PUCCHDecoderInvoked","HARQFeedbackApplied","StaleFeedbackIgnored"]
    if ~ismember(name,string(trace.Properties.VariableNames)), trace.(name)=NaN(height(trace),1); end
end
for name=["GNBFeedbackTransport","GNBFeedbackObservationID","PUCCHTransmissionID"]
    if ~ismember(name,string(trace.Properties.VariableNames)), trace.(name)=strings(height(trace),1); end
end
for k=1:height(rows)
    d=dispositions(indices(k)); t=ti(k);
    assert(d.SourceSlot==rows.SourceSlot(k) && d.HARQProcess==rows.HarqID(k) && ...
        d.TargetSlot==selection.TargetSlot && d.FeedbackDispositionPrevalidated, ...
        'sixgr:truth:UnselectedPUCCHDispositionMismatch','Join only the same physical DL attempt.');
    pending.Processed(pi(k))=true;
    trace.GrantExecutedFlag(t)=true;
    trace.PUCCHTransmissionExecuted(t)=1; trace.PUCCHDecoderInvoked(t)=0;
    trace.PUCCHTransmissionID(t)=identity.TransmissionID;
    trace.GNBFeedbackTransport(t)="PUSCH";
    trace.GNBFeedbackObservationID(t)=d.ObservationID;
    trace.HARQFeedbackApplied(t)=double(~d.StaleFeedbackIgnored);
    trace.StaleFeedbackIgnored(t)=double(d.StaleFeedbackIgnored);
    trace.PUCCHGrantState(t)="transmitted_unselected_gnb_PUSCH";
    trace.Status(t)="TX_ONLY";
    trace.Notes(t)="Actual PUCCH TX retained; no PUCCH decoder/BER result. HARQ disposition is in the independent PUSCH receive table.";
end
next.PendingFeedbackTable=pending; next.PUCCHGrantTraceTable=trace;
end
