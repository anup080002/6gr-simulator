function ok=testReceivedPRACHValidity()
% Actual native BCH contexts, actual SIB1 UPER round trips and native RO
% geometry feed the decoded-input adapter. No SI waveform reception,
% delivered UE context, beam measurement, Msg1 waveform or gNB RX is claimed.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=configuration();
[mib0,rx0]=receivedMIB(cfg,0,0);
[mib,rx]=receivedMIB(cfg,1,1);
[wrapped,rxWrapped]=receivedMIB(cfg,1025,1);
assert(mib.Data.HalfFrame==1 && mib.Data.AbsoluteFrameNumber==1 && ...
    wrapped.Data.HalfFrame==1 && wrapped.Data.AbsoluteFrameNumber==1025 && ...
    wrapped.Data.ReceivedSFN==1);
n=native(167,30,2);
[tree,bits]=decodedTree(cfg,n,"10100001",40,[]);
f=@sixgr.mac.ra.resolveReceivedPRACHValidity;
before=rng; calls=sixgr.runtime.RuntimeCallLedger.snapshot();
v=f(tree,mib,n); w=f(tree,wrapped,n); z=f(tree,mib0,n);
assert(isequal(before,rng) && isequaln(calls,sixgr.runtime.RuntimeCallLedger.snapshot()));
assert(~v.RuntimeAuthorityVerified && ~v.PHYExecutionPerformed && ...
    ~v.NativeInputIndependentlyAuthenticated && ~v.TDDCommonPresent);
assert(v.ContractVersion=="received_prach_candidate_validity_input/v1" && ...
    v.MIBContextSHA256==mib.SHA256 && v.NativeResolutionSHA256==hash(n));
assert(isequal(v.SSBIntervals.SSBIndex0,[0;2;7]), ...
    'Use every active received bitmap entry, not the one transmitted/decoded test beam.');
ms=sixgr.phy.frame.AbsoluteTime.TicksPerSecond/int64(1000);
assert(v.ReceivedBurstRadioTicks==15*ms && v.SSBBurstPhaseTicks==15*ms && ...
    w.ReceivedBurstRadioTicks==10255*ms && w.SSBBurstPhaseTicks==15*ms && ...
    z.SSBBurstPhaseTicks==0);
% Independent closed-form ordinary 30-kHz normal-CP boundaries. Candidate
% positions are retained original receiver geometry, never current cfg.
symbols=mib.Data.ReceiverGeometry.SSBCandidateStartSymbolsWithinHalfFrame([1 3 8]);
assert(isequal(v.SSBIntervals.StartTicks,15*ms+boundary(symbols(:),30)) && ...
    isequal(v.SSBIntervals.EndTicksExclusive,15*ms+boundary(symbols(:)+4,30)));
assert(isequaln(v.SSBIntervals,w.SSBIntervals) && isequal(v.RepeatedValidity,w.RepeatedValidity) && ...
    isequal(v.DecisionReasons,w.DecisionReasons));
assert(isequaln(v.CandidateSupport,v.Evaluation.CandidateSupport) && ...
    isequaln(v.Evaluation.OriginalOccasions,n.Occasions));
assert(v.ReceiptSHA256==hash(rmfield(v,'ReceiptSHA256')));

% Mutating host settings after reception cannot alter frozen geometry or
% periodicity operands. This adapter does not even accept a cfg parameter.
poison=cfg; poison.phy.ssb.activeBitmap=true(1,8); poison.phy.ssb.halfFrameIndex=0;
poison.phy.ssb.periodicity_ms=160; poison.phy.carrier.NFrame=777; %#ok<NASGU>
assert(isequaln(v,f(tree,mib,n)));
[sparse,sparseBits]=decodedTree(cfg,n,"10000000",20,[]);
assert(~isequal(bits,sparseBits));
s=f(sparse,mib,n);
assert(isequal(s.SSBIntervals.SSBIndex0,0) && s.SSBBurstPhaseTicks==15*ms && ...
    s.EvaluatedPeriodTicks==lcm(int64(n.BasePeriodFrames)*10*ms,20*ms));

% Retain original v1530/base tokens through a legal 3+2-ms combined pattern.
% A lone 3-ms pattern is NOT used: its combined period fails the existing
% common-TDD period guard before this adapter can be exercised.
pattern=struct('dl_UL_TransmissionPeriodicity',"ms2p5", ...
    'dl_UL_TransmissionPeriodicity_v1530',"ms3", ...
    'nrofDownlinkSlots',3,'nrofDownlinkSymbols',0,'nrofUplinkSlots',3,'nrofUplinkSymbols',0);
extensionTDD=struct('referenceSubcarrierSpacing',"kHz30",'pattern1',pattern, ...
    'pattern2',struct('dl_UL_TransmissionPeriodicity',"ms2", ...
    'nrofDownlinkSlots',0,'nrofDownlinkSymbols',0,'nrofUplinkSlots',4,'nrofUplinkSymbols',0));
[extensionTree,extensionBits]=decodedTree(cfg,n,"10100001",40,extensionTDD);
extension=f(extensionTree,mib,n);
originalExtension=extensionTree.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon;
assert(extension.TDDCommonPresent && ...
    isequaln(extension.Evaluation.OriginalCommonConfiguration.TDDCommonIE,originalExtension) && ...
    string(originalExtension.pattern1.dl_UL_TransmissionPeriodicity)=="ms2p5" && ...
    string(originalExtension.pattern1.dl_UL_TransmissionPeriodicity_v1530)=="ms3" && ...
    string(originalExtension.pattern2.dl_UL_TransmissionPeriodicity)=="ms2");
assert(extension.EvaluatedPeriodTicks==lcm(lcm(int64(n.BasePeriodFrames)*10*ms,5*ms),40*ms));

% A legal 10-ms DL + 10-ms UL pair changes the mask across native 10-ms
% periods. Retain the complete joint period, never just its first column.
tdd=struct('referenceSubcarrierSpacing',"kHz30", ...
    'pattern1',struct('dl_UL_TransmissionPeriodicity',"ms10", ...
    'nrofDownlinkSlots',20,'nrofDownlinkSymbols',0,'nrofUplinkSlots',0,'nrofUplinkSymbols',0), ...
    'pattern2',struct('dl_UL_TransmissionPeriodicity',"ms10", ...
    'nrofDownlinkSlots',0,'nrofDownlinkSymbols',0,'nrofUplinkSlots',20,'nrofUplinkSymbols',0));
[changingTree,changingBits]=decodedTree(cfg,n,"10100001",40,tdd);
changing=f(changingTree,mib,n);
originalTDD=changingTree.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon;
assert(changing.TDDCommonPresent && isequaln(changing.Evaluation.OriginalCommonConfiguration.TDDCommonIE,originalTDD));
assert(changing.EvaluatedPeriodTicks==lcm(lcm(int64(n.BasePeriodFrames)*10*ms,20*ms),40*ms));
assert(size(changing.RepeatedValidity,2)>1 && ...
    any(changing.RepeatedValidity~=changing.RepeatedValidity(:,1),'all') && ...
    ~changing.SelectionSupportsAllPeriods, ...
    'Keep all joint-period masks; this test must exercise genuinely changing validity.');
q=request(changingTree,mib);
reject(@()sixgr.mac.ra.resolveReceivedSSBPRACHSelection(changingTree,mib,n,changing,q), ...
    'sixgr:mac:ra:AssociationPatternNotImplemented');

% Compatible repeating output passes directly to the existing production
% selection consumer. These availability/selection inputs remain DECLARED.
allUL=struct('referenceSubcarrierSpacing',"kHz30",'pattern1', ...
    struct('dl_UL_TransmissionPeriodicity',"ms2p5",'nrofDownlinkSlots',0, ...
    'nrofDownlinkSymbols',0,'nrofUplinkSlots',5,'nrofUplinkSymbols',0));
[simple,~]=decodedTree(cfg,n,"10000000",5,allUL);
sv=f(simple,mib,n); assert(sv.SelectionSupportsAllPeriods);
selection=sixgr.mac.ra.resolveReceivedSSBPRACHSelection(simple,mib,n,sv,request(simple,mib));
assert(selection.Available && selection.ValiditySHA256==hash(sv) && ...
    selection.MIBContextSHA256==mib.SHA256 && ~selection.RuntimeAuthorityVerified);

% Long metadata uses exact native CP/useful support and shared absent-SCS
% semantics. The codec may already retain a derived semantic SCS: deleting
% it below is an explicitly declared optional-field boundary, not new UPER.
long=native(0,1.25,1);
[longTree,~]=decodedTree(cfg,long,"10000000",20,[]);
lv=f(longTree,mib,long);
assert(isequal(lv.CandidateSupport.ActiveStartTicks,long.Occasions.PRACHActiveStartTicks) && ...
    isequal(lv.CandidateSupport.ActiveEndTicksExclusive,long.Occasions.PRACHActiveEndTicksExclusive));
longAbsent=longTree; r=rach(longAbsent); r=rmfield(r,'msg1SubcarrierSpacing_kHz');
longAbsent=withRACH(longAbsent,r); la=f(longAbsent,mib,long);
assert(isequal(lv.RepeatedValidity,la.RepeatedValidity));

% Typed identity/configuration guards. None may be rescued from host cfg.
bad=n; bad.ConfigurationIndex=bad.ConfigurationIndex+1; reject(@()f(tree,mib,bad),'sixgr:mac:ra:ReceivedValidityNativeMismatch');
bad=n; bad.Msg1FDM=1; reject(@()f(tree,mib,bad),'sixgr:mac:ra:ReceivedValidityNativeMismatch');
bad=n; bad.CarrierCyclicPrefix="extended"; reject(@()f(tree,mib,bad),'sixgr:mac:ra:ReceivedValidityNativeMismatch');
bad=n; bad.DuplexMode="FDD"; reject(@()f(tree,mib,bad),'sixgr:mac:ra:ReceivedValidityNativeMismatch');
bad=n; bad.DirectionPeriodSlots=5; reject(@()f(tree,mib,bad),'sixgr:phy:ra:PRACHValidityPrefilteredNativeUnsupported');
reject(@()f(tree,mib,rmfield(n,'CarrierCyclicPrefix')),'sixgr:mac:ra:ReceivedValidityNativeRequired');
reject(@()f(tree,mib.Data,n),'sixgr:mac:ra:ReceivedValidityMIBRequired');
bad=tree; bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.ssb_PositionsInBurst.inOneGroup="01000000";
reject(@()f(bad,mib,n),'sixgr:mac:ra:ReceivedValidityBitmapMismatch');
bad=tree; bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.ssb_periodicityServingCell="ms15";
reject(@()f(bad,mib,n),'sixgr:mac:ra:ReceivedValidityClockMismatch');
bad=tree; bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon=[];
reject(@()f(bad,mib,n),'sixgr:mac:ra:ReceivedValidityClockMismatch');
bad=tree; r=rach(bad); r.msg1FrequencyStart=r.msg1FrequencyStart+1; bad=withRACH(bad,r);
reject(@()f(bad,mib,n),'sixgr:mac:ra:ReceivedValidityNativeMismatch');
parent=fullfile(pwd,'results','validation','received_prach_validity');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
save(fullfile(folder,'original_inputs_and_validity.mat'),'cfg','mib0','mib','wrapped','rx0','rx','rxWrapped', ...
    'tree','bits','n','v','w','z','extensionTree','extensionBits','extension', ...
    'changingTree','changingBits','changing','selection','long','lv','-v7.3');
fprintf('RECEIVED_PRACH_VALIDITY_PASS native_BCH=3 actual_UPER=1 native_RO_geometry=1 runtime_or_Msg1=0 folder=%s\n',folder);
ok=true;
end

function [mib,rx]=receivedMIB(cfg,frame,half)
cfg.phy.carrier.NFrame=frame; cfg.phy.ssb.halfFrameIndex=half;
tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'Content','SSB_MIB');
first=tx.BroadcastStartSample; fs=tx.SampleRateHz;
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(tx.Waveform,1),fs,size(tx.Waveform,2));
o.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,first),fs);
[rx,mib]=sixgr.phy.broadcast.recoverSIB1FromWaveform(o,cfg,'RecoveryScope','SSB_MIB');
assert(rx.SSBMIBComplete && isa(mib,'sixgr.phy.broadcast.ReceivedMIBContext'));
assert(mib.Data.AbsoluteFrameNumber==frame && mib.Data.HalfFrame==half);
end
function cfg=configuration()
cfg=sixgr.config.defaultConfig(); cfg.run.strictMode=true;
cfg.phy.sib1.enable=true; cfg.phy.carrier.NCellID=17;
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.carrier.NSizeGrid=51; cfg.phy.channelBandwidth_MHz=20;
cfg.frequency.bandwidth_hz=20e6; cfg.channel.bandwidth_Hz=20e6;
cfg.frequency.band_name="n40"; cfg.initial_access.band_context="n40";
cfg.frequency.center_frequency_hz=2.35e9; cfg.phy.carrier.centerFrequency_Hz=2.35e9;
cfg.phy.fc_Hz=2.35e9; cfg.channel.fc_Hz=2.35e9;
cfg.initial_access.spectrum="unpaired"; cfg.frequency.spectrum="unpaired";
cfg.initial_access.shared_spectrum=false; cfg.frequency.shared_spectrum=false;
cfg.phy.ssb.blockPattern="Case C"; cfg.phy.ssb.scs_kHz=30; cfg.phy.ssb.Lmax=8;
cfg.phy.ssb.NCRBSSB=30; cfg.phy.ssb.KSSB=0;
cfg.phy.ssb.periodicity_ms=10; cfg.phy.ssb.period_ms=10;
cfg.phy.sib1.ssbObservationSubframes=10;
cfg.phy.ssb.activeBitmap=logical([1 0 0 0 0 0 0 0]);
cfg.phy.ssb.runtimeSSBIndex=0; cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
cfg.initial_access.type0=struct('monitoring_occasion_ordinal',1);
cfg.phy.sib1.coreset0Index=0; cfg.phy.sib1.searchSpaceZero=4;
cfg.phy.mib.pdcchConfigSIB1=4; cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.sync.fineCFOEnabled=true;
end
function n=native(index,scs,fdm)
n=sixgr.phy.frame.PRACHOccasionResolver.resolve('FrequencyRange',"FR1", ...
    'DuplexMode',"TDD",'ConfigurationIndex',index,'CarrierSubcarrierSpacingKHz',30, ...
    'CarrierCyclicPrefix',"normal",'NSizeGrid',51,'NStartGrid',0,'NCellID',17, ...
    'PRACHSubcarrierSpacingKHz',scs,'SequenceIndex',0,'PreambleIndex',0, ...
    'RestrictedSet',"UnrestrictedSet",'ZeroCorrelationZone',0,'Msg1FDM',fdm,'Msg1FrequencyStart',0);
end
function [tree,bits]=decodedTree(cfg,n,bitmap,period,tdd)
cfg.initial_access.ssb.positions_in_burst=bitmap; cfg.initial_access.ssb.periodicity_ms=period;
cfg.phy.prach.configurationIndex=n.ConfigurationIndex; cfg.phy.prach.rootSeqIndex=0;
cfg.phy.prach.zeroCorrelationZone=0; cfg.phy.prach.restrictedSet="UnrestrictedSet";
cfg.phy.prach.subcarrierSpacing_kHz=n.PRACHSubcarrierSpacingKHz;
cfg.phy.prach.preambleFormat=n.Format; cfg.phy.prach.nPreambles=64;
cfg.random_access.msg1_fdm=n.Msg1FDM; cfg.random_access.frequency_start=0;
cfg.rrc.sib1.ssb_per_rach_choice="one"; cfg.rrc.sib1.cb_preambles_per_ssb="n64";
cfg.phy.duplex=struct('mode','TDD'); cfg.rrc.sib1.tdd_ul_dl_config_common=tdd;
original=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
bits=sixgr.rrc.asn1.encodeSIB1UPER(original); tree=sixgr.rrc.asn1.decodeSIB1UPER(bits);
assert(sixgr.rrc.asn1.compareSIB1Trees(original,tree));
end
function t=boundary(symbol,scs)
% Independent normal-CP equation, not the production AbsoluteTime method.
mu=log2(scs/15); half=int64(983040); perHalf=7*2^mu;
t=int64(floor(double(symbol)/perHalf))*half+int64(mod(double(symbol),perHalf))*int64(140288/2^mu);
t=t+int64(mod(double(symbol),perHalf)>0)*int64(1024);
end
function q=request(tree,mib)
[~,h]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
first=int64(mib.Data.AbsoluteFrameNumber+4)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
q=struct('MIBContextSHA256',mib.SHA256,'SIB1TreeSHA256',string(h.RxTreeHash), ...
    'SelectedSSBIndex0',0,'CBPreambleOffset0',0,'KnowledgeSample',mib.Data.AvailableAtSample, ...
    'SIB1AvailableAtSample',mib.Data.AvailableAtSample,'SelectedSSBAvailableAtSample',mib.Data.AvailableAtSample, ...
    'SelectedSSBReferenceSHA256',hash(struct('DeclaredBoundaryOnly',true)), ...
    'EarliestRadioTicks',first,'EndRadioTicks',first+int64(64)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame);
end
function r=rach(tree)
r=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
end
function tree=withRACH(tree,r)
tree.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=r;
end
function h=hash(x)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(x))));
end
function reject(fn,id)
try
    fn();
catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingReceivedValidityRejection','Expected %s.',id);
end
