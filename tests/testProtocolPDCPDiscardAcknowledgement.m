function ok=testProtocolPDCPDiscardAcknowledgement()
% Original RLC receiver-generated STATUS at a declared MAC codec boundary.
% These are clock/owner checks, not RF/CRC population measurements.
setup6GRSimToolkit('Verbose',false);
for acknowledgedAt=[.009 .010 .011]
    cfg=config();rt=sixgr.protocol.ProtocolRuntime(cfg);
    rt.enqueuePacket('original',uint8(1:16),0);
    p=rt.prepareSegment(128,0);p=wrapMAC(p);
    assert(rt.receive(p,.002));
    status=rt.prepareReverseStatus(64,.003);
    assert(~isempty(fieldnames(status)));
    rt.commitReverseStatus(status,'original-status-tx',.003);
    assert(abs(rt.nextTimerExpiry()-.010)<1e-12);
    rt.receiveReverseStatus(status.Bytes,'original-status-rx',acknowledgedAt);
    events=rt.takeDiscardEvents();
    if acknowledgedAt<.010
        assert(isempty(events),'Original received ACK before expiry must stop the timer.');
    else
        assert(numel(events)==1&&events.DeadlineSample==10&& ...
            events.ObservedAtSample==round(acknowledgedAt*1000)&&events.ApplicationBytesDropped==0&& ...
            events.LowerLayerDisposition=="retained_already_handed_to_lower_layer");
    end
    rt.receiveReverseStatus(status.Bytes,'original-status-rx',.012);
    assert(isempty(rt.advance(.020))&&isempty(rt.takeDiscardEvents()));
    c=rt.conservation();assert(c.DeliveredBytes==16&&c.DroppedBytes==0&&c.EquationErrorBytes==0);
end
% Legacy fragments were immediately submitted to MAC. Timer expiry may
% discard the PDCP TX copy but must leave original RLC bytes receivable.
cfg=config();cfg.RLCARQEnabled=false;rt=sixgr.protocol.ProtocolRuntime(cfg);
p=rt.transmit('legacy',uint8(4:19),.001);
assert(isempty(rt.advance(.011)));
events=rt.takeDiscardEvents();assert(numel(events)==1&&events.PacketizationMode=="legacy_fragment"&&events.ApplicationBytesDropped==0);
assert(rt.receive(p,.012));
c=rt.conservation();assert(c.DeliveredBytes==16&&c.DroppedBytes==0);
% A genuine wholly unsent terminal discard is not reversible by a late
% or forged delivery callback.
ledger=sixgr.protocol.ProtocolLineageLedger();
ledger.addPacket(struct('PacketID',"dropped",'PacketBytes',1,'PayloadSHA256',sixgr.protocol.ProtocolHash.bytes(uint8(1))));
ledger.drop('dropped');
expectError(@()ledger.deliver('dropped'),'sixgr:protocol:ConservationFailure');
fprintf('PDCP_DISCARD_ACK_CLOCK_PASS before_exact_after_deadline=1 original_STATUS_only=1 no_RF_claim=1\n');
ok=true;
end
function p=wrapMAC(p)
mac=sixgr.l2.mac.MACPDUAssembler.assemble(p.Direction, ...
    struct('LCID',p.LCID,'Payload',p.Bytes,'OwnerID',p.PacketID),numel(p.Bytes)+3);
p.MACBytes=mac.Bytes;p.MACSHA256=mac.SHA256;
end
function cfg=config()
cfg=struct('UEID',"UE-001",'BearerID',"DRB-1",'Direction',"DL",'QFI',9,'DRBID',1, ...
 'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18,'ConfigurationEpoch',1, ...
 'SampleRateHz',1000,'ClockEpoch',1,'DiscardTime_s',.010,'ReorderingTime_s',.002, ...
 'RLCARQEnabled',true,'RLCPollRetransmit_s',.045,'RLCReassembly_s',.002,'RLCStatusProhibit_s',0);
end
function expectError(f,id)
try,f();catch ex,assert(string(ex.identifier)==id,ex.message);return;end
error('sixgr:test:MissingDiscardGuard','Expected %s.',id);
end
