function ok=testRLCAMReceiverState()
% Actual AMD/STATUS codec octets; declared MAC/sample boundary, no PHY claim.
for bits=[12 18]
    initial=2^bits-1;
    c=struct('BearerID',"b",'SNBits',bits,'InitialCount',initial,'ReassemblySamples',10, ...
        'StatusProhibitSamples',7,'ClockEpoch',2,'SampleRateHz',1e6);
    a=sixgr.l2.rlc18.RLCAMReceiverState(c);
    % Out-of-order complete SDU delivers immediately, starts gap timer.
    [a,done]=a.receive(pdu(bits,0,0,0,[],uint8([20 21])),1);
    assert(done.FullCount==initial+1 && a.RXNext==initial && a.nextTimerExpiry()==11);
    a=a.advance(11);assert(a.RXHighestStatus==initial+2 && a.StatusTriggered);
    tiny=a.previewStatus(3,11);assert(tiny.FullACKCount==initial && isempty(tiny.NACKs));
    full=a.previewStatus(20,11);decoded=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(full.Bytes,bits);
    assert(decoded.ACKSN==1 && decoded.NACKs.NACKSN==initial && a.pendingStatusBytes()==numel(full.Bytes));
    assert(isequaln(full,a.previewStatus(20,11))); % Withheld STATUS persists.
    [a,full]=a.prepareStatus(20,11);
    withheld=a.releasePreparedStatus(full);assert(withheld.StatusTriggered&&isinf(withheld.StatusProhibitDeadline));
    later=a.advance(12);later=later.commitStatus(full,receipt(full.Bytes,"later_submission",12));
    assert(later.StatusProhibitDeadline==19);
    [newer,~]=a.receive(pdu(bits,0,1,0,[],uint8([20 21])),12);
    newer=newer.commitStatus(full,receipt(full.Bytes,"old_bytes_new_trigger",12));
    assert(newer.StatusTriggered && newer.StatusProhibitDeadline==19);
    r=receipt(full.Bytes,"status1",11);b=a.commitStatus(full,r);
    assert(~b.StatusTriggered && b.StatusProhibitDeadline==18);
    reject(@()b.commitStatus(full,r));
    % Discarded duplicate poll coalesces until prohibit expiry.
    [b,done]=b.receive(pdu(bits,0,1,0,[],uint8([20 21])),12);
    assert(isempty(done)&&b.StatusTriggered&&b.pendingStatusBytes()==0&&b.nextTimerExpiry()==18);
    b=b.advance(18);assert(b.pendingStatusBytes()>0);
    % Original missing SDU arrives; receive window crosses modular wrap.
    [b,done]=b.receive(pdu(bits,initial,1,0,[],uint8([10 11])),18);
    assert(done.FullCount==initial&&b.RXNext==initial+2&&b.RXHighestStatus==initial+2);
    p=b.previewStatus(20,18);assert(isempty(p.NACKs)&&p.FullACKCount==initial+2);
    % Internal byte gap, no TX-known SDU extent; missing tail stays65535.
    z=sixgr.l2.rlc18.RLCAMReceiverState(c);
    [z,done]=z.receive(pdu(bits,initial,1,3,3,uint8([4 5])),0);
    assert(isempty(done)&&z.nextTimerExpiry()==10 && ~z.StatusTriggered && isequal(z.DelayedPolls,initial));
    % Fully duplicate bytes with a different final marker are discarded.
    originalRecord=z.Records{1};
    [duplicate,done]=z.receive(pdu(bits,initial,0,2,3,uint8([4 5])),1);
    assert(isempty(done)&&isequaln(duplicate.Records{1},originalRecord)&&duplicate.RXNext==initial);
    % Filling the observed internal gap cancels reassembly, even though the
    % unobserved tail is still unknown and the delayed poll remains delayed.
    [filled,done]=z.receive(pdu(bits,initial,0,1,[],uint8([1 2 3])),1);
    assert(isempty(done)&&isinf(filled.ReassemblyDeadline)&&~filled.StatusTriggered);
    z=z.advance(10);p=z.previewStatus(100,10);
    assert(numel(p.NACKs)==2 && p.NACKs(1).SOstart==0&&p.NACKs(1).SOend==2 && ...
        p.NACKs(2).SOstart==5&&p.NACKs(2).SOend==65535);
    firstOnly=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(bits,0,p.NACKs(1));
    limited=z.previewStatus(firstOnly.ByteCount,10);
    assert(limited.FullACKCount==initial && isempty(limited.NACKs)); % Never ACK an omitted gap of this SN.
    reject(@()z.receive(pdu(bits,initial,0,3,3,uint8([9 5])),10));
    [z,done]=z.receive(pdu(bits,initial,0,1,[],uint8([1 2 3])),10);assert(isempty(done));
    [z,done]=z.receive(pdu(bits,initial,0,2,5,uint8(6)),10);
    assert(isequal(done.Bytes,uint8(1:6))&&z.RXNext==initial+1);
end
ok=true;
end
function b=pdu(bits,sn,poll,si,so,data)
b=uint8([sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(bits,1,poll,si,sn,so) data]);
end
function r=receipt(bytes,id,sample)
r=struct('ID',id,'BearerID',"b",'Sample',sample,'ClockEpoch',2,'SampleRateHz',1e6, ...
    'Source',"actual_MAC_lower_layer_submission",'PayloadSHA256',sixgr.protocol.ProtocolHash.bytes(bytes));
end
function reject(fn)
try,fn();catch e,assert(startsWith(string(e.identifier),"sixgr:rlc:"));return;end
error('test:RXGuard','Expected original-receipt guard.');
end
