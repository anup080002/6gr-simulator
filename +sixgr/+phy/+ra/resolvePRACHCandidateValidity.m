function out=resolvePRACHCandidateValidity(native,common,ssb)
%RESOLVEPRACHCANDIDATEVALIDITY Exact-clock Type-1 PRACH validity evaluation.
% NR reference: TS38.213 V18.8.0 section8.1 and Table8.1-2; physical start
% lattice: TS38.211 V18.8.0 sections5.3.1/5.3.2. Ngap is counted BACK from
% the exact PRACH start on that ordinary normal-CP OFDM lattice (mu0 for
% long1.25/5kHz, otherwise PRACH SCS). This cross-clause clock interpretation
% permits mixed numerologies without rounding DL/SSB end times.
%
% native: ORIGINAL unfiltered PRACHOccasionResolver resolution, including
% exact int64 PRACHActiveStartTicks/PRACHActiveEndTicksExclusive. No native
% generator, waveform, decoder, random draw or TX/RX acceptance runs here.
% common: scalar struct with Source, CarrierCyclicPrefix, TDDCommonIE,
% Procedure='type1_single_preamble', ChannelAccessMode='not_provided'.
% Source is configured_cell_common, decoded_common_configuration, or the
% explicitly nonphysical declared_clock_fixture. An absent IE remains [].
% ssb: scalar struct with matching Source, PeriodTicks (int64),
% SubcarrierSpacingKHz and Intervals table(SSBIndex0,StartTicks,EndTicksExclusive).
% Intervals are the COMPLETE original configured/decoded bitmap population,
% relative to radio frame0 modulo PeriodTicks, including original phase.
% Each interval must retain exactly four normal-CP SSB symbols. The caller
% owns band/Case/bitmap association and received-context authentication.
%
% All intervals are half-open Tc intervals. The periodic pattern extends
% before frame0 for lookbehind and beyond the evaluated horizon for same-
% slot lookahead. The whole joint period is returned, even if validity is
% not constant across native periods. No received-authority or PHY claim is
% made by hashes: they identify these supplied operands only.

localFields(common,["Source","CarrierCyclicPrefix","TDDCommonIE", ...
    "Procedure","ChannelAccessMode"],"common");
source=localToken(common.Source,["configured_cell_common", ...
    "decoded_common_configuration","declared_clock_fixture"],"Source");
cp=localToken(common.CarrierCyclicPrefix,["normal","extended"],"CarrierCyclicPrefix");
localToken(common.Procedure,"type1_single_preamble","Procedure");
localToken(common.ChannelAccessMode,"not_provided","ChannelAccessMode");
[base,carrierSpec,prachSpec]=localNative(native,cp);
tdd=sixgr.rrc.asn1.resolveTDDCommonRuntime(common.TDDCommonIE, ...
    native.CarrierSubcarrierSpacingKHz,cp,native.FrequencyRange);
tddHash=""; tddPeriod=int64(1); direction=char.empty(0,0);
if tdd.Present
    assert(string(native.DuplexMode)=="TDD", ...
        'sixgr:phy:ra:PRACHValidityContradictoryDuplex', ...
        'A common TDD IE cannot silently override paired/SUL native candidates.');
    tddHash=localHash(common.TDDCommonIE);
    direction=tdd.SlotFormatState.CommonDirection;
    tddPeriod=int64(tdd.SlotFormatState.ActiveSlotsPerPattern)*carrierSpec.TicksPerSlot;
end
[ssbStarts,ssbEnds,ssbPeriod]=localSSB(ssb,source);
joint=localLCM(localLCM(base,tddPeriod),ssbPeriod);
assert(joint>0 && double(joint)<=flintmax && rem(joint,base)==0, ...
    'sixgr:phy:ra:PRACHValidityClockOverflow','The complete joint period must be exactly representable.');
T=native.Occasions; count=height(T); repeats=double(joint/base);
assert(count*repeats<=1e6,'sixgr:phy:ra:PRACHValidityDomainUnsupported', ...
    'The explicit joint-period evaluation exceeds the bounded one-million decision domain.');
support=table(T.Ordinal,T.PRACHActiveStartTicks,T.PRACHActiveEndTicksExclusive, ...
    'VariableNames',{'SourceOccasionOrdinal','ActiveStartTicks','ActiveEndTicksExclusive'});
valid=false(count,repeats); reasons=strings(count,repeats);
rows=repmat(localRow(),count*repeats,1);
paired=any(string(native.DuplexMode)==["FDD","SUL"]);
for p=0:repeats-1
    translation=int64(p)*base;
    for r=1:count
        row=localRow(); row.SourceOccasionRow=r; row.SourceOccasionOrdinal=T.Ordinal(r);
        row.NativePeriodIndex0=p; row.Format=string(T.Format(r));
        first=T.PRACHActiveStartTicks(r)+translation;
        last=T.PRACHActiveEndTicksExclusive(r)+translation;
        row.ActiveStartTicks=first; row.ActiveEndTicksExclusive=last;
        symbol=localSymbolAt(first,prachSpec);
        assert(localBoundary(symbol,prachSpec)==first, ...
            'sixgr:phy:ra:PRACHValidityStartNotOnReferenceClock', ...
            'Original RO ordinal %g start must match the TS38.211 PRACH reference OFDM clock exactly.',T.Ordinal(r));
        slot=idivide(symbol,int64(prachSpec.SymbolsPerSlot),'floor');
        slotFirst=localBoundary(slot*int64(prachSpec.SymbolsPerSlot),prachSpec);
        slotLast=localBoundary((slot+1)*int64(prachSpec.SymbolsPerSlot),prachSpec);
        row.PRACHReferenceSlotStartTicks=slotFirst; row.PRACHReferenceSlotEndTicksExclusive=slotLast;
        gap=localGap(row.Format,native.PRACHSubcarrierSpacingKHz,native.SequenceLength);
        cutoff=localBoundary(symbol-int64(gap),prachSpec);
        row.NgapSymbols=gap; row.GapCutoffTicks=cutoff;
        if paired
            row.Valid=true; row.Reason="paired_or_supplementary_uplink";
        else
            % Include complete previous-period SSB support, a future block
            % in the containing PRACH slot, and any block intersecting a
            % long preamble beyond that first reference slot.
            [starts,ends]=localPeriodicIntervals(ssbStarts,ssbEnds,ssbPeriod, ...
                min(cutoff,slotFirst)-ssbPeriod,max(last,slotLast));
            row.SSBOverlap=any(starts<last & ends>first);
            sameSlot=starts<slotLast & ends>slotFirst;
            row.DoesNotPrecedeSSBInPRACHSlot=~any(ends(sameSlot)>first);
            previous=ends(ends<=first);
            if ~isempty(previous)
                row.LastSSBAvailable=true; row.LastSSBEndTicks=max(previous);
                row.SSBGapSatisfied=row.LastSSBEndTicks<=cutoff;
            else
                % Empty original population is explicit; no synthetic last
                % SSB time is invented. TDD unpaired callers are rejected
                % below if the original population itself was empty.
                row.SSBGapSatisfied=true;
            end
            if tdd.Present
                [row.WithinCommonUL,row.CommonDLOverlap,hasDL,lastDL]= ...
                    localTDD(first,last,carrierSpec,direction);
                row.LastDLAvailable=hasDL; row.LastDLEndTicks=lastDL;
                row.DLGapSatisfied=~hasDL || lastDL<=cutoff;
            else
                row.DLGapSatisfied=true;
            end
            if row.SSBOverlap
                row.Reason="SSB_active_support_overlap";
            elseif row.CommonDLOverlap
                row.Reason="common_DL_active_support_overlap";
            elseif row.WithinCommonUL
                row.Valid=true; row.Reason="within_common_UL_symbols";
            elseif ~row.DoesNotPrecedeSSBInPRACHSlot
                row.Reason="precedes_SSB_in_PRACH_reference_slot";
            elseif ~row.SSBGapSatisfied
                row.Reason="insufficient_gap_after_SSB";
            elseif ~row.DLGapSatisfied
                row.Reason="insufficient_gap_after_common_DL";
            else
                row.Valid=true;
                if tdd.Present, row.Reason="common_TDD_order_and_gaps_satisfied";
                else, row.Reason="absent_common_TDD_SSB_order_and_gap_satisfied"; end
            end
        end
        valid(r,p+1)=row.Valid; reasons(r,p+1)=row.Reason;
        rows(p*count+r)=row;
    end
end
out=struct('ContractVersion',"prach_candidate_validity/v1", ...
    'Scope',"exact_configured_or_decoded_clock_evaluation_not_PHY_or_runtime_authentication", ...
    'Source',source,'Standard',"TS38.213_V18.8.0_8.1_and_TS38.211_V18.8.0_5.3.1_5.3.2", ...
    'RuntimeAuthorityVerified',false,'NativeInputIndependentlyAuthenticated',false, ...
    'PHYExecutionPerformed',false,'ClockOrigin',"absolute_radio_frame_zero", ...
    'GapClockInterpretation',"ordinary_PRACH_start_reference_OFDM_lattice_backward_Ngap_CP_bearing_symbols", ...
    'NativeResolutionSHA256',localHash(native),'CommonConfigurationSHA256',localHash(common), ...
    'SSBClockSHA256',localHash(ssb),'TDDCommonPresent',tdd.Present,'TDDCommonSHA256',tddHash, ...
    'BasePeriodTicks',base,'EvaluatedPeriodTicks',joint,'CandidateSupport',support, ...
    'RepeatedValidity',valid,'DecisionReasons',reasons,'Decisions',struct2table(rows), ...
    'OriginalCommonConfiguration',common,'OriginalSSBClock',ssb,'OriginalOccasions',T);
out.ReceiptSHA256=localHash(out);
end

function [base,carrier,prach]=localNative(n,cp)
required=["ContractVersion","FrequencyRange","DuplexMode","CarrierSubcarrierSpacingKHz", ...
    "PRACHSubcarrierSpacingKHz","SequenceLength","BasePeriodFrames","BasePeriodCarrierSlots", ...
    "PeriodFrames","DirectionPeriodSlots","Occasions","ResolvedValid","FallbackUsed","UnknownIndexDefaulted"];
assert(isstruct(n) && isscalar(n) && all(isfield(n,required)) && ...
    localText(n.ContractVersion)=="sixgr_prach_occasion_release18/v1", ...
    'sixgr:phy:ra:PRACHValidityNativeRequired','Supply original canonical native RO geometry.');
for f=["ResolvedValid","FallbackUsed","UnknownIndexDefaulted"]
    assert(islogical(n.(f)) && isscalar(n.(f)), ...
        'sixgr:phy:ra:PRACHValidityNativeRequired','Native authority flags must be scalar logical.');
end
assert(n.ResolvedValid && ~n.FallbackUsed && ~n.UnknownIndexDefaulted, ...
    'sixgr:phy:ra:PRACHValidityNativeRequired','Unresolved or fallback geometry cannot authorize validity.');
localToken(n.FrequencyRange,["FR1","FR2-1","FR2-2"],"FrequencyRange");
localToken(n.DuplexMode,["TDD","FDD","SUL"],"DuplexMode");
assert(string(n.FrequencyRange)=="FR1" || string(n.DuplexMode)=="TDD", ...
    'sixgr:phy:ra:PRACHValidityContradictoryDuplex','FR2 native PRACH must be unpaired.');
scs=localNumber(n.CarrierSubcarrierSpacingKHz,[15 30 60 120 240 480 960]);
psc=localNumber(n.PRACHSubcarrierSpacingKHz,[1.25 5 15 30 60 120 480 960]);
seq=localNumber(n.SequenceLength,[139 571 839 1151]);
assert((seq==839)==ismember(psc,[1.25 5]), ...
    'sixgr:phy:ra:PRACHValidityNativeRequired','Long/short sequence and native SCS disagree.');
carrier=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',scs,'CyclicPrefix',cp));
ref=psc; if seq==839, ref=15; end
prach=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',ref,'CyclicPrefix',"normal"));
maxFrames=floor(flintmax/double(sixgr.phy.frame.AbsoluteTime.TicksPerFrame));
frames=localInteger(n.BasePeriodFrames,1,maxFrames); base=int64(frames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
assert(localInteger(n.PeriodFrames,1,maxFrames)==frames && ...
    localInteger(n.DirectionPeriodSlots,1,flintmax)==1 && ...
    localInteger(n.BasePeriodCarrierSlots,1,flintmax)==frames*carrier.SlotsPerFrame, ...
    'sixgr:phy:ra:PRACHValidityPrefilteredNativeUnsupported', ...
    'Require one unfiltered native period; host direction-map filtering is not received common authority.');
T=n.Occasions;
assert(istable(T) && height(T)>0 && all(ismember(["Ordinal","Format", ...
    "PRACHActiveStartTicks","PRACHActiveEndTicksExclusive"],string(T.Properties.VariableNames))), ...
    'sixgr:phy:ra:PRACHValidityNativeRequired','Original native table needs exact CP/useful support.');
assert(isnumeric(T.Ordinal) && ~islogical(T.Ordinal) && isequal(double(T.Ordinal),(1:height(T)).') && ...
    isstring(T.Format) && iscolumn(T.Format) && all(~ismissing(T.Format)), ...
    'sixgr:phy:ra:PRACHValidityNativeRequired','Preserve original contiguous native ordinals and format tokens.');
for f=["PRACHActiveStartTicks","PRACHActiveEndTicksExclusive"]
    localTickVector(T.(f));
end
assert(all(T.PRACHActiveStartTicks>=0 & T.PRACHActiveStartTicks<base & ...
    T.PRACHActiveEndTicksExclusive>T.PRACHActiveStartTicks & ...
    T.PRACHActiveEndTicksExclusive<=base+sixgr.phy.frame.AbsoluteTime.TicksPerFrame), ...
    'sixgr:phy:ra:PRACHValidityInvalidSupport','Require complete original CP/useful support, not guard-zero padding or a truncated period.');
end

function [starts,ends,period]=localSSB(s,source)
localFields(s,["Source","PeriodTicks","SubcarrierSpacingKHz","Intervals"],"ssb");
assert(localText(s.Source)==source,'sixgr:phy:ra:PRACHValiditySourceMismatch', ...
    'Do not silently mix configured and decoded authority labels.');
period=localTicks(s.PeriodTicks);
ms=sixgr.phy.frame.AbsoluteTime.TicksPerSecond/int64(1000);
assert(any(period==int64([5 10 20 40 80 160])*ms), ...
    'sixgr:phy:ra:PRACHValidityInvalidSSBClock','SSB period must retain its exact supported clock.');
scs=localNumber(s.SubcarrierSpacingKHz,[15 30 120 240 480 960]);
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',scs,'CyclicPrefix',"normal"));
T=s.Intervals;
assert(istable(T) && height(T)>0 && isequal(string(T.Properties.VariableNames), ...
    ["SSBIndex0","StartTicks","EndTicksExclusive"]), ...
    'sixgr:phy:ra:PRACHValidityInvalidSSBClock','Supply the complete nonempty original SSB population, not the selected beam only.');
assert(isnumeric(T.SSBIndex0) && ~islogical(T.SSBIndex0) && iscolumn(T.SSBIndex0) && ...
    all(isfinite(T.SSBIndex0) & T.SSBIndex0==fix(T.SSBIndex0) & T.SSBIndex0>=0 & T.SSBIndex0<=63) && ...
    numel(unique(T.SSBIndex0))==height(T), ...
    'sixgr:phy:ra:PRACHValidityInvalidSSBClock','Each original periodic SSB index must occur exactly once.');
starts=T.StartTicks; ends=T.EndTicksExclusive; localTickVector(starts); localTickVector(ends);
assert(all(starts>=0 & starts<period & ends>starts & ends<=period), ...
    'sixgr:phy:ra:PRACHValidityInvalidSSBClock','SSB support must fit the original radio-zero periodic interval.');
for k=1:height(T)
    symbol=localSymbolAt(starts(k),spec);
    assert(localBoundary(symbol,spec)==starts(k) && localBoundary(symbol+4,spec)==ends(k), ...
        'sixgr:phy:ra:PRACHValidityInvalidSSBClock','Each original SSB must retain four complete normal-CP symbols at its own SCS.');
end
[a,i]=sort(starts); b=ends(i);
assert(all(a(2:end)>=b(1:end-1)), ...
    'sixgr:phy:ra:PRACHValidityInvalidSSBClock','Original periodic SSB supports must not overlap.');
end

function gap=localGap(format,scs,seq)
if seq==839
    assert(any(format==["0","1","2","3"]),'sixgr:phy:ra:PRACHValidityNativeRequired','Invalid long format.');
    gap=0;
else
    assert(any(format==["A1","A2","A3","B1","B2","B3","B4","C0","C2"]), ...
        'sixgr:phy:ra:PRACHValidityNativeRequired','Invalid short format.');
    if format=="B4", gap=0;
    elseif ismember(scs,[15 30 60 120]), gap=2;
    elseif scs==480, gap=8;
    elseif scs==960, gap=16;
    else, error('sixgr:phy:ra:PRACHValidityDomainUnsupported','No supported Ngap for the original preamble.'); end
end
end

function [withinUL,overlapDL,hasDL,lastDL]=localTDD(first,last,spec,map)
firstSymbol=localSymbolAt(first,spec); lastSymbol=localSymbolAt(last-1,spec);
ids=firstSymbol:lastSymbol; periodSymbols=int64(numel(map));
flat=reshape(map.',1,[]); directions=flat(double(mod(ids,periodSymbols))+1);
withinUL=all(directions=='U'); overlapDL=any(directions=='D');
% Look back one complete common period; its last DL end is sufficient.
prior=(firstSymbol-periodSymbols):firstSymbol;
ends=localBoundary(prior+1,spec);
eligible=ends<=first & flat(double(mod(prior,periodSymbols))+1)=='D';
hasDL=any(eligible); lastDL=int64(0);
if hasDL, lastDL=max(ends(eligible)); end
end

function [starts,ends]=localPeriodicIntervals(a,b,period,first,last)
% End of the previous period is deliberately kept; future blocks in the
% containing PRACH slot must be visible even after the query horizon.
lo=idivide(first-max(b),period,'floor'); hi=idivide(last-min(a),period,'floor');
offsets=(lo:hi)*period;
starts=reshape(a+offsets,[],1); ends=reshape(b+offsets,[],1);
keep=starts<last & ends>=first; starts=starts(keep); ends=ends(keep);
end

function symbol=localSymbolAt(t,spec)
frame=sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
f=idivide(t,frame,'floor'); within=mod(t,frame);
index=find(spec.SymbolStartTicks<=within,1,'last')-1;
symbol=f*int64(numel(spec.SymbolStartTicks))+int64(index);
end
function ticks=localBoundary(symbol,spec)
count=int64(numel(spec.SymbolStartTicks)); frames=idivide(symbol,count,'floor');
index=double(mod(symbol,count))+1;
ticks=frames*sixgr.phy.frame.AbsoluteTime.TicksPerFrame+reshape(spec.SymbolStartTicks(index),size(symbol));
end
function r=localRow()
r=struct('SourceOccasionRow',NaN,'SourceOccasionOrdinal',NaN,'NativePeriodIndex0',NaN, ...
    'Format',"",'ActiveStartTicks',int64(0),'ActiveEndTicksExclusive',int64(0), ...
    'PRACHReferenceSlotStartTicks',int64(0),'PRACHReferenceSlotEndTicksExclusive',int64(0), ...
    'NgapSymbols',NaN,'GapCutoffTicks',int64(0),'WithinCommonUL',false, ...
    'CommonDLOverlap',false,'SSBOverlap',false,'DoesNotPrecedeSSBInPRACHSlot',false, ...
    'LastDLAvailable',false,'LastDLEndTicks',int64(0),'DLGapSatisfied',false, ...
    'LastSSBAvailable',false,'LastSSBEndTicks',int64(0),'SSBGapSatisfied',false, ...
    'Valid',false,'Reason',"");
end
function localFields(s,fields,label)
assert(isstruct(s) && isscalar(s) && isequal(sort(string(fieldnames(s))),sort(fields(:))), ...
    'sixgr:phy:ra:PRACHValidityInvalidContract','%s must contain exactly the documented original operands.',label);
end
function v=localInteger(v,lo,hi)
assert(isnumeric(v) && ~islogical(v) && isreal(v) && isscalar(v) && isfinite(v) && ...
    v==fix(v) && v>=lo && v<=hi,'sixgr:phy:ra:PRACHValidityInvalidOperand','Require an original finite integer.');
v=double(v);
end
function v=localNumber(v,allowed)
assert(isnumeric(v) && ~islogical(v) && isreal(v) && isscalar(v) && isfinite(v) && ismember(v,allowed), ...
    'sixgr:phy:ra:PRACHValidityInvalidOperand','Unsupported or malformed original numeric operand.');
v=double(v);
end
function s=localText(s)
assert((isstring(s) && isscalar(s) && ~ismissing(s)) || (ischar(s) && isrow(s)), ...
    'sixgr:phy:ra:PRACHValidityInvalidOperand','Require original scalar text.');
s=string(s);
end
function s=localToken(s,allowed,label)
s=localText(s); assert(any(s==allowed),'sixgr:phy:ra:PRACHValidityDomainUnsupported', ...
    'Unsupported %s; do not silently invent a validity policy.',label);
end
function t=localTicks(t)
assert(isa(t,'int64') && isscalar(t) && t>=0 && double(t)<=flintmax, ...
    'sixgr:phy:ra:PRACHValidityInvalidClock','Require original nonnegative scalar int64 Tc.');
end
function localTickVector(v)
assert(isa(v,'int64') && iscolumn(v) && all(abs(double(v))<=flintmax), ...
    'sixgr:phy:ra:PRACHValidityInvalidClock','Require original exact int64 Tc column vectors.');
end
function h=localHash(v)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(v))));
end
function value=localLCM(a,b)
q=idivide(a,gcd(a,b),'floor');
assert(double(q)<=floor(flintmax/double(b)), ...
    'sixgr:phy:ra:PRACHValidityClockOverflow','Joint-period arithmetic would exceed exact Tc range.');
value=q*b;
end
