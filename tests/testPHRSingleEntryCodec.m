function ok=testPHRSingleEntryCodec()
% Codec only; no received waveform or applicable-PCMAX qualification.
% TS 38.321 V18.8.0 Fig6.1.3.8-1; TS38.133 V18.8.0
% Tables10.1.17.1-1 and10.1.18.1-1. MPE/DPC not configured.
map=@sixgr.l2.mac.PHRMappingR18.phIndex;
enc=@sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR;
dec=@sixgr.l2.mac.BSR_PHR.decodeSingleEntryPHR;
assert(isequal(enc(0,23,false),uint8([33;53])));
assert(isequal(enc(0,23,true),uint8([161;53])));
assert(isequal(enc(22,33,true),uint8([183;63])));
assert(isequal(enc(-100,-100,false),uint8([0;0])));
assert(isequal(enc(100,100,true),uint8([191;63])));
assert(map(21.999)==54 && map(22)==55 && map(23.999)==55 && map(24)==56);
% Independent tabular edges, including every saturation and wide PH bin.
phEdges=[-32:22 24:2:38]; pcEdges=-29:33;
for i=1:63
    assert(map(phEdges(i))==i && map(phEdges(i)-1e-7)==i-1);
    assert(sixgr.l2.mac.PHRMappingR18.pcmaxIndex(pcEdges(i))==i);
    assert(sixgr.l2.mac.PHRMappingR18.pcmaxIndex(pcEdges(i)-1e-7)==i-1);
end
for i=0:63
    for p=[false true]
        [ph,pc,flag,r]=dec(uint8([i+128*double(p);i]));
        assert(flag==p && r.PHIndex==i && r.PCMAXIndex==i);
        if i==0
            assert(isequal(r.PHRange_dB,[-Inf -32]) && isequal(r.PCMAXRange_dBm,[-Inf -29]));
            assert(isnan(ph) && isnan(pc));
        elseif i==63
            assert(isequal(r.PHRange_dB,[38 Inf]) && isequal(r.PCMAXRange_dBm,[33 Inf]));
            assert(isnan(ph) && isnan(pc));
        else
            assert(isequal(r.PHRange_dB,phEdges(i:i+1)));
            assert(isequal(r.PCMAXRange_dBm,pcEdges(i:i+1)));
            assert(isequal(enc(ph,pc,p),uint8([i+128*double(p);i])));
        end
    end
end
for bad={NaN,Inf,-Inf,1+1i,[1 2],[]}
    rejects(@()enc(bad{1},23,false)); rejects(@()enc(0,bad{1},false));
end
for bad={NaN,Inf,-1,2,[],[false true]}
    rejects(@()enc(0,23,bad{1}));
end
for bad={[],1,[1 2 3],[-1 2],[256 2],[1.5 2],[NaN 2],[1+1i 2],[64 0],[0 64],[0 128]}
    rejects(@()dec(bad{1}));
end
for bad={NaN,Inf,-1,64,1.5,[1 2]}
    rejects(@()sixgr.l2.mac.PHRMappingR18.phRange(bad{1}));
    rejects(@()sixgr.l2.mac.PHRMappingR18.pcmaxRange(bad{1}));
end
% Public CE construction and state-machine indices share one authority.
owner=sixgr.l2.mac.BSR_PHR(); ce=owner.makePHR(0,23,'PowerBackoff',true);
assert(ce.LCID==57 && ce.IsFixed && isequal(ce.Payload,uint8([161;53])));
rejects(@()owner.makePHR(NaN,23));
assert(owner.LastPH_dB==0 && owner.LastPCMAX_dBm==23);
machine=sixgr.l2.mac.PHRStateMachine(1); machine.trigger('activation',1);
r=machine.buildReport(struct('PH_dB',0,'PCMAX_dBm',23),1,2);
assert(r.PHIndex==33 && r.PCMAXIndex==53);
machine.trigger('periodic',3);
rejects(@()machine.buildReport(struct('PH_dB',NaN,'PCMAX_dBm',23),3,2));
assert(machine.PendingTrigger=="periodic");
ok=true;
end

function rejects(f)
didThrow=false;
try, f(); catch, didThrow=true; end
assert(didThrow,'testPHRSingleEntryCodec:ExpectedRejection','Malformed PHR was accepted.');
end
