function ok=testReceivedMACJointStatusTransaction()
% Authored decoder-byte boundary, not a received waveform qualification.
for kind=["bad_phr","bad_bsr","duplicate_bsr","stale","valid"]
    [b,bits,scope,rx]=fixture(kind);
    ph=sixgr.l2.mac.ReceivedPHRState(scope); bs=sixgr.l2.mac.ReceivedULBufferState(scope);
    before=b.pendingTransmitBytes(1,'DL');
    reverse=b.previewReverseStatusDecoded('reverse',bits,true,.041);
    rejected=false;
    try
        [a,~]=ph.previewAdmission(bits,rx); [c,~]=bs.previewAdmission(bits,rx);
        if kind=="stale", b.advance(.042); end
        sixgr.truth.commitReceivedMACAdmissions(b,reverse,ph,a,bs,c);
    catch e
        rejected=true;
        assert(kind~="valid",'Unexpected %s: %s',e.identifier,e.message);
    end
    if kind=="valid"
        assert(~rejected&&numel(ph.Reports)==1&&numel(bs.BSR)==1);
        assert(b.pendingTransmitBytes(1,'DL').AMRetransmissionBytes==30);
        assert(bs.Debits{1}.SDUBytes==0&&bs.Debits{1}.RLCStatusBytes>0);
    else
        assert(rejected&&isempty(ph.Reports)&&isempty(bs.BSR)&&isempty(bs.Debits));
        assert(isequal(before,b.pendingTransmitBytes(1,'DL')));
        if kind~="stale"
            % A rejected CE must not invalidate the still-uncommitted STATUS base.
            b.validateReceivedReverseStatus(reverse);
        end
        b.cancelReceivedReverseStatus(reverse);
    end
end
ok=true;
end
function [b,bits,s,rx]=fixture(kind)
c=struct('enabled',true,'strict',true,'configuration_epoch',1,'sample_rate_hz',1000,'clock_epoch',1);
c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8, ...
    'arq_enabled',true,'t_poll_retransmit_ms',45,'t_reassembly_ms',35,'t_status_prohibit_ms',0);
c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0','t_reordering_ms',50);
c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
c.mac=struct('lcid',4); c.traffic.sessions=struct('flow_id','data','pdu_session_id',1,'qfi',9,'direction','BIDIR');
b=sixgr.protocol.WaveformProtocolBridge(c,1); b.enqueuePacket(1,'DL','app',uint8(1:35),0);
for k=1:3
    [wire,~]=b.prepareQueuedSegment(1,'DL',"tb-"+k,168,k*.001,0);
    b.commitPreparedTransportBlock("tb-"+k,k*.001);
end
b.deliverDecoded('tb-3',wire,.004); b.advance(.039);
[~,e]=b.prepareReverseStatusTransportBlock(1,'UL','reverse',384,.039,10);
items(1)=struct('LCID',57,'Payload',reshape(sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(-2,23,false),1,[]),'OwnerID',"ph");
items(2)=struct('LCID',61,'Payload',sixgr.l2.mac.BSR_PHR.encodeShortBSR(0,100),'OwnerID',"bs");
if kind=="bad_phr", items(1).Payload=uint8([0 255]); end
if kind=="bad_bsr", items(2).LCID=59; end
if kind=="duplicate_bsr", items(3)=items(2); items(3).OwnerID="duplicate"; end
authority=struct('Stage',"original_received_DCI_before_first_TX", ...
    'AssignmentDigest',string(repmat('a',1,64)),'OriginalGrantContextID',string(repmat('b',1,64)), ...
    'TBSBits',384,'IsNewData',true);
[bits,receipt]=b.finalizeULControl('reverse',items,authority);
b.commitPreparedTransportBlock('reverse',.040);
s=struct('RunID',"run",'ExecutionID',"exec",'ConfigHash',"cfg",'UEID',1, ...
    'CellID',1,'RNTI',4660,'ConfigurationEpoch',1,'SampleRateHz',1000);
rx=struct('Scope',s,'Direction',"UL",'CRCPass',true,'LogicalTBID',"reverse", ...
    'TransmissionID',"tx-reverse",'ReferenceGrantContextID',"original-g", ...
    'OriginalTransmissionStartSample',40,'ObservationEndSampleExclusive',41,'AvailableSample',41, ...
    'DecodedRLCPayloadBytes',0,'DecodedRLCStatusBytes',e.SegmentPayloadBytes,'DecodedMACSHA256',receipt.MACSHA256);
end
