function [usable,status] = qclTimingSchedulingEligibility(state,ueIndex)
% Admission uses the same source age as the PDSCH receiver, not TRS delivery
% age. This is scheduler policy; the receiver's independent guard remains.
policy=sixgr.util.structGet(state.CfgMobility,'phy.pdsch.qclTCI',struct());
usable=true; status="not_required";
if ~logical(sixgr.util.structGet(policy,'enabled',false)), return; end
[installed,status,receipt]=sixgr.truth.DLMeasurementInstallation.current(state,ueIndex,"TRS");
if ~installed, usable=false; return; end
usable=false; status="missing_received_qcl_timing_reference";
references=sixgr.util.structGet(state,'SharedQCLTimingReferences',{});
if numel(references)<ueIndex || isempty(references{ueIndex}), return; end
source=references{ueIndex};
if sixgr.truth.DLMeasurementInstallation.required(state) && ...
        string(sixgr.util.structGet(source,'DLMeasurementInstallationSHA256',""))~=receipt.SHA256
    usable=false; status="qcl_reference_before_current_measurement_installation"; return;
end
fields={'UEIndex','ServingCellIndex','SourceResourceID','ConfigurationEpoch', ...
    'SourceSlot0','AvailableAtSample','SampleRateHz','Source'};
assert(isstruct(source) && isscalar(source) && all(isfield(source,fields)), ...
    'sixgr:qcl:IncompleteSchedulingReference', ...
    'A received QCL timing reference must retain its identity and clock.');
% NaN comparisons are false in MATLAB; reject malformed evidence before
% evaluating age/availability so NaN cannot accidentally admit a grant.
status="invalid_received_qcl_reference";
for field=fields(1:7)
    value=source.(field{1});
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value<0 || value~=fix(value)
        return;
    end
end
if source.UEIndex<1 || source.ServingCellIndex<1 || source.SampleRateHz<=0 || ...
        ~isscalar(string(source.Source)) || ismissing(string(source.Source))
    return;
end
resource=sixgr.util.structGet(policy,'timing_source_resource_id', ...
    sixgr.util.structGet(policy,'source_resource_id',NaN));
serving=state.CurrentServingIdx(ueIndex);
status="qcl_reference_identity_mismatch";
if source.UEIndex~=ueIndex || source.ServingCellIndex~=serving || ...
        source.SourceResourceID~=resource || ...
        source.ConfigurationEpoch~=policy.configuration_epoch || ...
        string(source.Source)~="received_nzp_csi_rs_trs_timing_estimator"
    return;
end
slot0=double(state.CurrentSlot)-1;
status="inactive_or_stale_qcl_timing_reference";
if slot0<policy.activation_absolute_slot0 || slot0<source.SourceSlot0 || ...
        slot0-source.SourceSlot0>policy.source_max_age_slots
    return;
end
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
start=sixgr.phy.frame.slotStartSample(carrier,slot0,source.SampleRateHz);
known=start;
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
if isa(owner,'sixgr.truth.CoupledWaveformStream')
    assert(owner.SampleRateHz==source.SampleRateHz, ...
        'sixgr:qcl:ReferenceIdentityMismatch','QCL and physical owner clocks differ.');
    known=min(known,owner.Events.NextSampleIndex);
end
status="qcl_timing_reference_not_yet_available";
if source.AvailableAtSample>known, return; end
usable=true; status="received_qcl_timing_reference_usable";
end
