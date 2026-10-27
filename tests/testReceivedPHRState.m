function ok=testReceivedPHRState()
% Authored decoder boundary; not an actual PUSCH test.
s=struct('RunID',"run",'ExecutionID',"execution",'ConfigHash',"cfg", ...
    'UEID',1,'CellID',1,'RNTI',4660,'ConfigurationEpoch',1,'SampleRateHz',30720000);
rx=struct('Scope',s,'CRCPass',true,'Direction',"UL",'LogicalTBID',"tb1", ...
    'TransmissionID',"tx1",'ObservationEndSampleExclusive',100,'AvailableSample',110, ...
    'OriginalTransmissionStartSample',90,'ReferenceGrantContextID',"original-grant");
item=struct('LCID',57,'Payload',sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(0,23,false),'OwnerID',"ue1");
pdu=sixgr.l2.mac.MACPDUAssembler.assemble('UL',item,12);
bits=bitsOf(pdu.Bytes); st=sixgr.l2.mac.ReceivedPHRState(s);
bad=rx; bad.CRCPass=false; assert(st.admit(bits,bad)=="decoder_crc_failed_no_state_update");
assert(isempty(st.Reports)); assert(~st.eligible(s,110,10).Usable);
assert(st.admit(bits,rx)=="received_original_crc_confirmed_single_entry_phr");
assert(st.admit(bits,rx)=="duplicate_success_no_state_update" && numel(st.Reports)==1);
assert(~st.eligible(s,109,20).Usable); result=st.eligible(s,110,20);
assert(result.Usable && isequal(result.Report.PHRange_dB,[0 1]));
assert(isequal(result.Report.PCMAXRange_dBm,[23 24]));
assert(~st.eligible(s,111,20).Usable);
for field=["UEID","CellID","RNTI","ConfigurationEpoch","SampleRateHz"]
    wrong=s; wrong.(field)=wrong.(field)+1;
    assert(~st.eligible(wrong,110,20).Usable);
    bad=rx; bad.Scope=wrong; rejects(@()st.admit(bits,bad));
end
badBits=bits; badBits(10)=1-badBits(10); rejects(@()st.admit(badBits,rx));
bad=rx; bad.AvailableSample=99; rejects(@()st.admit(bits,bad));
bad=rx; bad.LogicalTBID="tb2"; malformed=bits; malformed(1)=1;
rejects(@()st.admit(malformed,bad)); assert(numel(st.Reports)==1);
badBits=double(bits); badBits(1)=NaN; rejects(@()st.admit(badBits,bad));
% Delayed HARQ decode cannot freshen an old headroom observation.
late=sixgr.l2.mac.ReceivedPHRState(s); delayed=rx;
delayed.ObservationEndSampleExclusive=200; delayed.AvailableSample=210;
late.admit(bits,delayed); assert(~late.eligible(s,210,100).Usable);
% MATLAB save/load preserves actual object identity, dedup and usable range.
path=[tempname '.mat']; cleanup=onCleanup(@()delete(path)); save(path,'st');
loaded=load(path,'st'); assert(loaded.st.admit(bits,rx)=="duplicate_success_no_state_update");
assert(isequaln(loaded.st.eligible(s,110,20),result));
ok=true;
end
function bits=bitsOf(bytes)
matrix=zeros(numel(bytes),8,'int8');
for k=1:8, matrix(:,k)=int8(bitget(uint8(bytes(:)),9-k)); end
bits=reshape(matrix.',[],1);
end
function rejects(f)
thrown=false; try, f(); catch, thrown=true; end
assert(thrown,'Expected strict received-PHR rejection.');
end
