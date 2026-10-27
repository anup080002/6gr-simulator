function ok=testPUSCHUCIReservationOwnership()
% Declared state-transition contract; no PHY receive result is manufactured.
row=table("pucch","",NaN,false,false,'VariableNames', ...
    {'DeliveryMechanism','PUSCHGrantContextId','MultiplexedBitIndex','Processed','RightCensored'});
sixgr.truth.assertPUSCHUCIReservationOwner(row,"original_grant_A","pending_harq",2);
row.DeliveryMechanism="pusch_uci"; row.PUSCHGrantContextId="original_grant_A"; row.MultiplexedBitIndex=2;
sixgr.truth.assertPUSCHUCIReservationOwner(row,"original_grant_A","pending_harq",2);
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(row,"other_grant_B","pending_harq",2));
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(row,"original_grant_A","pending_harq",1));
% An explicit release removes reservation identity before a new owner acts.
row.DeliveryMechanism="pucch"; row.PUSCHGrantContextId=""; row.MultiplexedBitIndex=NaN;
sixgr.truth.assertPUSCHUCIReservationOwner(row,"other_grant_B","pending_harq",1);
row.Processed=true;
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(row,"other_grant_B","pending_harq",1));
row.Processed=false; row.UEProducerDisposition="closed_untransmitted_missing_measured_power_reference";
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(row,"other_grant_B","pending_harq",1));
csi=table("pucch","",false,false,false,'VariableNames', ...
    {'CSIUCITransport','CSIUCIPUSCHGrantContextId','CSIUCIMultiplexedOnPUSCH','Processed','UECSIPayloadRetired'});
sixgr.truth.assertPUSCHUCIReservationOwner(csi,"A","csi");
csi.CSIUCITransport="pusch_bound"; csi.CSIUCIPUSCHGrantContextId="A"; csi.CSIUCIMultiplexedOnPUSCH=true;
sixgr.truth.assertPUSCHUCIReservationOwner(csi,"A","csi");
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(csi,"B","csi"));
csi.UECSIPayloadRetired=true;
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(csi,"A","csi"));
trace=table("A",2,true,false,'VariableNames', ...
    {'PUSCHGrantContextId','MultiplexedBitIndex','MultiplexedOnPUSCH','UETransmissionSuppressed'});
sixgr.truth.assertPUSCHUCIReservationOwner(trace,"A","trace_harq",2);
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(trace,"B","trace_harq",2));
trace.UETransmissionSuppressed=true;
reject(@()sixgr.truth.assertPUSCHUCIReservationOwner(trace,"A","trace_harq",2));
ok=true; disp('PUSCH_UCI_RESERVATION_OWNERSHIP_PASS');
end
function reject(fn)
try, fn(); catch e
    assert(strcmp(e.identifier,'sixgr:truth:PUSCHUCIReservationOwnership')); return;
end
error('test:MissingUCIOwnershipGuard','A stale/foreign reservation was accepted.');
end
