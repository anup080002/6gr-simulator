function ok=testWaveformProtocolCrossBearerCompletion()
% Authored decoded-byte boundary; no physical waveform qualification.
c=struct('enabled',true,'strict',true,'configuration_epoch',1);
c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8);
c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0','t_reordering_ms',50);
c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
c.mac=struct('lcid',4); c.traffic.sessions=struct('flow_id','f','pdu_session_id',1,'qfi',9,'direction','BIDIR');
for sameBytes=[false true]
    for otherDirection=[false true]
        b=sixgr.protocol.WaveformProtocolBridge(c,2);
        first=uint8(1:8); other=uint8(21:28); if sameBytes, other=first; end
        ue=2; direction="UL"; if otherDirection, ue=1; direction="DL"; end
        % UE1/UL SN1 decodes while its SN0 is genuinely absent. Another
        % bearer may use the same application ID and even the same bytes.
        b.enqueuePacket(1,'UL','gap',uint8(41:48),0);
        [gap,~]=b.prepareQueuedSegment(1,'UL','gap-tb',160,.001,0);
        b.commitPreparedTransportBlock('gap-tb',.002);
        b.enqueuePacket(1,'UL','same-id',first,.003);
        [waiting,~]=b.prepareQueuedSegment(1,'UL','waiting-tb',160,.004,0);
        b.commitPreparedTransportBlock('waiting-tb',.005);
        b.enqueuePacket(ue,direction,'same-id',other,0);
        [foreign,~]=b.prepareQueuedSegment(ue,direction,'other-tb',160,.001,0);
        b.commitPreparedTransportBlock('other-tb',.002);
        [done,e]=b.deliverDecoded('waiting-tb',waiting,.010);
        assert(~done&&isempty(e.CompletedTransportBlocks));
        [done,e]=b.deliverDecoded('other-tb',foreign,.011);
        assert(done&&numel(e.CompletedTransportBlocks)==1&&e.CompletedTransportBlocks.TransportBlockId=="other-tb");
        failed=false; try, b.reassembleDecodedApplication("waiting-tb",8); catch, failed=true; end
        assert(failed,'A foreign bearer completion must not release the retained gap-blocked packet.');
        [actual,h]=b.reassembleDecodedApplication("other-tb",8);
        assert(isequal(actual,other)&&h==sixgr.protocol.ProtocolHash.bytes(other));
        [done,e]=b.deliverDecoded('gap-tb',gap,.012);
        assert(done&&numel(e.CompletedTransportBlocks)==2&& ...
            isequal(sort(string({e.CompletedTransportBlocks.TransportBlockId})),sort(["gap-tb","waiting-tb"])));
        [actual,h]=b.reassembleDecodedApplication("waiting-tb",8);
        assert(isequal(actual,first)&&h==sixgr.protocol.ProtocolHash.bytes(first));
    end
end
ok=true;
end
