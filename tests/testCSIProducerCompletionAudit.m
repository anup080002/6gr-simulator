function ok=testCSIProducerCompletionAudit()
% Declared post-reception value-state test; not waveform qualification.
original=struct('ReportIdentity',"report-7",'Direction',"DL",'UEIndex',1, ...
    'ServingCell',1,'DueSlot',10,'CSIPart1BitsToken',"original_bits", ...
    'CSIPart2BitsToken',"",'CSIPart1BitCount',7,'CSIPart2BitCount',0, ...
    'CSIUCIBitCount',7,'UECSIMeasurementInstallationSHA256',string(repmat('a',1,64)), ...
    'UECSIMeasurementConfigurationSHA256',string(repmat('b',1,64)), ...
    'UECSIPayloadRetired',false,'UECSIPayloadAdmissionStatus',"original_bound", ...
    'CQI',15,'Processed',false);
received=original;
received.CQI=4; received.Processed=true;
received.CSIUCIDecodeOk=true; received.ObservationID="actual-rx-7";
received.UECSIMeasurementInstallationSHA256="";
received.UECSIMeasurementConfigurationSHA256="";
received.UECSIPayloadAdmissionStatus="not_bound";
received.CSIPart1BitsToken="received_bits";
before=received;
audit=sixgr.truth.joinCSIProducerCompletionAudit(original,received);
assert(isequaln(received,before) && audit.CQI==4 && audit.Processed && ...
    audit.CSIUCIDecodeOk && audit.ObservationID=="actual-rx-7" && ...
    audit.CSIPart1BitsToken==original.CSIPart1BitsToken && ...
    audit.UECSIMeasurementInstallationSHA256==original.UECSIMeasurementInstallationSHA256 && ...
    audit.UECSIMeasurementConfigurationSHA256==original.UECSIMeasurementConfigurationSHA256 && ...
    ~audit.UECSIPayloadRetired && audit.UECSIPayloadAdmissionStatus=="original_bound");
% Retired producer audit cannot be resurrected by a receive-only outcome.
retired=original; retired.UECSIPayloadRetired=true;
retired.UECSIPayloadAdmissionStatus="retired_before_binding";
negative=received; negative.CSIUCIDecodeOk=false;
audit=sixgr.truth.joinCSIProducerCompletionAudit(retired,negative);
assert(audit.UECSIPayloadRetired && ~audit.CSIUCIDecodeOk && audit.Processed);
% Declared no-transmission producer versus independent receiver outcomes.
% Neither a negative result nor a false acceptance may erase the original
% producer disposition or use it to override actual receiver fields.
withheld=original;
withheld.UEProducerDisposition="closed_untransmitted_missing_measured_power_reference";
withheld.Processed=true;
withheld.DeliveryStatus="not_transmitted_missing_measured_power_reference";
withheld.DeliveredSlot=NaN;
for decoded=[false,true]
    independent=received;
    independent.CSIUCIDecodeOk=decoded;
    independent.DeliveredSlot=11;
    if decoded
        independent.DeliveryStatus="delivered_to_runtime_scheduler";
    else
        independent.DeliveryStatus="receiver_csi_unavailable_not_delivered";
    end
    independent.UEReferenceRecordJSON=string(jsonencode(withheld));
    originalBefore=withheld; receivedBefore=independent;
    audit=sixgr.truth.joinCSIProducerCompletionAudit(withheld,independent);
    assert(isequaln(withheld,originalBefore) && isequaln(independent,receivedBefore));
    assert(audit.UEProducerDisposition==withheld.UEProducerDisposition && ...
        audit.Processed && audit.CSIUCIDecodeOk==decoded && ...
        audit.DeliveredSlot==independent.DeliveredSlot && ...
        audit.DeliveryStatus==independent.DeliveryStatus && ...
        audit.CQI==independent.CQI && audit.ObservationID==independent.ObservationID && ...
        audit.UEReferenceRecordJSON==independent.UEReferenceRecordJSON);
    assert(~isfield(independent,'UEProducerDisposition'), ...
        'The private producer field must not enter the received report.');
    assert(all(ismember(fieldnames(withheld),fieldnames(audit))), ...
        'The original pending-row schema must remain replaceable.');
end
% A later fresh row shares the table-wide column, but not the withheld state.
fresh=original; fresh.UEProducerDisposition="";
audit=sixgr.truth.joinCSIProducerCompletionAudit(fresh,received);
assert(isfield(audit,'UEProducerDisposition') && audit.UEProducerDisposition=="" && ...
    all(ismember(fieldnames(fresh),fieldnames(audit))) && audit.CSIUCIDecodeOk);
legacy=sixgr.truth.joinCSIProducerCompletionAudit(original,received);
assert(~isfield(legacy,'UEProducerDisposition'), ...
    'Historical rows without the private field must not acquire a disposition.');
for name=["ReportIdentity","Direction","UEIndex","ServingCell","DueSlot"]
    bad=received;
    if isstring(bad.(name)), bad.(name)=bad.(name)+"wrong";
    else, bad.(name)=bad.(name)+1; end
    caught=false;
    try
        sixgr.truth.joinCSIProducerCompletionAudit(withheld,bad);
    catch cause
        caught=strcmp(cause.identifier,'sixgr:truth:CSIProducerCompletionIdentityMismatch');
    end
    assert(caught,'Mismatched %s must not mutate the producer ledger.',name);
end
ok=true;
fprintf('CSI_PRODUCER_COMPLETION_AUDIT_PASS private_binding_retained=1 received_fields_unchanged=1 noTX_outcomes=2 fresh_empty_disposition=1 legacy_absent=1 identity_negatives=5 scope=declared_value_state\n');
end
