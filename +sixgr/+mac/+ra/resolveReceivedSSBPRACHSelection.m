function out=resolveReceivedSSBPRACHSelection(tree,mib,native,validity,request)
%RESOLVERECEIVEDSSBPRACHSELECTION Decoded-input Type-1 CBRA selection boundary.
% This function is NOT a decoder, delivered-context authenticator, TDD/SSB
% validity evaluator, gNB monitor, or transmission. The caller must supply
% original decoded SIB1/MIB and an explicit native-RO validity evaluation.
% No host configuration, configured occasion, active TX bitmap, or default
% validity mask is used. Runtime callers must additionally authenticate the
% current UE/cell/acquisition generation and the selected-beam power/timing.
%
% validity binds the original native resolution and decoded inputs by SHA;
% CandidateSupport contains one original-period row per native RO with
% SourceOccasionOrdinal, ActiveStartTicks, ActiveEndTicksExclusive (Tc).
% RepeatedValidity is logical [nativeROs x evaluatedNativePeriods]. Its
% evaluation horizon must cover the joint native/TDD/SSB period. A changing
% validity mask is explicitly unsupported by the current association kernel.
% These are supplied decisions, never independently verified PHY evidence.
%
% request uses a radio-clock half-open [EarliestRadioTicks,EndRadioTicks)
% window, separate from KnowledgeSample / delivery availability. The caller
% must reserve the actual TA-shifted TX support before enqueueing waveform.
% CBPreambleOffset0 is an explicit caller policy draw within the received CB
% partition, not a configured absolute preamble or a detector hypothesis.

assert(isa(mib,'sixgr.phy.broadcast.ReceivedMIBContext') && isscalar(mib), ...
    'sixgr:mac:ra:ReceivedAssociationMIBRequired','Use the original immutable received BCH context.');
d=mib.Data;
assert(mib.SHA256==localHash(d) && d.GlobalCaptureEpochBound, ...
    'sixgr:mac:ra:ReceivedAssociationMIBRequired','A complete globally clock-bound original MIB context is required.');
assert(d.ReceiverGeometry.FrequencyRange=="FR1" && ismember(d.ReceiverGeometry.Lmax,[4 8]), ...
    'sixgr:mac:ra:ReceivedAssociationDomainUnsupported', ...
    'This decoded inOneGroup boundary supports FR1 Lmax4/8 only; groupPresence/FR2 is not inferred.');
assert(isstruct(tree) && isscalar(tree),'sixgr:mac:ra:ReceivedAssociationSIB1Required', ...
    'Supply the original decoded SIB1 tree, not host scenario policy.');
try
    serving=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon;
    ul=serving.uplinkConfigCommon.initialUplinkBWP;
    rach=ul.rach_ConfigCommon;
catch cause
    error('sixgr:mac:ra:ReceivedAssociationSIB1Required','Missing original common SIB1 operands: %s',cause.message);
end
[~,treeEvidence]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
treeHash=string(treeEvidence.RxTreeHash);
positions=serving.ssb_PositionsInBurst;
assert(isstruct(positions) && isscalar(positions) && isequal(string(fieldnames(positions)),"inOneGroup"), ...
    'sixgr:mac:ra:ReceivedAssociationDomainUnsupported','Only the original FR1 inOneGroup bitmap is supported.');
bitmap=localText(positions.inOneGroup);
assert(strlength(bitmap)==8 && all(ismember(char(bitmap),'01')), ...
    'sixgr:mac:ra:InvalidReceivedAssociationBitmap','The decoded inOneGroup bit string must retain all eight ordered bits.');
% TS38.331: Lmax4 uses the four LEFTMOST bits; the other four are ignored.
active=find(char(extractBetween(bitmap,1,d.ReceiverGeometry.Lmax))=='1')-1;
assert(~isempty(active),'sixgr:mac:ra:InvalidReceivedAssociationBitmap','No supported SSB is present in the decoded bitmap.');
choices=["oneEighth","oneFourth","oneHalf","one","two","four","eight","sixteen"];
ratios=[1/8 1/4 1/2 1 2 4 8 16]; choice=localText(rach.ssbPerRACHChoice);
assert(any(choice==choices),'sixgr:mac:ra:InvalidReceivedAssociationChoice','Unknown original ssb-perRACH choice.');
ratio=ratios(choice==choices);
cbToken=localText(rach.cbPreamblesPerSSB);
if ratio<=2, pattern='^n([0-9]+)$'; else, pattern='^([0-9]+)$'; end
token=regexp(char(cbToken),pattern,'tokens','once');
assert(~isempty(token),'sixgr:mac:ra:InvalidReceivedAssociationChoice','Retain the canonical CB preamble count token.');
cb=str2double(token{1});
canonical=string(cb); if ratio<=2, canonical="n"+canonical; end
assert(cbToken==canonical,'sixgr:mac:ra:InvalidReceivedAssociationChoice','Noncanonical CB count token.');
% The constrained decoder represents the ASN.1 absent-total default as 64.
% A direct original tree with the optional operand absent has that same
% standard default; a present malformed operand must never use it.
total=64; totalPresent=isfield(rach,'nPreambles');
if totalPresent, total=localInteger(rach.nPreambles,1,64); end
ulSCS=localSCS(ul.genericParameters.subcarrierSpacing);
cp="normal"; if isfield(ul.genericParameters,'cyclicPrefix'), cp=localText(ul.genericParameters.cyclicPrefix); end
assert(any(cp==["normal","extended"]),'sixgr:mac:ra:InvalidReceivedAssociationClock','Invalid decoded UL BWP CP.');
localNativeIdentity(native,rach,ulSCS,d.ReceiverGeometry.FrequencyRange);
baseTicks=int64(native.BasePeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
ssbPeriod=localText(serving.ssb_periodicityServingCell);
ssbTokens=["ms5","ms10","ms20","ms40","ms80","ms160"];
assert(any(ssbPeriod==ssbTokens),'sixgr:mac:ra:InvalidReceivedAssociationClock','Unsupported decoded SSB period.');
ssbTicks=int64([5 10 20 40 80 160]*(double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/1000));
ssbTicks=ssbTicks(ssbTokens==ssbPeriod);
tddPresent=isfield(serving,'tdd_UL_DL_ConfigurationCommon'); tddHash=""; tddTicks=int64(1);
if tddPresent
    tdd=sixgr.rrc.asn1.resolveTDDCommonRuntime(serving.tdd_UL_DL_ConfigurationCommon,ulSCS,cp,"FR1");
    assert(tdd.Present,'sixgr:mac:ra:InvalidReceivedAssociationClock','Present original TDD IE cannot be an absent marker.');
    tddHash=localHash(serving.tdd_UL_DL_ConfigurationCommon);
    tddTicks=int64(tdd.SlotFormatState.ActiveSlotsPerPattern)* ...
        (sixgr.phy.frame.AbsoluteTime.TicksPerFrame/int64(10*ulSCS/15));
end
jointTicks=lcm(lcm(baseTicks,tddTicks),ssbTicks);
localValidity(validity,native,mib.SHA256,treeHash,tddPresent,tddHash,jointTicks,baseTicks);
support=validity.CandidateSupport;
validMask=validity.RepeatedValidity(:,1);

required={'MIBContextSHA256','SIB1TreeSHA256','SelectedSSBIndex0','CBPreambleOffset0', ...
    'KnowledgeSample','SIB1AvailableAtSample','SelectedSSBAvailableAtSample', ...
    'SelectedSSBReferenceSHA256','EarliestRadioTicks','EndRadioTicks'};
assert(isstruct(request) && isscalar(request) && all(isfield(request,required)), ...
    'sixgr:mac:ra:InvalidReceivedAssociationRequest','Supply the complete explicit selection/availability contract.');
assert(localSHA(request.MIBContextSHA256)==mib.SHA256 && localSHA(request.SIB1TreeSHA256)==treeHash, ...
    'sixgr:mac:ra:ReceivedAssociationIdentityMismatch','Selection request must name the original received MIB/SIB1.');
selected=localInteger(request.SelectedSSBIndex0,0,d.ReceiverGeometry.Lmax-1);
offset=localInteger(request.CBPreambleOffset0,0,63);
assert(ismember(selected,active),'sixgr:mac:ra:SelectedSSBNotInReceivedBitmap', ...
    'Selected measured beam is not a valid active index in the received bitmap.');
assert(offset<cb,'sixgr:mac:ra:ReceivedAssociationPreambleOutsidePartition', ...
    'Caller preamble offset must fit this decoded CB partition.');
now=localInteger(request.KnowledgeSample,0,flintmax);
siAvailable=localInteger(request.SIB1AvailableAtSample,0,flintmax);
beamAvailable=localInteger(request.SelectedSSBAvailableAtSample,0,flintmax);
beamHash=localSHA(request.SelectedSSBReferenceSHA256);
assert(d.AvailableAtSample<=now && siAvailable<=now && beamAvailable<=now, ...
    'sixgr:mac:ra:ReceivedAssociationNotYetAvailable','Original MIB, SI and selected-beam reference must be available at the knowledge cutoff.');
first=localTicks(request.EarliestRadioTicks); last=localTicks(request.EndRadioTicks);
assert(last>first,'sixgr:mac:ra:InvalidReceivedAssociationClock','Selection requires a nonempty half-open radio-clock horizon.');
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/d.SampleRateHz;
assert(ticksPerSample==fix(ticksPerSample),'sixgr:mac:ra:InvalidReceivedAssociationClock','Original receive sample clock must map exactly to Tc.');
phaseTicks=(d.ReceivedFrameOriginSample-d.AbsoluteFrameNumber*d.SampleRateHz/100)*ticksPerSample;
radioNow=now*ticksPerSample-phaseTicks;
assert(abs(radioNow)<=flintmax && radioNow==fix(radioNow) && double(first)>=radioNow, ...
    'sixgr:mac:ra:ReceivedAssociationBackdated','Do not choose an RO before the receiver-derived current radio clock.');

out=struct('ContractVersion',"received_ssb_prach_selection/v1", ...
    'Scope',"decoded_input_selection_with_caller_supplied_validity_not_runtime_or_PHY_acceptance", ...
    'ValidityIndependentlyVerified',false,'RuntimeAuthorityVerified',false, ...
    'Available',false,'Status',"no_valid_RO_in_supplied_period", ...
    'MIBContextSHA256',mib.SHA256,'SIB1TreeSHA256',treeHash, ...
    'NativeResolutionSHA256',localHash(native),'ValiditySHA256',localHash(validity), ...
    'RequestSHA256',localHash(request),'TDDCommonPresent',tddPresent,'TDDCommonSHA256',tddHash, ...
    'SelectedSSBReferenceSHA256',beamHash,'SelectedSSBIndex0',selected, ...
    'DecodedTotalPreamblesOperandPresent',totalPresent,'TotalPreambles',double(total), ...
    'TotalPreamblesPresenceScope',"decoded_tree_operand_not_original_ASN1_IE_presence", ...
    'KnowledgeSample',now,'EarliestRadioTicks',first,'EndRadioTicks',last, ...
    'OriginalOccasions',native.Occasions,'OriginalCandidateSupport',support, ...
    'Association',struct(),'SelectedAssociationRow',table(),'SelectedNativeOccasion',table(), ...
    'AssociationCycleIndex0',NaN,'NativePeriodIndex0',NaN,'PRACHOccasionOrdinal',NaN, ...
    'PreambleIndex0',NaN,'ActiveStartTicks',int64.empty(0,1),'ActiveEndTicksExclusive',int64.empty(0,1));
if ~any(validMask), return; end
a=sixgr.mac.ra.resolveSSBPRACHAssociation(native,active,ratio,cb,total,validMask);
out.Association=a; out.Status="no_mapped_RO_in_requested_window";
rows=find(a.Mapping.SSBIndex0==selected); periodTicks=int64(a.AssociationPeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
starts=zeros(numel(rows),1,'int64'); cycles=zeros(numel(rows),1,'int64');
for k=1:numel(rows)
    m=a.Mapping(rows(k),:);
    starts(k)=support.ActiveStartTicks(m.SourceOccasionRow)+int64(m.ConfigurationPeriodIndex0)*baseTicks;
    delta=first-starts(k);
    if delta>0, cycles(k)=idivide(delta-1,periodTicks,'floor')+1; end
    assert(double(cycles(k))*double(periodTicks)+double(starts(k))<=flintmax, ...
        'sixgr:mac:ra:ReceivedAssociationClockOverflow','Translated RO exceeds the supported exact clock range.');
    starts(k)=starts(k)+cycles(k)*periodTicks;
end
% Actual time first; native frequency/time ordering is already preserved by
% the canonical mapping. The tie break is an explicit deterministic policy.
[start,index]=min(starts); if isempty(index) || start>=last, return; end
m=a.Mapping(rows(index),:); cycle=double(cycles(index));
periodIndex=double(m.ConfigurationPeriodIndex0)+cycle*a.AssociationPeriodConfigurationCount;
translation=int64(periodIndex)*baseTicks;
finish=support.ActiveEndTicksExclusive(m.SourceOccasionRow)+translation;
assert(double(finish)<=flintmax,'sixgr:mac:ra:ReceivedAssociationClockOverflow','Translated active end exceeds exact clock range.');
% Do not truncate the actual native CP/useful support at a run boundary.
if finish>last, out.Status="mapped_RO_support_outside_requested_window"; return; end
m.Ordinal=m.Ordinal+cycle*a.AssociationPeriodConfigurationCount*height(native.Occasions);
m.Frame=m.Frame+cycle*a.AssociationPeriodFrames;
m.AbsoluteSlot=m.AbsoluteSlot+cycle*a.AssociationPeriodCarrierSlots;
m.PRACHSlot=m.PRACHSlot+cycle*a.AssociationPeriodConfigurationCount*native.BasePeriodPRACHSlots;
out.Available=true; out.Status="selected_received_SSB_mapped_RO";
out.SelectedAssociationRow=m;
out.SelectedNativeOccasion=native.Occasions(m.SourceOccasionRow,:);
out.AssociationCycleIndex0=cycle; out.NativePeriodIndex0=periodIndex;
out.PRACHOccasionOrdinal=periodIndex*height(native.Occasions)+m.SourceOccasionOrdinal;
out.PreambleIndex0=double(m.CBPreambleStart0)+offset;
out.ActiveStartTicks=start; out.ActiveEndTicksExclusive=finish;
end

function localNativeIdentity(n,r,scs,range)
fields={'ContractVersion','FrequencyRange','ConfigurationIndex','CarrierSubcarrierSpacingKHz', ...
    'PRACHSubcarrierSpacingKHz','RestrictedSet','ZeroCorrelationZone','Msg1FDM','Msg1FrequencyStart', ...
    'BasePeriodFrames','BasePeriodCarrierSlots','BasePeriodPRACHSlots','Occasions', ...
    'ResolvedValid','FallbackUsed','UnknownIndexDefaulted'};
assert(isstruct(n) && isscalar(n) && all(isfield(n,fields)) && ...
    string(n.ContractVersion)=="sixgr_prach_occasion_release18/v1", ...
    'sixgr:mac:ra:ReceivedAssociationNativeRequired','Supply the original canonical native candidate resolution.');
for f=["ResolvedValid","FallbackUsed","UnknownIndexDefaulted"]
    assert(islogical(n.(f)) && isscalar(n.(f)), ...
        'sixgr:mac:ra:ReceivedAssociationNativeRequired','Native flags must remain original logical scalars.');
end
fdmTokens=["one","two","four","eight"]; fdmValues=[1 2 4 8]; fdm=localText(r.msg1FDM);
assert(any(fdm==fdmTokens),'sixgr:mac:ra:ReceivedAssociationNativeMismatch','Malformed received msg1-FDM.');
prachSCS=sixgr.mac.ra.resolveDecodedPRACHSubcarrierSpacing(r);
assert(n.ResolvedValid && ~n.FallbackUsed && ~n.UnknownIndexDefaulted && ...
    string(n.FrequencyRange)==range && n.ConfigurationIndex==localInteger(r.configurationIndex,0,262) && ...
    n.CarrierSubcarrierSpacingKHz==scs && n.PRACHSubcarrierSpacingKHz==prachSCS && ...
    isfield(n,'Format') && string(n.Format)==string(r.preambleFormat) && ...
    string(n.RestrictedSet)==localText(r.restrictedSet) && n.ZeroCorrelationZone==localInteger(r.zeroCorrelationZoneConfig,0,15) && ...
    n.Msg1FDM==fdmValues(fdmTokens==fdm) && n.Msg1FrequencyStart==localInteger(r.msg1FrequencyStart,0,flintmax), ...
    'sixgr:mac:ra:ReceivedAssociationNativeMismatch','Native RACH candidates disagree with decoded common operands.');
end

function localValidity(v,n,mibHash,treeHash,tddPresent,tddHash,joint,base)
names={'ContractVersion','MIBContextSHA256','SIB1TreeSHA256','NativeResolutionSHA256', ...
    'TDDCommonPresent','TDDCommonSHA256','EvaluatedPeriodTicks','CandidateSupport','RepeatedValidity','DecisionReasons'};
assert(isstruct(v) && isscalar(v) && all(isfield(v,names)) && ...
    localText(v.ContractVersion)=="received_prach_candidate_validity_input/v1", ...
    'sixgr:mac:ra:ReceivedAssociationValidityRequired','Require complete explicit original candidate validity evidence.');
assert(localSHA(v.MIBContextSHA256)==mibHash && localSHA(v.SIB1TreeSHA256)==treeHash && ...
    localSHA(v.NativeResolutionSHA256)==localHash(n) && ...
    islogical(v.TDDCommonPresent) && isscalar(v.TDDCommonPresent) && v.TDDCommonPresent==tddPresent && ...
    localText(v.TDDCommonSHA256)==tddHash, ...
    'sixgr:mac:ra:ReceivedAssociationValidityMismatch','Validity must name these original MIB/SIB1/native/TDD inputs.');
period=localTicks(v.EvaluatedPeriodTicks);
assert(period==joint && rem(period,base)==0,'sixgr:mac:ra:ReceivedAssociationValidityPeriod', ...
    'Evaluate the complete joint native/TDD/SSB period, anchored at radio frame zero.');
count=height(n.Occasions); columns=double(period/base);
assert(islogical(v.RepeatedValidity) && isequal(size(v.RepeatedValidity),[count columns]) && ...
    isstring(v.DecisionReasons) && isequal(size(v.DecisionReasons),[count columns]) && ...
    all(~ismissing(v.DecisionReasons) & strlength(v.DecisionReasons)>0,'all'), ...
    'sixgr:mac:ra:ReceivedAssociationValidityRequired','Every original RO/repetition needs an explicit logical decision and reason.');
assert(all(v.RepeatedValidity==v.RepeatedValidity(:,1),'all'), ...
    'sixgr:mac:ra:AssociationPatternNotImplemented','Validity changes across native periods; do not silently collapse a longer pattern.');
s=v.CandidateSupport;
assert(istable(s) && height(s)==count && all(ismember( ...
    ["SourceOccasionOrdinal","ActiveStartTicks","ActiveEndTicksExclusive"],string(s.Properties.VariableNames))) && ...
    isequal(s.SourceOccasionOrdinal,n.Occasions.Ordinal) && isa(s.ActiveStartTicks,'int64') && ...
    isa(s.ActiveEndTicksExclusive,'int64') && iscolumn(s.ActiveStartTicks) && iscolumn(s.ActiveEndTicksExclusive) && ...
    all(s.ActiveStartTicks>=0 & s.ActiveStartTicks<base & s.ActiveEndTicksExclusive>s.ActiveStartTicks) && ...
    all(double(s.ActiveEndTicksExclusive)<=flintmax) && ...
    all(ismember({'PRACHActiveStartTicks','PRACHActiveEndTicksExclusive'},n.Occasions.Properties.VariableNames)) && ...
    isequal(s.ActiveStartTicks,n.Occasions.PRACHActiveStartTicks) && ...
    isequal(s.ActiveEndTicksExclusive,n.Occasions.PRACHActiveEndTicksExclusive), ...
    'sixgr:mac:ra:ReceivedAssociationSupportMismatch', ...
    'Retain one original native CP/useful support per RO; do not use coarse long-PRACH whole-slot geometry.');
end

function v=localInteger(v,lo,hi)
assert(isnumeric(v) && ~islogical(v) && isreal(v) && isscalar(v) && isfinite(v) && ...
    v==fix(v) && v>=lo && v<=hi,'sixgr:mac:ra:InvalidReceivedAssociationOperand','Require an original numeric integer operand.');
v=double(v);
end
function t=localTicks(t)
assert(isa(t,'int64') && isscalar(t) && t>=0 && double(t)<=flintmax, ...
    'sixgr:mac:ra:InvalidReceivedAssociationClock','Radio clocks must be exact nonnegative int64 Tc within the exact arithmetic domain.');
end
function s=localText(s)
assert((isstring(s) && isscalar(s) && ~ismissing(s)) || (ischar(s) && isrow(s)), ...
    'sixgr:mac:ra:InvalidReceivedAssociationOperand','Require an original scalar text operand.');
s=string(s);
end
function s=localSHA(s)
s=localText(s); assert(~isempty(regexp(char(s),'^[0-9a-fA-F]{64}$','once')), ...
    'sixgr:mac:ra:ReceivedAssociationIdentityMismatch','Require a complete original SHA256 identity.');
end
function scs=localSCS(s)
tokens=["kHz15","kHz30","kHz60","kHz120"]; values=[15 30 60 120];
s=localText(s); assert(any(s==tokens),'sixgr:mac:ra:InvalidReceivedAssociationClock','Unsupported received BWP SCS.');
scs=values(s==tokens);
end
function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
