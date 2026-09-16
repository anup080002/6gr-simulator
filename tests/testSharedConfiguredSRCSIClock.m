function ok=testSharedConfiguredSRCSIClock()
% Real shared PUCCH execution with initialized SR state and installed calendar.
% CSI/DL inputs remain declared by the parent fixture. This does NOT qualify
% independent gNB schema selection, positive MAC SR lifecycle or 12 dB.
for harq=[false true]
    assert(testSharedCSIReportClock("TDD",harq,false,@audit,'lls_tdd_shared_csi_sr_fixture.yaml'));
end
fprintf('SHARED_CONFIGURED_SR_CSI_CLOCK_PASS CSI_only_and_HARQ_CSI=1 negative_SR_on_wire=1 independent_gNB_qualified=0\n');
ok=true;
end
function audit(state,item)
c=item.Context; p=c.Prepared;
context=p.RequestBinding.ReceiverContext;
assert(context.SRBits==1 && context.Sequence1Length==context.CSIPart1Bits+context.HARQACKBits+1);
assert(isequal(p.RequestBinding.Report.Data.SchedulingRequestReports.Bits,int8(0)));
assert(~isfield(c,'GNBReception'),'Update this component audit when independent normal scheduling is integrated.');
snapshot=c.UETransmitFrameState.SchedulingRequestStates;
assert(isscalar(snapshot) && ~snapshot.Data.PendingPositiveSR && snapshot.Data.AbsoluteSlot==c.Slot-1);
[~,~,~,~,actual]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
before=rng;
rx=sixgr.link.receivePUCCHObservation(c.Config,p.RequestBinding.Assignment,context,actual);
assert(isequal(before,rng) && rx.ReceiverUsable && ~rx.DTX && isequal(rx.DecodedFields.SR,int8(0)));
assert(~rx.IndependentReceiverAssignment); % Do not mislabel known TX-context limitation.
assert(isfield(state,'UEConfiguredSRProcedures'));
fprintf('SHARED_SR_WIRE_RECEIVED harq=%d csi=%d sr=%d total=%d\n', ...
    context.HARQACKBits,context.CSIPart1Bits,context.SRBits,context.Sequence1Length);
end
