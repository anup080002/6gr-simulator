function [prbs,r]=receivedPHRAllocationLimit(cfg,ue,prbs,symbols,mcs,layers)
% Explicit scheduler model, not an NR-mandated algorithm/power guarantee.
r=struct('Applied',false,'Status',"disabled",'Source',"received_PHR_constant_terms_quantized_lower_bound_policy", ...
    'InputPRBCount',numel(prbs),'OutputPRBCount',numel(prbs),'MaximumPRBCount',NaN, ...
    'PHLowerBound_dB',NaN,'Margin_dB',NaN,'ReceiptSHA256',"", ...
    'Assumption',"unchanged_non_bandwidth_uncapped_power_terms_not_independently_measured");
p=sixgr.util.structGet(cfg,'phy.mac.uplinkControl',struct('Enabled',false));
if ~p.Enabled || p.PHRAllocationPolicy=="disabled", return; end
e=sixgr.util.structGet(ue,'ReceivedPHREvidence',struct('Usable',false,'Reason',"no_received_phr"));
r.Status=string(e.Reason); if ~e.Usable, return; end
report=e.Report;
if ~isfield(report,'ReferenceAllocation'), r.Status="missing_original_allocation_reference"; return; end
a=report.ReferenceAllocation;
if report.PowerBackoff || a.SubcarrierSpacing~=cfg.phy.carrier.SubcarrierSpacing || ...
        a.MCSIndex~=mcs.MCSIndex || string(a.MCSTable)~=string(mcs.MCSTable) || ...
        a.NumLayers~=layers || ~isequal(double(a.SymbolAllocation(:)),double(symbols(:))) || ...
        a.PowerConfigurationSHA256~=sixgr.l2.mac.MACHash.of(cfg.phy.pusch.powerControl)
    r.Status="received_phr_noncomparable_allocation_or_power_configuration"; return;
end
lower=double(report.PHRange_dB(1));
if ~isfinite(lower), r.Status="open_lower_PH_bin_no_finite_resource_bound"; return; end
validateattributes(a.NumPRB,{'numeric'},{'scalar','real','finite','integer','positive'});
cap=floor(double(a.NumPRB)*10.^((lower-p.PHRAllocationMargin_dB)/10));
assert(isfinite(cap)&&cap>=0,'sixgr:mac:PHRAllocationArithmetic','Finite nonnegative resource bound required.');
prbs=prbs(1:min(numel(prbs),cap));
r.Applied=true; r.Status="applied_constant_terms_policy_not_power_guarantee";
r.OutputPRBCount=numel(prbs); r.MaximumPRBCount=cap; r.PHLowerBound_dB=lower;
r.Margin_dB=p.PHRAllocationMargin_dB; r.ReceiptSHA256=report.ReceiptSHA256;
end
