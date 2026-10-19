function ok=testTransportGoodputAccounting()
% Declared CRC outcomes; not a physical campaign or calibration population.
T=table(["DL";"DL";"DL"],ones(3,1),ones(3,1),[3;1;2], ...
    ["original";"original";"original"],["a3";"a1";"a2"], ...
    [800;800;800],[1;0;1],[0;0;0], ...
    'VariableNames',{'Direction','UEIndex','SweepPointIndex','Slot', ...
    'LogicalTBID','TransmissionAttemptID','TBSize_bits','CRCPass','NDIEpoch'});
[out,L]=sixgr.kpi.creditTransportGoodput(T);
assert(isequaln(out(:,T.Properties.VariableNames),T),'CRC/PHY input must remain unchanged.');
assert(isequal(out.UniqueDeliveredTBBits,[0;0;800]) && numel(L.Key)==1);
assert(isequal(sixgr.kpi.transportGoodputBits(out(1,:)),0), ...
    'A sliced duplicate cannot acquire a new first-delivery credit.');
% Receiver availability, not input row order or transmission slot, controls
% batch attribution when a causal completion clock is explicitly retained.
timed=T; timed.DataDecodeAvailableAtSample=[10;20;30];
[a,~]=sixgr.kpi.creditTransportGoodput(timed);
assert(isequal(a.UniqueDeliveredTBBits,[800;0;0]));
% The streaming owner retains credit across separately completed attempts.
[first,L]=sixgr.kpi.creditTransportGoodput(T(3,:));
[retry,L]=sixgr.kpi.creditTransportGoodput(T(1,:),L);
assert(first.UniqueDeliveredTBBits==800 && retry.UniqueDeliveredTBBits==0 && numel(L.Key)==1);
% Same label on a different UE/direction/sweep/NDI generation is independent.
v=T(1,:); v.UEIndex=2; [a,L]=sixgr.kpi.creditTransportGoodput(v,L); assert(a.UniqueDeliveredTBBits==800);
v=T(1,:); v.Direction="UL"; [a,L]=sixgr.kpi.creditTransportGoodput(v,L); assert(a.UniqueDeliveredTBBits==800);
v=T(1,:); v.SweepPointIndex=2; [a,L]=sixgr.kpi.creditTransportGoodput(v,L); assert(a.UniqueDeliveredTBBits==800);
v=T(1,:); v.NDIEpoch=1; [a,L]=sixgr.kpi.creditTransportGoodput(v,L); assert(a.UniqueDeliveredTBBits==800);
assert(sum(L.PayloadBits)==4000);
% Current RNTI changes cannot repeat delivery to the same logical UE/TB.
v=T(1,:); v.RNTI=1234; [a,L]=sixgr.kpi.creditTransportGoodput(v,L); assert(a.UniqueDeliveredTBBits==0);
v.RNTI=4660; [a,~]=sixgr.kpi.creditTransportGoodput(v,L); assert(a.UniqueDeliveredTBBits==0);
v=T(1,:); v.TBSize_bits=808;
reject(@()sixgr.kpi.creditTransportGoodput(v,L),'sixgr:kpi:TransportGoodputPayloadMismatch');
v=T(1,:); v.TBId="different";
reject(@()sixgr.kpi.creditTransportGoodput(v),'sixgr:kpi:TransportGoodputIdentityMismatch');
% Missing identity is not reconstructed from an attempt, HARQ process, row
% number or throughput. Unknown CRC is not a success or a manufactured zero.
v=removevars(T(1,:),'LogicalTBID'); v.TBId=1; v.GoodBits=800; v.Goodput_Mbps=1.6;
a=sixgr.kpi.creditTransportGoodput(v); assert(isnan(a.UniqueDeliveredTBBits));
v=T(1,:); v.CRCPass=NaN; a=sixgr.kpi.creditTransportGoodput(v); assert(isnan(a.UniqueDeliveredTBBits));
v=T(1,:); v.SweepPointIndex=NaN; a=sixgr.kpi.creditTransportGoodput(v); assert(isnan(a.UniqueDeliveredTBBits));
v=out(1,:); v.UniqueDeliveredTBBits=800;
reject(@()sixgr.kpi.transportGoodputBits(v),'sixgr:kpi:InvalidTransportGoodputCredit');
% Existing credits still need their original CRC, payload and identity.
% A positive value and a PASS-like label alone are not receiver evidence.
v=out(3,:); v.UniqueDeliveredTBBits=400;
reject(@()sixgr.kpi.transportGoodputBits(v),'sixgr:kpi:InvalidTransportGoodputCredit');
v=out(3,:); v.CRCPass=0;
reject(@()sixgr.kpi.transportGoodputBits(v),'sixgr:kpi:InvalidTransportGoodputCredit');
v=out(1,:); v.CRCPass=NaN;
reject(@()sixgr.kpi.transportGoodputBits(v),'sixgr:kpi:InvalidTransportGoodputCredit');
v=out(3,:); v.LogicalTBID="unrelated";
reject(@()sixgr.kpi.transportGoodputBits(v),'sixgr:kpi:InvalidTransportGoodputCredit');
v=[out(3,:);out(3,:)];
reject(@()sixgr.kpi.transportGoodputBits(v),'sixgr:kpi:InvalidTransportGoodputCredit');
v=T(1,:); v.TBSBits=808;
reject(@()sixgr.kpi.creditTransportGoodput(v),'sixgr:kpi:TransportGoodputPayloadMismatch');
% The fixed-link producer has an explicit independent-TB (no HARQ) contract.
% Neither reused local TB labels nor reused slots merge different executions.
fixed=removevars(T(1,:),{'LogicalTBID','UEIndex','NDIEpoch','SweepPointIndex'});
fixed.FixedLinkCampaign=true;
fixed.FixedLinkCampaignKind="fixed_link_monte_carlo";
fixed.FixedLinkPointIndex=1; fixed.FixedLinkDropIndex=1;
fixed.FixedLinkTrialIndex=1; fixed.FixedLinkSeedIndex=1; fixed.FixedLinkSeedValue=0;
[a,L]=sixgr.kpi.creditTransportGoodput(fixed);
assert(a.UniqueDeliveredTBBits==800);
[a,L]=sixgr.kpi.creditTransportGoodput(fixed,L); assert(a.UniqueDeliveredTBBits==0);
fixed.FixedLinkTrialIndex=2;
[a,L]=sixgr.kpi.creditTransportGoodput(fixed,L); assert(a.UniqueDeliveredTBBits==800);
fixed.FixedLinkDropIndex=2;
[a,L]=sixgr.kpi.creditTransportGoodput(fixed,L); assert(a.UniqueDeliveredTBBits==800);
fixed.FixedLinkCampaignKind="unknown";
a=sixgr.kpi.creditTransportGoodput(fixed); assert(isnan(a.UniqueDeliveredTBBits));
fixed.FixedLinkCampaignKind="fixed_link_monte_carlo"; fixed.FixedLinkSeedValue=NaN;
a=sixgr.kpi.creditTransportGoodput(fixed); assert(isnan(a.UniqueDeliveredTBBits));
fixed.FixedLinkCampaign=false; fixed.FixedLinkSeedValue=1;
a=sixgr.kpi.creditTransportGoodput(fixed); assert(isnan(a.UniqueDeliveredTBBits), ...
    'Trial numbers without the producer contract cannot manufacture a logical TB.');
fprintf('TRANSPORT_GOODPUT_ACCOUNTING_PASS declared_outcomes_only=1\n'); ok=true;
end
function reject(f,id)
try, f(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s.',id,ex.identifier); return; end
error('test:ExpectedRejection','Expected %s.',id);
end
