function assertPUSCHUCIReservationOwner(row,contextID,kind,bitIndex)
% Reconciliation may repeat the same reservation; it cannot steal another
% live grant's payload or resurrect a terminal no-TX/expired producer.
if nargin<4, bitIndex=NaN; end
id='sixgr:truth:PUSCHUCIReservationOwnership';
assert(istable(row)&&height(row)==1 && isscalar(string(contextID)) && ...
    strlength(strtrim(string(contextID)))>0,id,'One original producer and nonempty frozen PUSCH context are required.');
names=string(row.Properties.VariableNames);
for flag=["Processed","RightCensored","UETransmissionSuppressed","UECSIPayloadRetired"]
    if ismember(flag,names)
        v=row.(flag);
        assert((islogical(v)||isnumeric(v))&&isscalar(v)&&isreal(v)&&isfinite(v)&&v==0,id, ...
            'Terminal, withheld, retired or censored UCI cannot be reserved again.');
    end
end
if ismember("UEProducerDisposition",names)
    assert(~startsWith(string(row.UEProducerDisposition),"closed_untransmitted"),id, ...
        'A closed physical occasion requires a fresh producer, not resurrection.');
end
kind=string(kind);
if kind=="csi"
    required=["CSIUCITransport","CSIUCIPUSCHGrantContextId","CSIUCIMultiplexedOnPUSCH"];
    assert(all(ismember(required,names)),id,'Retain complete CSI reservation ownership.');
    old=string(row.CSIUCIPUSCHGrantContextId); active=binary(row.CSIUCIMultiplexedOnPUSCH,id);
    transport=string(row.CSIUCITransport);
    assert((~active && strlength(old)==0 && transport=="pucch") || ...
        (active && old==string(contextID) && transport=="pusch_bound"),id, ...
        'Only the existing identical PUSCH may reuse a bound CSI report; release it explicitly first.');
elseif any(kind==["pending_harq","trace_harq"])
    required=["PUSCHGrantContextId","MultiplexedBitIndex"];
    assert(all(ismember(required,names)),id,'Retain complete HARQ reservation ownership.');
    old=string(row.PUSCHGrantContextId);
    if kind=="pending_harq"
        assert(ismember("DeliveryMechanism",names),id,'Retain original transport.');
        active=string(row.DeliveryMechanism)=="pusch_uci";
        unbound=string(row.DeliveryMechanism)=="pucch";
    else
        assert(ismember("MultiplexedOnPUSCH",names),id,'Retain original transport.');
        active=binary(row.MultiplexedOnPUSCH,id); unbound=~active;
    end
    assert(isfinite(bitIndex)&&bitIndex>=1&&bitIndex==fix(bitIndex),id,'Retain the received-codebook bit position.');
    assert((unbound && strlength(old)==0) || ...
        (active && old==string(contextID) && row.MultiplexedBitIndex==bitIndex),id, ...
        'A live HARQ bit belongs to one PUSCH context/position until explicitly released.');
else
    error(id,'Unknown UCI ownership domain.');
end
end
function value=binary(value,id)
assert((isnumeric(value)||islogical(value))&&isscalar(value)&&isreal(value)&& ...
    isfinite(value)&&any(value==[0 1]),id,'Transport markers must retain an explicit binary value.');
value=logical(value);
end
