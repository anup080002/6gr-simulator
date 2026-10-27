function ok=testSSBSearchMeasurementIdentity()
% Declared identity fixture, not a transmitted-beam or received-power claim.
setup6GRSimToolkit('Verbose',false);
state=struct('CurrentSlot',5);
row=table(NaN,1,4,string(repmat('a',1,64)),0,59556,30.72e6, ...
    "unavailable_no_received_pbch_channel_estimate", ...
    'VariableNames',{'SSBIndex','ServingCell','RequestedSSBOccasionIndex', ...
    'ReceiverObservationSHA256','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','NMSEReferenceSource'});
for candidate=4:7
    row.RequestedSSBOccasionIndex=candidate;
    state=publish(state,row,false);
end
T=state.ReferenceSignalMeasurementTable;
assert(height(T)==4&&numel(unique(string(T.MeasurementId)))==4&& ...
    all(isnan(T.ResourceId))&&~any(T.Valid)&&all(isnan(T.RSRP_dBm))&& ...
    isequal(T.RequestedSSBOccasionIndex,(4:7).'));
assert(all(string(T.EvidenceSource)=="unavailable_no_received_pbch_channel_estimate"));
% Repeating the exact search preserves identity but never deduplicates rows.
again=publish(state,row,false);
assert(height(again.ReferenceSignalMeasurementTable)==5&& ...
    string(again.ReferenceSignalMeasurementTable.MeasurementId(5))==string(T.MeasurementId(4)));
changed=row; changed.ReceiverObservationSHA256=string(repmat('b',1,64));
next=publish(state,changed,false);
assert(~ismember(string(next.ReferenceSignalMeasurementTable.MeasurementId(5)),string(T.MeasurementId)));
changed=row; changed.ObservationStartSample=1; changed.ObservationEndSampleExclusive=59557;
next=publish(state,changed,false);
assert(~ismember(string(next.ReferenceSignalMeasurementTable.MeasurementId(5)),string(T.MeasurementId)));
valid=row; valid.SSBIndex=0;
next=publish(struct('CurrentSlot',5),valid,true);
assert(string(next.ReferenceSignalMeasurementTable.MeasurementId)=="SSB_UE_1_resource_0_slot_1");
missing=removevars(row,'ReceiverObservationSHA256');
next=publish(struct('CurrentSlot',5),missing,false);
assert(string(next.ReferenceSignalMeasurementTable.SSBSearchIdentityStatus)== ...
    "unavailable_original_search_candidate_or_capture"&&isnan(next.ReferenceSignalMeasurementTable.ResourceId));
ok=true;
fprintf('SSB_SEARCH_MEASUREMENT_IDENTITY_PASS distinct_quiet_candidates=4 no_detection_or_power_invented=1\n');
end
function state=publish(state,row,valid)
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,"SSB","UE",1,row,'ProducerSlot',1,'AvailableSlot',5,'Valid',valid,'Direction','DL');
end
