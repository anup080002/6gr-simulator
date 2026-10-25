function ok=testReceivedSSBPRACHSelection()
% One original native BCH acquisition, genuine SIB1 UPER round trips and
% native PRACH candidate/support geometry. Validity and delivery cutoffs are
% DECLARED boundary inputs here, not received SI, measured selection, a
% TDD-validity implementation, Msg1 waveform/RX, or live RA qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=configuration();
tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'Content','SSB_MIB');
fs=tx.SampleRateHz; first=tx.BroadcastStartSample;
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(tx.Waveform,1),fs,size(tx.Waveform,2));
observation.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,first),fs);
[rx,mib]=sixgr.phy.broadcast.recoverSIB1FromWaveform(observation,cfg,'RecoveryScope','SSB_MIB');
assert(rx.SSBMIBComplete && rx.MIBDecoded && isa(mib,'sixgr.phy.broadcast.ReceivedMIBContext'));
originalGeometry=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
assert(mib.Data.ReceiverGeometry.SSBCase==string(originalGeometry.Case) && ...
    mib.Data.ReceiverGeometry.SSBCyclicPrefix=="normal" && ...
    isequal(mib.Data.ReceiverGeometry.SSBCandidateStartSymbolsWithinHalfFrame, ...
        double(originalGeometry.CandidateStartSymbolsWithinHalfFrame(:).')));
mib.validate(cfg);
native=resolveNative(167,30,2);
[tree,bits]=decodedTree(cfg,native,"11110000","two","n8",true);
validity=declaredValidity(tree,mib,native);
request=selectionRequest(tree,mib,1);
f=@sixgr.mac.ra.resolveReceivedSSBPRACHSelection;
beforeRNG=rng; beforeCalls=sixgr.runtime.RuntimeCallLedger.snapshot();
out=f(tree,mib,native,validity,request);
assert(out.Available && out.SelectedSSBIndex0==1 && out.PreambleIndex0==35 && ...
    out.SelectedAssociationRow.CBPreambleStart0==32 && out.SelectedAssociationRow.CBPreambleCount==8 && ...
    ~out.RuntimeAuthorityVerified && ~out.ValidityIndependentlyVerified);
assert(out.ActiveStartTicks>=request.EarliestRadioTicks && out.ActiveEndTicksExclusive<=request.EndRadioTicks);
assert(isequaln(out.OriginalOccasions,native.Occasions) && ...
    isequaln(out.SelectedNativeOccasion,native.Occasions(out.SelectedAssociationRow.SourceOccasionRow,:)));
assert(~ismember('PRACHActiveEndTicksExclusive',out.SelectedAssociationRow.Properties.VariableNames));
assertTranslation(out,native,validity);
assert(isequal(rng,beforeRNG) && isequaln(sixgr.runtime.RuntimeCallLedger.snapshot(),beforeCalls), ...
    'Selection must not rerun a waveform, receiver or native candidate resolver or draw a preamble.');

% Exact inclusive-start/exclusive-end policy. A completed original native
% support is not truncated to manufacture an in-horizon transmission.
edge=request; edge.EarliestRadioTicks=out.ActiveStartTicks;
same=f(tree,mib,native,validity,edge); assert(same.PRACHOccasionOrdinal==out.PRACHOccasionOrdinal);
edge.EndRadioTicks=out.ActiveEndTicksExclusive-1;
short=f(tree,mib,native,validity,edge); assert(~short.Available && ...
    short.Status=="mapped_RO_support_outside_requested_window" && isempty(short.SelectedNativeOccasion));
edge=request; edge.EarliestRadioTicks=out.ActiveStartTicks+1;
next=f(tree,mib,native,validity,edge); assert(next.Available && next.ActiveStartTicks>out.ActiveStartTicks);

% Frame 1024 remains an unwrapped radio epoch. Never reset association at
% a new SIB1 delivery or rewrite the original native period's tick columns.
wrap=request; wrap.EarliestRadioTicks=int64(1024)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
wrap.EndRadioTicks=wrap.EarliestRadioTicks+int64(32)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
wrapped=f(tree,mib,native,validity,wrap);
assert(wrapped.Available && wrapped.SelectedAssociationRow.Frame>=1024);
assertTranslation(wrapped,native,validity);
assert(isequaln(native.Occasions,wrapped.OriginalOccasions));

% Changing the original wire bitmap/partition changes selection, even if
% a host scenario would still hold its old bitmap or preamble index.
[sparse,sparseBits]=decodedTree(cfg,native,"10100001","two","n8",true);
assert(~isequal(bits,sparseBits));
v=declaredValidity(sparse,mib,native); q=selectionRequest(sparse,mib,2);
changed=f(sparse,mib,native,v,q); assert(changed.Available && changed.PreambleIndex0==35);
reject(@()f(sparse,mib,native,validity,q),'ReceivedAssociationValidityMismatch');
q.SelectedSSBIndex0=1; reject(@()f(sparse,mib,native,v,q),'SelectedSSBNotInReceivedBitmap');

% DECLARED decoder-shaped N>=4 INTEGER choice boundary. The current bridge
% encoder for that choice is not qualified by this test; do not relabel the
% following metadata transformation as another actual UPER reception.
integerChoice=tree;
integerRACH=integerChoice.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
integerRACH.ssbPerRACHChoice="four"; integerRACH.cbPreamblesPerSSB="4";
integerChoice.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=integerRACH;
v=declaredValidity(integerChoice,mib,native); q=selectionRequest(integerChoice,mib,2);
integerResult=f(integerChoice,mib,native,v,q);
assert(integerResult.Available && integerResult.PreambleIndex0==35 && ...
    integerResult.SelectedAssociationRow.CBPreambleStart0==32);

% Optional TDD absence is retained, not rescued by a host frame map. These
% explicit all-true decisions remain DECLARED fixture inputs, not a claim
% that absent TDD permits all ROs. An absent decision is always rejected.
[absent,~]=decodedTree(cfg,native,"11110000","two","n8",false);
v=declaredValidity(absent,mib,native); q=selectionRequest(absent,mib,1);
a=f(absent,mib,native,v,q); assert(~a.TDDCommonPresent && a.TDDCommonSHA256=="");
reject(@()f(absent,mib,native,rmfield(v,'RepeatedValidity'),q),'ReceivedAssociationValidityRequired');

% Long 839-sequence geometry uses actual native CP/useful samples, NOT the
% older resolver's conservative full-PRACH-slot carrier-symbol reservation.
long=resolveNative(0,1.25,1);
[longTree,~]=decodedTree(cfg,long,"10000000","one","n64",false);
v=declaredValidity(longTree,mib,long); q=selectionRequest(longTree,mib,0);
q.CBPreambleOffset0=11;
longSelection=f(longTree,mib,long,v,q);
assert(long.SequenceLength==839 && longSelection.Available && longSelection.PreambleIndex0==11);
assertTranslation(longSelection,long,v);
for k=1:height(long.Occasions)
    r=long.Occasions(k,:);
    clock=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(r.AbsoluteSlot,r.StartSymbol,1);
    coarseEnd=clock.plusSymbols(r.DurationSymbols,1);
    assert(v.CandidateSupport.ActiveEndTicksExclusive(k)<=coarseEnd.Ticks);
end
assert(any(v.CandidateSupport.ActiveEndTicksExclusive-v.CandidateSupport.ActiveStartTicks < ...
    int64(long.SubframesPerPRACHSlot)*sixgr.phy.frame.AbsoluteTime.TicksPerSecond/int64(1000)), ...
    'The long native active support must not be replaced by the whole PRACH-slot duration.');

% Explicit malformed/changed evidence must fail before any physical work.
v=validity; v.NativeResolutionSHA256=repmat("0",1,64); v.NativeResolutionSHA256=join(v.NativeResolutionSHA256,"");
reject(@()f(tree,mib,native,v,request),'ReceivedAssociationValidityMismatch');
v=validity; v.CandidateSupport.ActiveEndTicksExclusive(1)=v.CandidateSupport.ActiveEndTicksExclusive(1)+1;
reject(@()f(tree,mib,native,v,request),'ReceivedAssociationSupportMismatch');
v=validity; v.CandidateSupport.ActiveStartTicks(1)=v.CandidateSupport.ActiveStartTicks(1)+1;
reject(@()f(tree,mib,native,v,request),'ReceivedAssociationSupportMismatch');
v=validity; v.RepeatedValidity=double(v.RepeatedValidity);
reject(@()f(tree,mib,native,v,request),'ReceivedAssociationValidityRequired');
v=validity; v.DecisionReasons(1)="";
reject(@()f(tree,mib,native,v,request),'ReceivedAssociationValidityRequired');
v=validity; v.EvaluatedPeriodTicks=v.EvaluatedPeriodTicks*2;
reject(@()f(tree,mib,native,v,request),'ReceivedAssociationValidityPeriod');
if size(validity.RepeatedValidity,2)>1
    v=validity; v.RepeatedValidity(1,2)=~v.RepeatedValidity(1,1);
    reject(@()f(tree,mib,native,v,request),'AssociationPatternNotImplemented');
end
v=validity; v.RepeatedValidity(:)=false;
empty=f(tree,mib,native,v,request); assert(~empty.Available && isempty(empty.SelectedNativeOccasion));
for name=["SIB1AvailableAtSample","SelectedSSBAvailableAtSample"]
    q=request; q.(name)=q.KnowledgeSample+1;
    reject(@()f(tree,mib,native,validity,q),'ReceivedAssociationNotYetAvailable');
end
q=request; q.EarliestRadioTicks=int64(0);
reject(@()f(tree,mib,native,validity,q),'ReceivedAssociationBackdated');
q=request; q.CBPreambleOffset0=8;
reject(@()f(tree,mib,native,validity,q),'ReceivedAssociationPreambleOutsidePartition');
q=request; q.SelectedSSBIndex0=true;
reject(@()f(tree,mib,native,validity,q),'InvalidReceivedAssociationOperand');
bad=native; bad.Msg1FDM=1;
reject(@()f(tree,mib,bad,validity,request),'ReceivedAssociationNativeMismatch');
reject(@()f(tree,mib.Data,native,validity,request),'ReceivedAssociationMIBRequired');
parent=fullfile(pwd,'results','validation','received_ssb_prach_selection');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
save(fullfile(folder,'original_operands_and_selections.mat'),'cfg','rx','mib','tree','bits','native', ...
    'validity','request','out','wrapped','long','longSelection','-v7.3');
fprintf('RECEIVED_SSB_PRACH_SELECTION_PASS native_BCH=1 actual_UPER=1 native_geometry=short_and_long validity=declared_boundary runtime_or_Msg1=0 folder=%s\n',folder);
ok=true;
end

function assertTranslation(s,n,v)
r=s.SelectedAssociationRow; original=n.Occasions(r.SourceOccasionRow,:);
delta=int64(s.NativePeriodIndex0*n.BasePeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
assert(s.ActiveStartTicks==v.CandidateSupport.ActiveStartTicks(r.SourceOccasionRow)+delta && ...
    s.ActiveEndTicksExclusive==original.PRACHActiveEndTicksExclusive+delta && ...
    r.AbsoluteSlot==original.AbsoluteSlot+s.NativePeriodIndex0*n.BasePeriodCarrierSlots && ...
    r.PRACHSlot==original.PRACHSlot+s.NativePeriodIndex0*n.BasePeriodPRACHSlots && ...
    r.TimeIndex==original.TimeIndex && r.FrequencyIndex==original.FrequencyIndex && ...
    r.ActivePRACHSlot==original.ActivePRACHSlot && ...
    s.PRACHOccasionOrdinal==s.NativePeriodIndex0*height(n.Occasions)+original.Ordinal);
end

function cfg=configuration()
cfg=sixgr.config.defaultConfig(); cfg.run.strictMode=true;
cfg.phy.sib1.enable=true; cfg.phy.carrier.NCellID=17;
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.carrier.NSizeGrid=51; cfg.phy.channelBandwidth_MHz=20;
cfg.frequency.bandwidth_hz=20e6; cfg.channel.bandwidth_Hz=20e6;
cfg.phy.ssb.NCRBSSB=30; cfg.phy.ssb.KSSB=0;
cfg.phy.ssb.periodicity_ms=20; cfg.phy.ssb.period_ms=20;
cfg.phy.ssb.activeBitmap=logical([1 0 0 0 0 0 0 0]);
cfg.phy.ssb.runtimeSSBIndex=0; cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
cfg.initial_access.type0=struct('monitoring_occasion_ordinal',1);
cfg.phy.sib1.coreset0Index=0; cfg.phy.sib1.searchSpaceZero=4;
cfg.phy.mib.pdcchConfigSIB1=4; cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.sync.fineCFOEnabled=true;
end

function n=resolveNative(index,scs,fdm)
n=sixgr.phy.frame.PRACHOccasionResolver.resolve('FrequencyRange',"FR1", ...
    'DuplexMode',"TDD",'ConfigurationIndex',index,'CarrierSubcarrierSpacingKHz',30, ...
    'CarrierCyclicPrefix',"normal",'NSizeGrid',51,'NStartGrid',0,'NCellID',17, ...
    'PRACHSubcarrierSpacingKHz',scs,'SequenceIndex',0,'PreambleIndex',0, ...
    'RestrictedSet',"UnrestrictedSet",'ZeroCorrelationZone',0,'Msg1FDM',fdm,'Msg1FrequencyStart',0);
end

function [tree,bits]=decodedTree(cfg,n,bitmap,choice,cb,tdd)
cfg.initial_access.ssb.positions_in_burst=bitmap;
cfg.initial_access.ssb.periodicity_ms=20;
cfg.phy.prach.configurationIndex=n.ConfigurationIndex;
cfg.phy.prach.rootSeqIndex=0; cfg.phy.prach.zeroCorrelationZone=0;
cfg.phy.prach.restrictedSet="UnrestrictedSet";
cfg.phy.prach.subcarrierSpacing_kHz=n.PRACHSubcarrierSpacingKHz;
cfg.phy.prach.preambleFormat=n.Format; cfg.phy.prach.nPreambles=64;
cfg.random_access.msg1_fdm=n.Msg1FDM; cfg.random_access.frequency_start=0;
cfg.rrc.sib1.ssb_per_rach_choice=choice; cfg.rrc.sib1.cb_preambles_per_ssb=cb;
cfg.phy.duplex=struct('mode','TDD');
if tdd
    cfg.rrc.sib1.tdd_ul_dl_config_common=struct('referenceSubcarrierSpacing',"kHz30", ...
        'pattern1',struct('dl_UL_TransmissionPeriodicity',"ms2p5", ...
        'nrofDownlinkSlots',3,'nrofDownlinkSymbols',10,'nrofUplinkSlots',1,'nrofUplinkSymbols',2));
else
    cfg.rrc.sib1.tdd_ul_dl_config_common=[];
end
original=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
bits=sixgr.rrc.asn1.encodeSIB1UPER(original);
tree=sixgr.rrc.asn1.decodeSIB1UPER(bits);
assert(sixgr.rrc.asn1.compareSIB1Trees(original,tree));
end

function v=declaredValidity(tree,mib,n)
% DECLARED repeating validity only. Exact support is independently queried
% from native PRACH OFDM metadata for every original candidate, both LRA.
serving=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon;
[~,h]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
base=int64(n.BasePeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
joint=lcm(base,int64(2)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame);
present=isfield(serving,'tdd_UL_DL_ConfigurationCommon'); digest="";
if present, digest=hash(serving.tdd_UL_DL_ConfigurationCommon); end
c=nrCarrierConfig('NSizeGrid',51,'NStartGrid',0,'NCellID',17,'SubcarrierSpacing',30);
p=nrPRACHConfig('FrequencyRange','FR1','DuplexMode','TDD','ConfigurationIndex',n.ConfigurationIndex, ...
    'SubcarrierSpacing',n.PRACHSubcarrierSpacingKHz,'SequenceIndex',0,'PreambleIndex',0, ...
    'RestrictedSet','UnrestrictedSet','ZeroCorrelationZone',0,'FrequencyStart',0);
starts=zeros(height(n.Occasions),1,'int64'); stops=starts;
for k=1:height(n.Occasions)
    r=n.Occasions(k,:); p.NPRACHSlot=r.PRACHSlot; p.ActivePRACHSlot=r.ActivePRACHSlot;
    p.TimeIndex=r.TimeIndex; p.FrequencyIndex=r.FrequencyIndex;
    c.NFrame=r.Frame; c.NSlot=r.SlotWithinFrame;
    t=sixgr.rach.prachSampleTiming(c,p);
    starts(k)=t.ActiveStartTicks; stops(k)=t.ActiveEndTicksExclusive;
    assert(starts(k)==r.PRACHActiveStartTicks && stops(k)==r.PRACHActiveEndTicksExclusive);
end
support=table(n.Occasions.Ordinal,starts,stops, ...
    'VariableNames',{'SourceOccasionOrdinal','ActiveStartTicks','ActiveEndTicksExclusive'});
shape=[height(n.Occasions),double(joint/base)];
v=struct('ContractVersion',"received_prach_candidate_validity_input/v1", ...
    'MIBContextSHA256',mib.SHA256,'SIB1TreeSHA256',string(h.RxTreeHash), ...
    'NativeResolutionSHA256',hash(n),'TDDCommonPresent',present,'TDDCommonSHA256',digest, ...
    'EvaluatedPeriodTicks',joint,'CandidateSupport',support, ...
    'RepeatedValidity',true(shape),'DecisionReasons',repmat("DECLARED_fixture_not_TDD_or_SSB_validity_evaluation",shape));
end

function q=selectionRequest(tree,mib,beam)
[~,h]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
% Delivery and beam selection are explicit boundary values, NOT a claim
% that this test physically received SI or measured the nonzero beam.
q=struct('MIBContextSHA256',mib.SHA256,'SIB1TreeSHA256',string(h.RxTreeHash), ...
    'SelectedSSBIndex0',double(beam),'CBPreambleOffset0',3, ...
    'KnowledgeSample',mib.Data.AvailableAtSample,'SIB1AvailableAtSample',mib.Data.AvailableAtSample, ...
    'SelectedSSBAvailableAtSample',mib.Data.AvailableAtSample, ...
    'SelectedSSBReferenceSHA256',hash(struct('DeclaredBeamBoundaryOnly',beam)), ...
    'EarliestRadioTicks',int64(2)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame, ...
    'EndRadioTicks',int64(64)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame);
end
function digest=hash(value)
digest=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
function reject(fn,suffix)
try, fn(); catch cause
    assert(string(cause.identifier)=="sixgr:mac:ra:"+suffix,'Expected %s, got %s: %s',suffix,cause.identifier,cause.message); return;
end
error('test:MissingReceivedAssociationRejection','Expected %s.',suffix);
end
