function p=resolveULMACControlPolicy(declared,slotDuration_s)
% Explicit received MAC demand policy; probe bytes are not a BSR measurement.
assert(isstruct(declared)&&isscalar(declared),'sixgr:mac:InvalidULMACPolicy','UL MAC policy must be scalar.');
p=struct('Enabled',false);
if isempty(fieldnames(declared)), return; end
assert(isfield(declared,'enabled')&&islogical(declared.enabled)&&isscalar(declared.enabled), ...
    'sixgr:mac:InvalidULMACPolicy','UL MAC enabled must be explicit boolean.');
p.Enabled=declared.enabled; if ~p.Enabled, return; end
names=["enabled","lcg_id","sr_probe_bytes","received_report_max_age_ms", ...
    "bsr_periodic_ms","bsr_retx_ms","phr_periodic_ms","phr_prohibit_ms","phr_pathloss_change_db","phr_power_management_backoff", ...
    "phr_allocation_policy","phr_allocation_margin_db"];
assert(all(isfield(declared,names))&&all(ismember(string(fieldnames(declared)),names)), ...
    'sixgr:mac:InvalidULMACPolicy','Enabled UL MAC policy requires the complete declared schema.');
validateattributes(slotDuration_s,{'numeric'},{'scalar','finite','positive'});
validateattributes(declared.lcg_id,{'numeric'},{'scalar','finite','integer','>=',0,'<=',7});
validateattributes(declared.sr_probe_bytes,{'numeric'},{'scalar','finite','integer','positive'});
validateattributes(declared.received_report_max_age_ms,{'numeric'},{'scalar','finite','positive'});
assert(ismember(declared.phr_periodic_ms,[10 20 50 100 200 500 1000 Inf])&& ...
    ismember(declared.phr_prohibit_ms,[0 10 20 50 100 200 500 1000])&& ...
    ismember(declared.phr_pathloss_change_db,[1 3 6 Inf]), ...
    'sixgr:mac:InvalidPHRPolicy','PHR timer/threshold must be supported R18 values.');
p.LCGID=declared.lcg_id; p.SRProbeBytes=declared.sr_probe_bytes;
p.ReceivedReportMaxAge_s=declared.received_report_max_age_ms/1000;
p.PHRPathlossChange_dB=declared.phr_pathloss_change_db;
assert(islogical(declared.phr_power_management_backoff)&&isscalar(declared.phr_power_management_backoff), ...
    'sixgr:mac:InvalidPHRPolicy','Power-management backoff applicability must be explicit.');
p.PHRPowerManagementBackoff=declared.phr_power_management_backoff;
p.PHRAllocationPolicy=string(declared.phr_allocation_policy);
assert(isscalar(p.PHRAllocationPolicy)&&ismember(p.PHRAllocationPolicy,["disabled","constant_terms_quantized_lower_bound"]), ...
    'sixgr:mac:InvalidPHRAllocationPolicy','Explicit supported PHR allocation policy required.');
validateattributes(declared.phr_allocation_margin_db,{'numeric'},{'scalar','real','finite','nonnegative'});
p.PHRAllocationMargin_dB=double(declared.phr_allocation_margin_db);
for pair={"bsr_periodic_ms","BSRPeriodicSlots";"bsr_retx_ms","BSRRetxSlots"; ...
        "phr_periodic_ms","PHRPeriodicSlots";"phr_prohibit_ms","PHRProhibitSlots"}.'
    name=pair{1}; target=pair{2}; value=declared.(name);
    assert(isscalar(value)&&isreal(value)&&~isnan(value)&&value>=0, ...
        'sixgr:mac:InvalidULMACTimer','Explicit nonnegative timer required.');
    slots=value/(1000*slotDuration_s);
    assert(isinf(slots)||abs(slots-round(slots))<1e-10, ...
        'sixgr:mac:UnrepresentableTimer','Timer must map exactly to canonical slots.');
    p.(target)=round(slots);
end
assert(isfinite(p.BSRPeriodicSlots)&&p.BSRPeriodicSlots>0&& ...
    isfinite(p.BSRRetxSlots)&&p.BSRRetxSlots>0,'sixgr:mac:InvalidBSRTimer','Supported BSR timers must be finite positive.');
p.QueueAuthority="received_SR_BSR_only";
p.ProbeSource="received_SR_probe_allocation_policy";
end
