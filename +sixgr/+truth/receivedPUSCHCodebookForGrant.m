function book=receivedPUSCHCodebookForGrant(state,grant,hasOverlappingHARQ)
% Planning may precede control reception; actual TX callers must require a
% typed result. Never substitute the scheduled DCI or pending ACK bit values.
book=[];
assert(islogical(hasOverlappingHARQ) && isscalar(hasOverlappingHARQ), ...
    'sixgr:truth:MissingReceivedHARQTransportSelection', ...
    'Retain the UE PUCCH/PUSCH symbol-overlap decision before constructing UCI.');
if ~isfield(state,'SharedWaveformStream') || ~isfield( ...
        sixgr.util.structGet(state.CfgMobility,'phy.pdcch.operatorControl',struct()),'connected_dci')
    return;
end
controlSlot=sixgr.truth.resolvePDCCHControlSlot(grant);
key="UL_ue_"+grant.UEIndex+"_rnti_"+grant.RNTI+"_control_"+controlSlot+"_data_"+grant.Slot;
controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
hit=find(cellfun(@(r)r.Key==key,controls));
if isempty(hit), return; end
assert(isscalar(hit),'sixgr:truth:AmbiguousReceivedULControl', ...
    'One exact received UL control result must own this PUSCH preparation.');
control=controls{hit};
assert(control.Allowed && ~isempty(control.ReceivedAssignment) && ...
    control.AvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex && ...
    string(control.Grant.PHYGrant.GrantContextId)==string(grant.PHYGrant.GrantContextId), ...
    'sixgr:truth:UnavailableReceivedULControl','A missed/future/different UL DCI cannot authorize UCI encoding.');
[cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(state.CfgMobility,state,grant.UEIndex,'UL');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,controlSlot);
book=sixgr.truth.buildReceivedHARQACKCodebook( ...
    state,cfg,grant.UEIndex,grant.Slot,control.ReceivedAssignment);
% Same feedback slot does not imply UCI-on-PUSCH (TS 38.213 9.2.5).
% The caller resolves the UE's actual configured PUCCH resource, including
% combined CSI/SR, and its overlap with this PUSCH. Keep a received DL
% codebook on a disjoint PUCCH; do not bind it to zero PUSCH producer rows.
% With no received DL event, retain the UL-DAI gap-only procedure: missing
% DCI must remain observable, not be erased using gNB scheduling knowledge.
if ~hasOverlappingHARQ && ~isempty(book.Events)
    % Do not confuse missing UE bookkeeping with a disjoint resource. The
    % real PUCCH producer identities must still exist, including already
    % executed rows if reconciliation is revisited later in the same slot.
    rows=sixgr.util.structGet(state,'PUCCHGrantTraceTable',table());
    assert(istable(rows) && all(ismember({'UEIndex','RNTI', ...
        'ScheduledAbsoluteSlot','UCIType'},rows.Properties.VariableNames)), ...
        'sixgr:truth:ReceivedPUCCHProducerMismatch', ...
        'Disjoint PUCCH feedback must retain its actual producer identities.');
    rows=rows(double(rows.UEIndex)==grant.UEIndex & double(rows.RNTI)==grant.RNTI & ...
        double(rows.ScheduledAbsoluteSlot)==grant.Slot & ...
        contains(lower(string(rows.UCIType)),"harq"),:);
    sixgr.truth.bindReceivedPUCCHCodebookRows(book,rows);
    book=[];
end
end
