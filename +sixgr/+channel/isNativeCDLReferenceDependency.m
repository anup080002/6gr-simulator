function ok=isNativeCDLReferenceDependency(d)
% Preserve old pinned receipts; admit new installations by actual capability.
ok=false;
if ~isstruct(d)||~isscalar(d)||~isfield(d,'NativeFilterAuthority'),return;end
authority=string(d.NativeFilterAuthority);
if authority=="R2026a_Inf_fresh_both_direction_public_getPathFilters"
    ok=string(version('-release'))=="2026a";
    return;
end
if authority~="public_CDL_Inf_capability_verified_original_filters"|| ...
        ~all(isfield(d,{'NativeCapability','NativeCapabilitySHA256','SampleRateHz'})),return;end
c=d.NativeCapability;
ok=sixgr.channel.nativeCDLFIRCapabilityValid(c)&& ...
    isequal(c.SampleRateHz,d.SampleRateHz)&& ...
    string(d.NativeCapabilitySHA256)==string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(c),'UTF-8'))));
end
