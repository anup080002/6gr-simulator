function evidence=assertOriginalReceivedPHRAllocation(state,requireEffectiveCap)
% Join actual shared MAC chain receipt to original issued/executed grant.
% Applied policy and an effective resource reduction are separate coverage.
if nargin<2, requireEffectiveCap=false; end
reports=state.SharedGNBPHRStates{1}.Reports;
T=state.TestMACUL; applied=0;effective=0; ids=strings(0,1);
assert(ismember('ReceivedPHRAllocationJSON',T.Properties.VariableNames), ...
    'test:PHRProjectionMissing','Actual UL trial must retain original allocation receipt.');
for k=1:height(T)
    text=string(T.ReceivedPHRAllocationJSON(k));
    if strlength(text)==0,continue;end
    assert(string(T.ReceivedPHRAllocationSHA256(k))==string(sixgr.util.sha256Hex(char(text))));
    a=jsondecode(text); if ~a.Applied,continue;end
    hit=find(cellfun(@(p) string(p.ReceiptSHA256)==string(a.ReceiptSHA256),reports));
    assert(isscalar(hit),'test:PHROriginalReceipt','Applied allocation must join one actual CRC-decoded PHR.');
    p=reports{hit};assert(string(p.ReceiptSHA256)==sixgr.l2.mac.MACHash.of(rmfield(p,'ReceiptSHA256')));
    assert(string(a.Source)=="received_PHR_constant_terms_quantized_lower_bound_policy"&& ...
        string(a.Assumption)=="unchanged_non_bandwidth_uncapped_power_terms_not_independently_measured");
    cap=floor(double(p.ReferenceAllocation.NumPRB)*10^((double(p.PHRange_dB(1))-a.Margin_dB)/10));
    assert(isfinite(cap)&&cap==a.MaximumPRBCount&&a.PHLowerBound_dB==p.PHRange_dB(1));
    assert(a.OutputPRBCount==min(a.InputPRBCount,cap));
    issued=find(cellfun(@(g) isfield(g,'ReceivedPHRAllocation')&& ...
        string(jsonencode(g.ReceivedPHRAllocation))==text,state.TestMACIssued));
    assert(~isempty(issued),'test:PHRIssuedGrant','Executed receipt must remain original issued-control grant metadata.');
    applied=applied+1;effective=effective+(a.OutputPRBCount<a.InputPRBCount);
    ids(end+1,1)=string(a.ReceiptSHA256); %#ok<AGROW>
end
assert(applied>0,'test:PHRNotApplied','Receiving PHR alone is not later allocation use.');
if requireEffectiveCap
    assert(effective>0,'test:PHRCapNotExercised','Applied but nonbinding PHR policy does not prove resource restriction.');
end
evidence=struct('AppliedExecutedRows',applied,'EffectiveCapRows',effective, ...
    'OriginalReceivedPHRReceiptSHA256',ids,'Scope',"configured_constant_terms_model_not_power_guarantee");
end
