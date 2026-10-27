function ok=testWaveformProtocolReverseStatus()
% Original encoded/decoded-byte boundary; no waveform reception claim.
for direction=["DL","UL"]
    reverse="UL"; if direction=="UL", reverse="DL"; end
    c=struct('enabled',true,'strict',true,'configuration_epoch',1,'sample_rate_hz',1000,'clock_epoch',1);
    c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8, ...
        'arq_enabled',true,'t_poll_retransmit_ms',45,'t_reassembly_ms',35,'t_status_prohibit_ms',0);
    c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0','t_reordering_ms',50);
    c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
    c.mac=struct('lcid',4); c.traffic.sessions=struct('flow_id','data-1','pdu_session_id',1,'qfi',9,'direction','BIDIR');
    b=sixgr.protocol.WaveformProtocolBridge(c,2);
    b.enqueuePacket(1,direction,'original',uint8(1:35),0);
    wire={}; ids=strings(0,1);
    for k=1:3
        ids(k,1)="data-"+k;
        [wire{k},~]=b.prepareQueuedSegment(1,direction,ids(k),168,k*.001,0); %#ok<AGROW>
        b.commitPreparedTransportBlock(ids(k),k*.001);
    end
    assert(b.pendingTransmitBytes(1,direction).TotalBSRBytes==0);
    [delivered,~]=b.deliverDecoded(ids(3),wire{3},.004); assert(~delivered);
    b.advance(.039);
    assert(b.pendingReverseStatusBytes(1,reverse)>0);
    assert(b.pendingReverseStatusBytes(1,direction)==0&&b.pendingReverseStatusBytes(2,reverse)==0);
    [withheld,e]=b.prepareReverseStatusTransportBlock(1,reverse,'withheld',256,.039);
    assert(e.ControlOnly&&e.ApplicationPayloadBytes==0&&e.PayloadBits==0&&e.DataDirection==direction);
    b.cancelPreparedTransportBlock('withheld');
    assert(b.pendingReverseStatusBytes(1,reverse)>0&&b.pendingTransmitBytes(1,direction).AMRetransmissionBytes==0);
    [bits,~]=b.prepareReverseStatusTransportBlock(1,reverse,'sent',256,.040);
    assert(isequal(bits,withheld),'Withholding must preserve original receiver STATUS octets.');
    bad=bits; bad(1)=1-bad(1);
    mustFail(@()b.validatePreparedTransportBlock('sent',.040,bad),'sixgr:protocol:OriginalMACCommitMismatch');
    b.validatePreparedTransportBlock('sent',.040,bits); b.commitPreparedTransportBlock('sent',.040);
    x=b.receiveReverseStatusDecoded('sent',[],false,.041);
    assert(x.ControlOnly&&x.ApplicationPayloadBytes==0&&b.pendingTransmitBytes(1,direction).AMRetransmissionBytes==0);
    mustFail(@()b.receiveReverseStatusDecoded('sent',bad,true,.041),'sixgr:protocol:DecodedTransportBlockMismatch');
    x=b.receiveReverseStatusDecoded('sent',bits,true,.041);
    assert(x.Status=="original_crc_confirmed_reverse_STATUS"&&isempty(x.CompletedTransportBlocks));
    volume=b.pendingTransmitBytes(1,direction);
    assert(volume.AMRetransmissionBytes==30&&b.pendingTransmitBytes(2,direction).TotalBSRBytes==0);
    x=b.receiveReverseStatusDecoded('sent',bits,true,.042);
    assert(x.Status=="duplicate_STATUS_no_state_update"&&isequal(volume,b.pendingTransmitBytes(1,direction)));
    mustFail(@()b.cancelPreparedTransportBlock('sent'),'sixgr:protocol:LateMACCancellation');
end
ok=true;
end
function mustFail(f,id)
try, f(); error('test:ExpectedFailure','Expected %s',id);
catch e, assert(strcmp(e.identifier,id),'Expected %s, got %s: %s',id,e.identifier,e.message); end
end
