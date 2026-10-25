function ok=testTDDCommonRuntimeAuthority()
% Declared original IE -> actual exact symbol-map consumer; no UPER/RX claim.
resolve=@(ie,scs,cp,range)sixgr.rrc.asn1.resolveTDDCommonRuntime(ie,scs,cp,range);
for absent={[],struct()}
    a=resolve(absent{1},30,"normal","FR1");
    assert(~a.Present && isequaln(a.OriginalIE,absent{1}) && ...
        isempty(a.SlotFormatState) && isempty(fieldnames(a.EffectiveConfig)));
end
ie=localIE("kHz15",localPattern("ms5",2,3,1,2));
before=ie;
r=resolve(ie,15,"normal","FR1");
assert(r.Present && isequaln(r.OriginalIE,before) && isequaln(ie,before));
expected=repmat('F',1,70); expected(1:31)='D'; expected(55:70)='U';
assert(isequal(r.SlotFormatState.CommonDirection,reshape(expected,14,5).'));
assert(all(r.SlotFormatState.ResolvedDirection(r.SlotFormatState.CommonDirection=='F')=="UNRESOLVED_FLEX"));
mixed=resolve(ie,30,"normal","FR1");
assert(mixed.SlotFormatState.ActiveSlotsPerPattern==10 && ...
    mixed.SlotFormatState.ReferenceSubcarrierSpacingKHz==15);
assert(isequal(mixed.SlotFormatState.directionsForFrame(0),mixed.SlotFormatState.directionsForFrame(10000)));
% Every base IE period is retained, on an explicitly legal reference clock.
periods=["ms0p5","ms0p625","ms1","ms1p25","ms2","ms2p5","ms5","ms10"];
durations=[0.5 0.625 1 1.25 2 2.5 5 10];
for k=1:numel(periods)
    base=localIE("kHz120",localPattern(periods(k),0,0,0,0));
    b=resolve(base,120,"normal","FR2-1");
    assert(b.EffectiveConfig.Pattern1.PeriodicityMilliseconds==durations(k) && ...
        isequaln(b.OriginalIE,base));
end
extended=localIE("kHz60",localPattern("ms1",1,2,1,2));
ex=resolve(extended,60,"extended","FR1");
assert(ex.SlotFormatState.SymbolsPerSlot==12);
badExtended=extended; badExtended.pattern1.nrofDownlinkSymbols=12;
reject(@()resolve(badExtended,60,"extended","FR1"),'InvalidTDDPatternCount');
% Original base enum survives even when v1530 supplies the effective period.
ext=localIE("kHz15",localPattern("ms10",3,0,0,0));
ext.pattern1.dl_UL_TransmissionPeriodicity_v1530="ms3";
ext.pattern2=localPattern("ms2",0,0,2,0);
e=resolve(ext,15,"normal","FR1");
assert(isequaln(e.OriginalIE,ext) && e.OriginalIE.pattern1.dl_UL_TransmissionPeriodicity=="ms10");
assert(e.EffectiveConfig.Pattern1.PeriodicityMilliseconds==3 && ...
    e.SlotFormatState.PatternDurationMilliseconds==5 && ...
    isequal(e.SlotFormatState.CommonDirection,[repmat('D',3,14);repmat('U',2,14)]));
four=localIE("kHz30",localPattern("ms0p5",4,0,4,0));
four.pattern1.dl_UL_TransmissionPeriodicity_v1530="ms4";
f=resolve(four,30,"normal","FR1");
assert(f.EffectiveConfig.Pattern1.PeriodicityMilliseconds==4 && isequaln(f.OriginalIE,four));
% Pattern1+2 is radio-even-frame aligned, never delivery-relative.
twenty=localIE("kHz15",localPattern("ms10",10,0,0,0));
twenty.pattern2=localPattern("ms10",0,0,10,0);
t=resolve(twenty,15,"normal","FR1");
assert(all(t.SlotFormatState.directionsForFrame(0)=='D','all') && ...
    all(t.SlotFormatState.directionsForFrame(1)=='U','all') && ...
    all(t.SlotFormatState.directionsForFrame(2)=='D','all'));
% Applicable reference SCS by actual frequency range, not generic FR2.
for pair={ {"kHz60",60,"FR2-1"}, {"kHz120",120,"FR2-1"}, ...
        {"kHz120",120,"FR2-2"}, {"kHz480",480,"FR2-2"}, {"kHz960",960,"FR2-2"} }
    c=pair{1}; positive=localIE(c{1},localPattern("ms1",0,0,0,0));
    x=resolve(positive,c{2},"normal",c{3}); assert(x.Present);
end
bad=ie; bad.pattern1.nrofDownlinkSymbols=14; reject(@()resolve(bad,15,"normal","FR1"),'InvalidTDDPatternCount');
for value={'A',true,NaN,Inf,-1,0.5,321,[1 2]}
    bad=ie; bad.pattern1.nrofDownlinkSlots=value{1};
    reject(@()resolve(bad,15,"normal","FR1"),'InvalidTDDPatternCount');
end
bad=ie; bad.pattern1.dl_UL_TransmissionPeriodicity=5;
reject(@()resolve(bad,15,"normal","FR1"),'InvalidTDDEnum');
bad=ext; bad.pattern1.dl_UL_TransmissionPeriodicity_v1530="ms5";
reject(@()resolve(bad,15,"normal","FR1"),'InvalidTDDEnum');
bad=ie; bad.pattern2=struct(); reject(@()resolve(bad,15,"normal","FR1"),'InvalidTDDCommonIE');
bad=ie; bad.pattern1.extra=1; reject(@()resolve(bad,15,"normal","FR1"),'UnsupportedTDDCommonField');
bad=rmfield(ie,'pattern1'); reject(@()resolve(bad,15,"normal","FR1"),'InvalidTDDCommonIE');
bad=ie; bad.referenceSubcarrierSpacing="kHz120";
reject(@()resolve(bad,120,"normal","FR1"),'TDDReferenceSCSFrequencyRange');
reject(@()resolve(ie,'A',"normal","FR1"),'InvalidTDDActiveSCS');
reject(@()resolve(ie,15,"normal","FR2"),'InvalidTDDEnum');
bad=ie; bad.referenceSubcarrierSpacing="kHz30";
rejectExact(@()resolve(bad,15,"normal","FR1"),'sixgr:phy:frame:ReferenceSCSExceedsActiveBWPSCS');
bad=ie; bad.pattern1=localPattern("ms0p625",0,0,0,0);
rejectExact(@()resolve(bad,15,"normal","FR1"),'sixgr:phy:frame:TDDPeriodNotIntegralSlots');
bad=ie; bad.pattern1=localPattern("ms1",1,1,0,0);
rejectExact(@()resolve(bad,15,"normal","FR1"),'sixgr:phy:frame:TDDPatternOverbooked');
bad=ext; bad=rmfield(bad,'pattern2');
rejectExact(@()resolve(bad,15,"normal","FR1"),'sixgr:phy:frame:TDDPeriodDoesNotDivide20ms');
fprintf('PASS testTDDCommonRuntimeAuthority: original IE preservation, exact maps, extension/absence and malformed guards; no codec/RX qualification.\n');
ok=true;
end
function ie=localIE(scs,p)
ie=struct('referenceSubcarrierSpacing',scs,'pattern1',p);
end
function p=localPattern(period,d,ds,u,us)
p=struct('dl_UL_TransmissionPeriodicity',period,'nrofDownlinkSlots',d, ...
    'nrofDownlinkSymbols',ds,'nrofUplinkSlots',u,'nrofUplinkSymbols',us);
end
function reject(fn,suffix)
rejectExact(fn,"sixgr:rrc:asn1:"+suffix);
end
function rejectExact(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==string(id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('testTDDCommonRuntimeAuthority:MissingRejection','Expected %s.',id);
end
