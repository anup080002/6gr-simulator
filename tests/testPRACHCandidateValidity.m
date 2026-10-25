function ok=testPRACHCandidateValidity(mode)
% Exact interval/IE evaluation only, NOT RF, detected PRACH or installed UE.
% clock_only uses explicitly declared native-schema clock fixtures. Default
% all additionally obtains real native short/long geometry from 5G Toolbox.
% No boolean validity inputs, received-state fabrication, or host TDD map.
if nargin==0, mode="all"; end
assert(isstring(mode) && isscalar(mode) && any(mode==["all","clock_only"]));
f=@sixgr.phy.ra.resolvePRACHCandidateValidity;
ms=int64(1966080); frame=int64(19660800);
c=common([]); s=ssb(30,20*ms,2);
n=native(30,"A1",tick(30,8),tick(30,10)); before={n,c,s}; rngBefore=rng;

% Absent TDD does NOT imply all UL: actual SSB end + two ordinary symbols.
x=f(n,c,s); assert(x.RepeatedValidity(1,1));
d=x.Decisions(1,:);
assert(d.GapCutoffTicks==tick(30,6) && d.LastSSBEndTicks==tick(30,6) && ...
    d.SSBGapSatisfied && ~x.TDDCommonPresent && ~d.WithinCommonUL);
n7=n; n7.Occasions.PRACHActiveStartTicks=tick(30,7);
y=f(n7,c,s); assert(~y.RepeatedValidity(1,1) && y.Decisions.Reason(1)=="insufficient_gap_after_SSB");
for delta=int64([-1 1])
    q=n; q.Occasions.PRACHActiveStartTicks=tick(30,8)+delta;
    reject(@()f(q,c,s),'PRACHValidityStartNotOnReferenceClock');
    q=s; q.Intervals.EndTicksExclusive(1)=tick(30,6)+delta;
    reject(@()f(n,c,q),'PRACHValidityInvalidSSBClock');
end
assert(isequaln(before,{n,c,s}) && isequal(rngBefore,rng));
assert(~x.RuntimeAuthorityVerified && ~x.PHYExecutionPerformed && ...
    x.Source=="declared_clock_fixture" && isequal(x.OriginalOccasions,n.Occasions));

% Future SSB in the same PRACH slot vetoes a disjoint early RO. Moving that
% SSB into the NEXT PRACH slot removes ordering veto (not carrier-slot math).
early=native(30,"A1",tick(30,2),tick(30,4)); later=ssb(30,20*ms,8);
a=f(early,c,later); assert(~a.RepeatedValidity(1,1) && ~a.Decisions.SSBOverlap(1) && ...
    a.Decisions.Reason(1)=="precedes_SSB_in_PRACH_reference_slot");
next=ssb(30,20*ms,16); a=f(early,c,next); assert(a.RepeatedValidity(1,1));
assert(a.Decisions.PRACHReferenceSlotStartTicks(1)==0 && ...
    a.Decisions.PRACHReferenceSlotEndTicksExclusive(1)==ms/2);

% Full common UL is a separate branch; flexible symbols stay flexible but
% may meet the explicit non-DL ordering/gap rule. Same rows, changed IE.
ul=common(ie(30,"ms1",0,0,2,0));
u=f(early,ul,later); assert(u.RepeatedValidity(1,1) && u.Decisions.WithinCommonUL(1));
flex=common(ie(30,"ms1",0,0,0,0));
v=f(early,flex,later); assert(~v.RepeatedValidity(1,1));
dl=common(ie(30,"ms1",2,0,0,0));
v=f(n,dl,s); assert(~v.RepeatedValidity(1,1) && v.Decisions.CommonDLOverlap(1));

% Common-DL boundary is compared in time, not copied carrier/SSB indices.
% 15-kHz common reference with 30-kHz PRACH: first three DL symbols map
% physically through the production common-TDD resolver.
mixed=common(ie(15,"ms1",0,3,0,0));
q=native(30,"A1",tick(30,8),tick(30,10));
oldSSB=ssb(30,20*ms,28); z=f(q,mixed,oldSSB);
assert(z.RepeatedValidity(1,1) && z.Decisions.LastDLEndTicks(1)==tick(15,3) && ...
    z.Decisions.GapCutoffTicks(1)==tick(30,6));
q.Occasions.PRACHActiveStartTicks=tick(30,7); z=f(q,mixed,oldSSB);
assert(~z.RepeatedValidity(1,1) && z.Decisions.Reason(1)=="insufficient_gap_after_common_DL");

% 15-kHz PRACH with 30-kHz SSB uses the PRACH guard clock. SSB end at30k
% symbol8 equals15k symbol4; equality at15k symbol6 passes, one symbol early
% fails. No rounding of a mixed-numerology endpoint is permitted.
m15=native(15,"A1",tick(15,6),tick(15,7)); ss30=ssb(30,20*ms,4);
z=f(m15,c,ss30); assert(z.RepeatedValidity(1,1) && ...
    z.Decisions.GapCutoffTicks(1)==tick(15,4));
m15.Occasions.PRACHActiveStartTicks=tick(15,5); z=f(m15,c,ss30);
assert(~z.RepeatedValidity(1,1) && z.Decisions.Reason(1)=="insufficient_gap_after_SSB");

% CP-bearing half-subframe edge: the exact two-symbol duration is not two
% mean symbols. The SSB in the next slot does not affect this start-slot.
q=native(30,"A1",tick(30,15),tick(30,16)); edge=ssb(30,20*ms,20);
z=f(q,c,edge);
assert(z.Decisions.GapCutoffTicks(1)==tick(30,13) && ...
    tick(30,15)-tick(30,13)==int64(2*70144+1024));

% B4 and long-preamble Ngap0. Long support crosses beyond its containing
% 1-ms reference slot: later DL/SSB overlap still rejects the entire RO.
b4=native(30,"B4",tick(30,6),tick(30,8)); z=f(b4,c,s);
assert(z.RepeatedValidity(1,1) && z.Decisions.NgapSymbols(1)==0);
long=native(1.25,"1",tick(15,7),int64(5)*ms/2);
long.CarrierSubcarrierSpacingKHz=30; long.BasePeriodCarrierSlots=20;
outside=ssb(30,20*ms,56); z=f(long,c,outside);
assert(~z.RepeatedValidity(1,1) && z.Decisions.SSBOverlap(1) && ...
    z.Decisions.PRACHReferenceSlotEndTicksExclusive(1)==ms && ...
    z.Decisions.DoesNotPrecedeSSBInPRACHSlot(1));
lateDL=ie(30,"ms1",0,0,0,0); lateDL.pattern2=pattern("ms1",2,0,0,0);
away=ssb(30,20*ms,100); z=f(long,common(lateDL),away);
assert(~z.RepeatedValidity(1,1) && z.Decisions.CommonDLOverlap(1));
long.Occasions.PRACHActiveEndTicksExclusive=ms; z=f(long,c,away);
assert(z.RepeatedValidity(1,1) && z.Decisions.NgapSymbols(1)==0);

% Previous-period tail is visible at radio frame0. The full20-ms joint
% period is evaluated; changing TDD/SSB validity is NOT collapsed to one mask.
tail=ssb(30,20*ms,556); zero=native(30,"A1",tick(30,0),tick(30,2));
z=f(zero,c,tail); assert(~z.RepeatedValidity(1,1) && ...
    z.Decisions.LastSSBAvailable(1) && z.Decisions.LastSSBEndTicks(1)==0 && ...
    z.Decisions.GapCutoffTicks(1)<0);
two=ie(30,"ms10",20,0,0,0); two.pattern2=pattern("ms10",0,0,20,0);
q=native(30,"A1",tick(30,260),tick(30,262));
z=f(q,common(two),s); assert(isequal(z.RepeatedValidity,logical([0 1])) && ...
    z.EvaluatedPeriodTicks==2*frame && z.Decisions.NativePeriodIndex0(2)==1 && ...
    z.Decisions.ActiveStartTicks(2)==q.Occasions.PRACHActiveStartTicks+frame);

% Paired/SUL all-native-candidate branch is explicit, not absent-TDD magic.
for duplex=["FDD","SUL"]
    q=early; q.DuplexMode=duplex; z=f(q,c,later);
    assert(all(z.RepeatedValidity,'all') && all(z.Decisions.Reason=="paired_or_supplementary_uplink"));
    reject(@()f(q,ul,later),'PRACHValidityContradictoryDuplex');
end

% Strict original types/epochs/scope; no supplied mask or host-map override.
bad=c; bad.Validity=true; reject(@()f(n,bad,s),'PRACHValidityInvalidContract');
bad=c; bad.ChannelAccessMode="semiStatic"; reject(@()f(n,bad,s),'PRACHValidityDomainUnsupported');
bad=c; bad.Procedure="msgA"; reject(@()f(n,bad,s),'PRACHValidityDomainUnsupported');
bad=s; bad.Source="configured_cell_common"; reject(@()f(n,c,bad),'PRACHValiditySourceMismatch');
bad=s; bad.PeriodTicks=double(bad.PeriodTicks); reject(@()f(n,c,bad),'PRACHValidityInvalidClock');
bad=n; bad.ResolvedValid=1; reject(@()f(bad,c,s),'PRACHValidityNativeRequired');
bad=n; bad.DirectionPeriodSlots=2; reject(@()f(bad,c,s),'PRACHValidityPrefilteredNativeUnsupported');
bad=n; bad.Occasions.PRACHActiveStartTicks=double(bad.Occasions.PRACHActiveStartTicks);
reject(@()f(bad,c,s),'PRACHValidityInvalidClock');
bad=n; bad.Occasions.PRACHActiveEndTicksExclusive=bad.Occasions.PRACHActiveStartTicks;
reject(@()f(bad,c,s),'PRACHValidityInvalidSupport');

nativeCount=0;
if mode=="all"
    % Real native candidate metadata only, never a generated PRACH waveform.
    % Format1's nominal3-ms container also exercises a base period >16frames
    % where applicable; none of that container's guard zeros is occupancy.
    prachCatalog=nrPRACHConfig('FrequencyRange','FR1','DuplexMode','TDD');
    catalog=prachCatalog.Tables.ConfigurationsFR1Unpaired;
    longIndex=double(catalog.ConfigurationIndex(find(string(catalog.PreambleFormat)=="1",1)));
    for spec={[167 30],[0 1.25],[longIndex 1.25]}
        args=spec{1}; actual=sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
            'FrequencyRange',"FR1",'DuplexMode',"TDD",'ConfigurationIndex',args(1), ...
            'CarrierSubcarrierSpacingKHz',30,'CarrierCyclicPrefix',"normal", ...
            'NSizeGrid',51,'NStartGrid',0,'NCellID',17,'PRACHSubcarrierSpacingKHz',args(2), ...
            'SequenceIndex',0,'PreambleIndex',0,'RestrictedSet',"UnrestrictedSet", ...
            'ZeroCorrelationZone',0,'Msg1FDM',2,'Msg1FrequencyStart',0);
        original=actual; output=f(actual,flex,s);
        assert(isequaln(actual,original) && isequal(output.OriginalOccasions,actual.Occasions));
        assert(isequal(output.CandidateSupport.ActiveStartTicks,actual.Occasions.PRACHActiveStartTicks) && ...
            isequal(output.CandidateSupport.ActiveEndTicksExclusive,actual.Occasions.PRACHActiveEndTicksExclusive));
        for k=1:height(actual.Occasions)
            ref=30; if actual.SequenceLength==839, ref=15; end
            start=actual.Occasions.PRACHActiveStartTicks(k);
            assert(output.Decisions.PRACHReferenceSlotStartTicks(k)== ...
                idivide(start,int64(1966080*15/ref),'floor')*int64(1966080*15/ref));
        end
        nativeCount=nativeCount+height(actual.Occasions);
    end
end
fprintf('PRACH_CANDIDATE_VALIDITY_PASS mode=%s native_metadata_rows=%d PHY_execution=0 runtime_installation=0\n',mode,nativeCount);
ok=true;
end

function n=native(scs,format,first,last)
% Declared native-schema fixture, explicitly NOT native generation evidence.
carrierSCS=scs; seq=139;
if ismember(scs,[1.25 5]), carrierSCS=15; seq=839; end
T=table(1,string(format),first,last,'VariableNames', ...
    {'Ordinal','Format','PRACHActiveStartTicks','PRACHActiveEndTicksExclusive'});
n=struct('ContractVersion',"sixgr_prach_occasion_release18/v1", ...
    'TestInputClassification',"declared_native_schema_clock_fixture", ...
    'FrequencyRange',"FR1",'DuplexMode',"TDD",'CarrierSubcarrierSpacingKHz',carrierSCS, ...
    'PRACHSubcarrierSpacingKHz',scs,'SequenceLength',seq,'BasePeriodFrames',1, ...
    'BasePeriodCarrierSlots',10*carrierSCS/15,'PeriodFrames',1,'DirectionPeriodSlots',1, ...
    'Occasions',T,'ResolvedValid',true,'FallbackUsed',false,'UnknownIndexDefaulted',false);
end
function c=common(raw)
c=struct('Source',"declared_clock_fixture",'CarrierCyclicPrefix',"normal", ...
    'TDDCommonIE',raw,'Procedure',"type1_single_preamble",'ChannelAccessMode',"not_provided");
end
function s=ssb(scs,period,firstSymbol)
a=tick(scs,firstSymbol); b=tick(scs,firstSymbol+4);
s=struct('Source',"declared_clock_fixture",'PeriodTicks',period, ...
    'SubcarrierSpacingKHz',scs,'Intervals',table(0,a,b, ...
    'VariableNames',{'SSBIndex0','StartTicks','EndTicksExclusive'}));
end
function v=tick(scs,symbol)
% Independent closed-form ordinary normal-CP clock: base140288/2^mu Tc
% per symbol plus1024Tc at each half-subframe boundary. No production helper.
halfSymbols=7*scs/15; half=floor(double(symbol)/halfSymbols);
remainder=mod(double(symbol),halfSymbols);
v=int64(half*983040+remainder*(140288*15/scs)+1024*(remainder>0));
end
function s=ie(scs,period,d,ds,u,us)
s=struct('referenceSubcarrierSpacing',"kHz"+string(scs), ...
    'pattern1',pattern(period,d,ds,u,us));
end
function s=pattern(period,d,ds,u,us)
s=struct('dl_UL_TransmissionPeriodicity',period,'nrofDownlinkSlots',d, ...
    'nrofDownlinkSymbols',ds,'nrofUplinkSlots',u,'nrofUplinkSymbols',us);
end
function reject(fn,suffix)
try
    fn();
catch cause
    assert(endsWith(string(cause.identifier),suffix), ...
        'Unexpected %s while expecting %s: %s',cause.identifier,suffix,cause.message);
    return;
end
error('test:MissingExpectedFailure','Expected %s.',suffix);
end
