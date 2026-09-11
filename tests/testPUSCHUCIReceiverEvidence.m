function ok=testPUSCHUCIReceiverEvidence()
% Actual NR coding/soft decoding fixtures, not propagation measurements.
setup6GRSimToolkit('Verbose',false);
for modulation=["QPSK","16QAM","64QAM","256QAM"]
    for count=[1 2 7 12 20]
        bits=int8(mod((1:count)',2));
        coded=nrUCIEncode(bits,480,char(modulation));
        coded(coded==-1)=1;
        y=find(coded==-2); coded(y)=coded(y-1);
        waveform=nrSymbolModulate(coded,char(modulation));
        llr=nrSymbolDemodulate(waveform,char(modulation),.01);
        [decoded,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,count,modulation);
        assert(isequal(decoded,bits) && e.DecodeUsable);
        assert(e.CRCApplicable==(count>=12));
        if count<12, assert(isnan(e.CRCPass)); else, assert(e.CRCPass==1); end
    end
end
% A CRC failure still returns binary bits; those cannot become scheduler CSI.
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(901); failed=false;
for attempt=1:16
    [bits,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(randn(192,1),20,'QPSK');
    if e.CRCPass==0, failed=true; break; end
end
assert(failed && ~e.DecodeUsable && numel(bits)==20 && all(ismember(bits,int8([0 1]))));
[empty,absent]=sixgr.phy.ul.pusch.decodeUCIWithEvidence([],0,'QPSK');
out=struct('UCIReceiverEvidence',struct('CSI1',e,'CSI2AndConfiguredGrantUCI',absent));
[usable,crc]=sixgr.truth.puschCSIReceiverUsable(out,bits,empty,[20 0]);
assert(~usable && crc==0);
e.DecodeUsable=true; out.UCIReceiverEvidence.CSI1=e;
[usable,crc]=sixgr.truth.puschCSIReceiverUsable(out,bits,empty,[20 0]);
assert(~usable && crc==0,'A stale usability flag cannot override actual CRC failure.');
fprintf('PUSCH_UCI_RECEIVER_EVIDENCE_PASS: modulation-specific UCI, actual CRC and failed-CRC rejection.\n');
ok=true;
end
