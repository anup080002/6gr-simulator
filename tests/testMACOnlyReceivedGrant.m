function ok=testMACOnlyReceivedGrant()
% Declared received-assignment/decoder-byte boundary, not an RF qualification.
c=struct('enabled',true,'strict',true,'configuration_epoch',1);
c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8);
c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0','t_reordering_ms',50);
c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
c.mac=struct('lcid',4);c.traffic.sessions=struct('flow_id','data','pdu_session_id',1,'qfi',9,'direction','UL');
b=sixgr.protocol.WaveformProtocolBridge(c,1);
authority=struct('Stage',"original_received_DCI_empty_UE_L2",'UEIndex',1,'TBSBits',256, ...
    'AssignmentDigest',string(repmat('a',1,64)));
[bits,e]=b.prepareMACOnlyTransportBlock(1,'padding',256,authority);
assert(e.TransportKind=="MAC_CE_PADDING"&&e.ControlOnly&&e.PayloadBits==0);
bytes=bytesOf(bits);assert(isequal(bytes,uint8([63 zeros(1,31)])));
padding=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytes);
assert(isempty(padding.SubPDUs)&&isfield(padding.SubPDUs,'Kind')&&padding.PaddingBytes==32);
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==0);
b.commitPreparedTransportBlock('padding',.001);
failed=b.previewMACControlDecoded('padding',[],false,.002);
x=b.commitReceivedReverseStatus(failed);assert(x.ApplicationPayloadBytes==0);
bad=bits;bad(1)=1-bad(1);rejects(@()b.previewMACControlDecoded('padding',bad,true,.002));
candidate=b.previewMACControlDecoded('padding',bits,true,.002);
x=b.commitReceivedReverseStatus(candidate);assert(x.Status=="original_crc_confirmed_MAC_CE_PADDING");
x=b.commitReceivedReverseStatus(b.previewMACControlDecoded('padding',bits,true,.003));
assert(x.Status=="duplicate_MAC_control_no_state_update");
rejects(@()b.previewReverseStatusDecoded('padding',bits,true,.004));
% Original CE-only report remains MAC control, never an invented RLC STATUS.
[~,~]=b.prepareMACOnlyTransportBlock(1,'ce',256,authority);
ce=struct('LCID',57,'Payload',reshape(sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(-2,23,false),1,[]),'OwnerID',"ph");
a=struct('Stage',"original_received_DCI_before_first_TX",'AssignmentDigest',authority.AssignmentDigest, ...
    'OriginalGrantContextID',string(repmat('b',1,64)),'TBSBits',256,'IsNewData',true);
[wire,receipt]=b.finalizeULControl('ce',ce,a);
mac=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytesOf(wire));
assert(numel(mac.SubPDUs)==1&&mac.SubPDUs(1).LCID==57&&receipt.ApplicationPayloadBits==0);
b.commitPreparedTransportBlock('ce',.004);
candidate=b.previewMACControlDecoded('ce',wire,true,.005);
s=struct('RunID',"run",'ExecutionID',"exec",'ConfigHash',"cfg",'UEID',1,'CellID',1,'RNTI',4660,'ConfigurationEpoch',1,'SampleRateHz',1000);
ph=sixgr.l2.mac.ReceivedPHRState(s);bs=sixgr.l2.mac.ReceivedULBufferState(s);
rx=struct('Scope',s,'Direction',"UL",'CRCPass',true,'LogicalTBID',"ce",'TransmissionID',"tx-ce", ...
    'ReferenceGrantContextID',"g",'OriginalTransmissionStartSample',4,'ObservationEndSampleExclusive',5,'AvailableSample',5, ...
    'DecodedRLCPayloadBytes',0,'DecodedRLCStatusBytes',0,'DecodedMACSHA256',receipt.MACSHA256);
[p,~]=ph.previewAdmission(wire,rx);[q,~]=bs.previewAdmission(wire,rx);
sixgr.truth.commitReceivedMACAdmissions(b,candidate,ph,p,bs,q);
assert(numel(ph.Reports)==1&&bs.Debits{1}.ReceivedL2DebitBytes==0&&isempty(bs.BSR));
% Actual remaining L2 bytes must never be replaced by a padding rescue.
b.enqueuePacket(1,'UL','original',uint8(1:8),.006);
rejects(@()b.prepareMACOnlyTransportBlock(1,'wrong',256,authority));
% A small original MAC CE budget defers a trigger; it cannot overflow TBS.
uePH=sixgr.l2.mac.PHRStateMachine(1,20);uePH.trigger('configuration',0);
ueBS=sixgr.l2.mac.BSRStateMachine(1,1,10,80);ueBS.arrival(0,4);
power=struct('Enabled',true,'RequestedPower_dBm',25,'Pcmax_dBm',23,'PowerHeadroom_dB',-2);
policy=struct('PHRProhibitSlots',0);a.PowerManagementBackoffApplied=false;
for budget=[1 2 3 5]
    t=sixgr.l2.mac.prepareULMACControlTransaction(uePH,ueBS,power,0,1,policy,a,budget);
    assert(t.BSRReport.Transmit==(budget>=2)&&t.PHRReport.Transmit==(budget>=5));
    assert(uePH.PendingTrigger=="configuration"&&ueBS.PendingTrigger=="regular");
end
ok=true;
end
function bytes=bytesOf(bits)
bytes=uint8(double(reshape(bits,8,[]).')*(2.^(7:-1:0)).');bytes=bytes(:).';
end
function rejects(f)
failed=false;try,f();catch,failed=true;end;assert(failed);
end
