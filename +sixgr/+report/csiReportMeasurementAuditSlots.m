function [slots,authority] = csiReportMeasurementAuditSlots(reports)
% Post-hoc measurement/report linkage, never receiver or scheduler input.
% A gNB CSI reference-resource slot is not the private UE measurement slot.
% Only the retained, identity-matched UE audit record can establish the latter.
arguments
    reports table
end
slots = nan(height(reports),1);
authority = repmat("unbound_measurement_audit",height(reports),1);
names = string(reports.Properties.VariableNames);
if ~ismember("SourceSlot",names), return; end
for k = 1:height(reports)
    declared = "";
    if ismember("SourceSlotAuthority",names)
        declared = string(reports.SourceSlotAuthority(k));
        if ismissing(declared), declared = ""; end
    end
    if declared == ""
        % Direct receiver report rows explicitly carry their measurement slot.
        if localSlot(reports.SourceSlot(k))
            slots(k) = double(reports.SourceSlot(k));
            authority(k) = "receiver_report_measurement_source_slot";
        end
        continue;
    end
    if declared ~= "configured_CSI_reference_resource_not_UE_measurement_slot" || ...
            ~ismember("UEReferenceRecordJSON",names)
        continue;
    end
    try
        reference = jsondecode(string(reports.UEReferenceRecordJSON(k)));
    catch
        continue; % Missing/corrupt audit evidence must remain unbound.
    end
    identity = ["Direction","UEIndex","RNTI","ReportIdentity", ...
        "CSIReportConfigID","CSIConfigurationEpoch","CSIReferenceSlot","DueSlot"];
    if ~isstruct(reference) || ~isscalar(reference) || ...
            ~all(ismember(identity,names)) || ~all(isfield(reference,cellstr(identity))) || ...
            ~all(isfield(reference,{'SourceSlot','MeasurementAvailableSlot','SourceSignal'}))
        continue;
    end
    matches = true;
    for field = identity
        actual = reports.(field)(k);
        expected = reference.(field);
        if isnumeric(actual) && isnumeric(expected)
            equal = isscalar(actual) && isscalar(expected) && ...
                isfinite(actual) && isfinite(expected) && actual==expected;
        else
            equal = isscalar(string(actual)) && isscalar(string(expected)) && ...
                ~ismissing(string(actual)) && ~ismissing(string(expected)) && ...
                strlength(string(actual))>0 && string(actual)==string(expected);
        end
        matches = matches && equal;
    end
    if ~matches || string(reference.SourceSignal)~="CSI-RS" || ...
            ~localSlot(reference.UEIndex) || ~localSlot(reference.RNTI) || ...
            ~localSlot(reference.CSIReferenceSlot) || ...
            ~isnumeric(reference.CSIConfigurationEpoch) || ...
            ~isscalar(reference.CSIConfigurationEpoch) || ...
            ~isfinite(reference.CSIConfigurationEpoch) || ...
            reference.CSIConfigurationEpoch<0 || ...
            reference.CSIConfigurationEpoch~=fix(reference.CSIConfigurationEpoch) || ...
            ~localSlot(reference.SourceSlot) || ~localSlot(reference.MeasurementAvailableSlot) || ...
            ~localSlot(reference.DueSlot) || ...
            reference.SourceSlot>reference.MeasurementAvailableSlot || ...
            reference.MeasurementAvailableSlot>reference.DueSlot || ...
            reference.CSIReferenceSlot>=reference.DueSlot
        continue;
    end
    slots(k) = double(reference.SourceSlot);
    authority(k) = "posthoc_identity_matched_UE_audit_not_gNB_receive_authority";
end
end

function valid = localSlot(value)
valid = isnumeric(value) && isscalar(value) && isfinite(value) && ...
    value>=1 && value==fix(value);
end
