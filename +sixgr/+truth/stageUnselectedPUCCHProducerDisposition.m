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
types=lower(string(rows.UCIType));
harq=contains(types,"harq");
assert(all(harq | types=="csi_part1_part2"), ...
    'sixgr:truth:UnsupportedPUCCHPayloadOwnership','Retain explicit HARQ/CSI producer ownership.');
sixgr.truth.bindReceivedPUCCHCodebookRows(producer.UEHARQCodebook,rows(harq,:));
indices=zeros(height(rows),1);
indices(harq)=sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping.BaseMapping,rows(harq,:));
pending=state.PendingFeedbackTable; trace=state.PUCCHGrantTraceTable;
reports=sixgr.util.structGet(state,'PendingCSITable',table());
pi=zeros(height(rows),1); ti=pi;
for k=1:height(rows)
    t=find(string(trace.PUCCHGrantId)==string(rows.PUCCHGrantId(k)));
    assert(isscalar(t) && ~trace.MultiplexedOnPUSCH(t) && ~trace.GrantExecutedFlag(t), ...
        'sixgr:truth:UnselectedPUCCHProducerAlreadyDisposed', ...
        'Bind each unprocessed PUCCH producer once; never relabel a PUSCH transfer.');
    if harq(k)
        p=find(string(pending.PUCCHGrantId)==string(rows.PUCCHGrantId(k)));
        assert(isscalar(p) && ~pending.Processed(p) && string(pending.DeliveryMechanism(p))=="pucch", ...
            'sixgr:truth:UnselectedPUCCHProducerAlreadyDisposed','Require the unprocessed HARQ producer.');
    else
        assert(~isempty(reports),'sixgr:truth:UnselectedPUCCHCSIProducerMissing','Retain the actual CSI producer.');
        p=find("PUCCH-CSI-"+string(reports.ReportIdentity)==string(rows.PUCCHGrantId(k)));
        assert(isscalar(p) && ~reports.Processed(p) && reports.UEIndex(p)==selection.UEIndex && ...
            reports.DueSlot(p)==selection.TargetSlot && string(reports.CSIUCITransport(p))=="pucch_bound" && ...
            ~reports.CSIUCIMultiplexedOnPUSCH(p), ...
            'sixgr:truth:UnselectedPUCCHProducerAlreadyDisposed','Require the exact transmitted CSI reservation.');
    end
    pi(k)=p; ti(k)=t;
end
for name=["PUCCHTransmissionExecuted","PUCCHDecoderInvoked","HARQFeedbackApplied","StaleFeedbackIgnored"]
    if ~ismember(name,string(trace.Properties.VariableNames)), trace.(name)=NaN(height(trace),1); end
end
for name=["GNBFeedbackTransport","GNBFeedbackObservationID","PUCCHTransmissionID"]
    if ~ismember(name,string(trace.Properties.VariableNames)), trace.(name)=strings(height(trace),1); end
end
for k=1:height(rows)
    t=ti(k);
    if harq(k)
        d=dispositions(indices(k));
        assert(d.SourceSlot==rows.SourceSlot(k) && d.HARQProcess==rows.HarqID(k) && ...
            d.TargetSlot==selection.TargetSlot && d.FeedbackDispositionPrevalidated, ...
            'sixgr:truth:UnselectedPUCCHDispositionMismatch','Join only the same physical DL attempt.');
        pending.Processed(pi(k))=true;
        trace.GNBFeedbackObservationID(t)=d.ObservationID;
        trace.HARQFeedbackApplied(t)=double(~d.StaleFeedbackIgnored);
        trace.StaleFeedbackIgnored(t)=double(d.StaleFeedbackIgnored);
    else
        % This is TX-only producer disposition, not CSI reception/failure.
        % Actual independently decoded PUSCH CSI has its own receiver table.
        p=pi(k);
        reports.Processed(p)=true;
        reports.CSIUCITransport(p)="pucch_transmitted_unselected";
        reports.DeliveryStatus(p)="transmitted_without_PUCCH_reception";
        reports.CSIUCIDeliveryReason(p)="gNB_selected_scheduled_PUSCH_receiver";
        trace.HARQFeedbackApplied(t)=0;
        trace.StaleFeedbackIgnored(t)=0;
    end
    trace.GrantExecutedFlag(t)=true;
    trace.PUCCHTransmissionExecuted(t)=1; trace.PUCCHDecoderInvoked(t)=0;
    trace.PUCCHTransmissionID(t)=identity.TransmissionID;
    trace.GNBFeedbackTransport(t)="PUSCH";
    trace.PUCCHGrantState(t)="transmitted_unselected_gnb_PUSCH";
    trace.Status(t)="TX_ONLY";
    trace.Notes(t)="Actual PUCCH TX retained; no PUCCH decoder/BER result. HARQ/CSI reception is in the independent PUSCH receive tables.";
end
next.PendingFeedbackTable=pending; next.PUCCHGrantTraceTable=trace;
if ~isempty(reports), next.PendingCSITable=reports; end
end
