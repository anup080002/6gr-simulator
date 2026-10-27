function ok=testReceivedULMACTransaction()
% Original authored decoded bytes, not a physical PUSCH qualification.
s=struct('RunID',"run",'ExecutionID',"exec",'ConfigHash',"cfg",'UEID',1, ...
    'CellID',1,'RNTI',4660,'ConfigurationEpoch',1,'SampleRateHz',1000);
ph=sixgr.l2.mac.ReceivedPHRState(s); bs=sixgr.l2.mac.ReceivedULBufferState(s);
items(1)=struct('LCID',57,'Payload',reshape(sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(-2,23,false),1,[]),'OwnerID',"ph");
items(2)=struct('LCID',61,'Payload',sixgr.l2.mac.BSR_PHR.encodeShortBSR(0,100),'OwnerID',"bs");
mac=sixgr.l2.mac.MACPDUAssembler.assemble('UL',items,20); bits=bitsOf(mac.Bytes);
rx=struct('Scope',s,'Direction',"UL",'CRCPass',true,'LogicalTBID',"tb1", ...
    'TransmissionID',"tx1",'ReferenceGrantContextID',"g1", ...
    'OriginalTransmissionStartSample',20,'ObservationEndSampleExclusive',25,'AvailableSample',30, ...
    'DecodedRLCPayloadBytes',8,'DecodedMACSHA256',mac.SHA256);
[a,~]=ph.previewAdmission(bits,rx); [b,~]=bs.previewAdmission(bits,rx);
assert(isempty(ph.Reports)&&isempty(bs.BSR)&&isempty(bs.Debits));
assert(bs.estimate(s,29,100,64).BudgetBytes==0);
ph.validateAdmission(a); bs.validateAdmission(b); ph.commitAdmission(a); bs.commitAdmission(b);
assert(numel(ph.Reports)==1&&numel(bs.BSR)==1&&numel(bs.Debits)==1);
expected=bs.estimate(s,30,100,64).BudgetBytes; assert(expected>0&&expected<=100);
assert(bs.estimate(s,29,100,64).BudgetBytes==0);
% Same-TB duplicate success cannot double-debit or refresh its original age.
later=rx; later.AvailableSample=40; later.ObservationEndSampleExclusive=35;
[a,~]=ph.previewAdmission(bits,later); [b,~]=bs.previewAdmission(bits,later);
ph.commitAdmission(a); bs.commitAdmission(b);
assert(numel(ph.Reports)==1&&numel(bs.Debits)==1&&bs.estimate(s,40,100,64).BudgetBytes==expected);
% A newer decoded SDU debit becomes visible only at its receive availability.
only=struct('LCID',4,'Payload',uint8([128 0 0 1:8]),'OwnerID',"rlc");
data=sixgr.l2.mac.MACPDUAssembler.assemble('UL',only,20);
next=rx; next.LogicalTBID="tb2"; next.TransmissionID="tx2";
next.OriginalTransmissionStartSample=35; next.ObservationEndSampleExclusive=40; next.AvailableSample=50;
next.DecodedMACSHA256=data.SHA256;
[b,~]=bs.previewAdmission(bitsOf(data.Bytes),next); bs.commitAdmission(b);
assert(bs.estimate(s,49,100,64).BudgetBytes==expected);
assert(bs.estimate(s,50,100,64).BudgetBytes==max(0,expected-8));
% CRC failure cannot introduce either CE or a decoded debit.
failed=next; failed.LogicalTBID="failed"; failed.CRCPass=false;
[a,~]=ph.previewAdmission([],failed); [b,~]=bs.previewAdmission([],failed);
ph.commitAdmission(a); bs.commitAdmission(b); assert(numel(bs.Debits)==2&&numel(ph.Reports)==1);
% Invalid second CE is detected before either candidate is committed.
badItems=items; badItems(2).LCID=59;
bad=sixgr.l2.mac.MACPDUAssembler.assemble('UL',badItems,20);
badRx=rx; badRx.LogicalTBID="malformed-second";
ph.previewAdmission(bitsOf(bad.Bytes),badRx);
rejects(@()bs.previewAdmission(bitsOf(bad.Bytes),badRx));
assert(numel(ph.Reports)==1&&numel(bs.BSR)==1);
wrong=rx; wrong.Scope.CellID=2; rejects(@()ph.previewAdmission(bits,wrong));
wrong=rx; wrong.AvailableSample=24; rejects(@()bs.previewAdmission(bits,wrong));
% Received STATUS bytes retire previously reported L2 demand, not app bytes.
status=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(18,1,struct([]));
statusMAC=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
    struct('LCID',4,'Payload',status.Bytes,'OwnerID',"original-status"),20);
control=next; control.LogicalTBID="status-only"; control.TransmissionID="tx-status";
control.OriginalTransmissionStartSample=55; control.ObservationEndSampleExclusive=60; control.AvailableSample=65;
control.DecodedRLCPayloadBytes=0; control.DecodedRLCStatusBytes=numel(status.Bytes);
control.DecodedMACSHA256=statusMAC.SHA256;
[candidate,~]=bs.previewAdmission(bitsOf(statusMAC.Bytes),control); bs.commitAdmission(candidate);
assert(bs.estimate(s,64,100,64).BudgetBytes==max(0,expected-8));
assert(bs.estimate(s,65,100,64).BudgetBytes==max(0,expected-8-numel(status.Bytes)));
assert(bs.Debits{end}.SDUBytes==0&&bs.Debits{end}.RLCStatusBytes==numel(status.Bytes));
[candidate,~]=bs.previewAdmission(bitsOf(statusMAC.Bytes),control); bs.commitAdmission(candidate);
assert(numel(bs.Debits)==3);
% A new post-LCP BSR already excludes this same-TB STATUS; do not subtract twice.
fresh=control; fresh.LogicalTBID="status-with-bsr"; fresh.OriginalTransmissionStartSample=70;
combined=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
    [items struct('LCID',4,'Payload',status.Bytes,'OwnerID',"original-status")],24);
fresh.ObservationEndSampleExclusive=75; fresh.AvailableSample=80; fresh.DecodedMACSHA256=combined.SHA256;
[candidate,~]=bs.previewAdmission(bitsOf(combined.Bytes),fresh); bs.commitAdmission(candidate);
assert(bs.estimate(s,80,100,64).BudgetBytes==expected);
ok=true;
end
function bits=bitsOf(bytes)
m=zeros(numel(bytes),8,'int8'); for k=1:8, m(:,k)=int8(bitget(bytes(:),9-k)); end
bits=reshape(m.',[],1);
end
function rejects(f)
failed=false; try, f(); catch, failed=true; end; assert(failed,'Expected original MAC rejection.');
end
