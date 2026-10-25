function audit=joinCSIProducerCompletionAudit(original,received)
%JOINCSIPRODUCERCOMPLETIONAUDIT Private producer state, never RX authority.
% Called only AFTER independent decoding and scheduler publication. The
% returned row belongs to PendingCSITable, not SharedGNBCSIReportTable.
assert(isstruct(original)&&isscalar(original)&&isstruct(received)&&isscalar(received), ...
    'sixgr:truth:InvalidCSIProducerCompletionAudit','Join one original and one received report.');
for name=["ReportIdentity","Direction","UEIndex","ServingCell","DueSlot"]
    assert(isfield(original,name)&&isfield(received,name), ...
        'sixgr:truth:InvalidCSIProducerCompletionAudit','Missing CSI identity %s.',name);
    if any(name==["ReportIdentity","Direction"])
        same=isscalar(string(original.(name)))&&isscalar(string(received.(name)))&& ...
            ~ismissing(string(original.(name)))&&strlength(string(original.(name)))>0&& ...
            string(original.(name))==string(received.(name));
    else
        same=isnumeric(original.(name))&&isscalar(original.(name))&& ...
            isfinite(original.(name))&&isequal(original.(name),received.(name));
    end
    assert(same,'sixgr:truth:CSIProducerCompletionIdentityMismatch', ...
        'A received report cannot replace another producer identity (%s).',name);
end
audit=received;
% Reference payload is retained for post-reception comparison only. The
% admission hashes/retirement/disposition are UE-owned lifecycle, not decoded
% CSI bits. Preserve even an empty disposition: after the first deferral this
% column exists on every pending row and strict row replacement requires it.
% DeliveryStatus/DeliveredSlot remain the independent receiver's outcome.
names=["CSIPart1BitsToken","CSIPart2BitsToken","CSIPart1BitCount", ...
    "CSIPart2BitCount","CSIUCIBitCount","UECSIMeasurementInstallationSHA256", ...
    "UECSIMeasurementConfigurationSHA256","UECSIPayloadRetired","UECSIPayloadAdmissionStatus", ...
    "UEProducerDisposition"];
for name=names
    if isfield(original,name), audit.(name)=original.(name); end
end
end
