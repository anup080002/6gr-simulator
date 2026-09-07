function context=connectedTimingFromRAR(cfg,common,rar,rarDLSlot0,receivedAtSample,fs)
% Initial single-cell TAG authority, from received SIB1 and accepted MAC RAR.
% TS 38.213 V18.8.0 4.2; TS 38.321 V18.6.0 5.2. This is NOT the
% RAR-scheduled Msg3 timing exception, a relative TA CE, or a TAG restart.
assert(common.Source=="decoded_sib1" && isfield(common,'TimeAlignmentTimerCommon') && ...
    isfield(common,'ReceivedDLTimingReference') && isfield(common,'ULTimingAdvanceOffset'), ...
    'sixgr:mac:ra:MissingConnectedTimingAuthority','Retain decoded SIB1 timer, offset and received DL clock.');
validateattributes(rarDLSlot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(receivedAtSample,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
dl=common.InitialDLBWP; ul=common.InitialULBWP;
assert(dl.CyclicPrefix=="normal" && ul.CyclicPrefix=="normal", ...
    'sixgr:mac:ra:ConnectedTimingCPNotSupported','An extended-CP application-time authority is not implemented.');
dlMu=log2(double(dl.SubcarrierSpacing_kHz)/15);
ulMu=log2(double(ul.SubcarrierSpacing_kHz)/15);
processingMu=min(dlMu,ulMu);
cap=sixgr.phy.frame.TimingPolicyCatalog.capability1(processingMu);
% Additional DM-RS column, with N1,0=14 mandated specifically by 38.213.
mu=[0 1 2 3 5 6]; n1=[14 13 20 24 96 192];
index=find(mu==processingMu,1);
assert(~isempty(index),'sixgr:mac:ra:UnsupportedTAGNumerology','Missing normative TAG processing numerology.');
ticksPerSecond=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
symbolTicks=(2048+144)*64/2^processingMu;
processingTicks=(n1(index)+cap.PUSCHN2Symbols)*symbolTicks;
maximumTATicks=3846*1024/2^ulMu;
slotTicks=ticksPerSecond*1e-3/2^ulMu;
k=ceil((processingTicks+maximumTATicks+ticksPerSecond*.5e-3)/slotTicks);
% Before dedicated reconfiguration the decoded initial BWPs are the full
% configured set for this initial TAG. Use the last overlapping UL slot,
% not an assumption that the DL and UL numerologies are identical.
n=ceil((rarDLSlot0+1)*2^(ulMu-dlMu))-1;
effectiveULSlot0=n+k+1;
ta=sixgr.phy.ra.resolveRARTimingAdvance(rar.TimingAdvanceCommand,ul.SubcarrierSpacing_kHz,fs);
context=struct('DLReference',common.ReceivedDLTimingReference, ...
    'Offset',common.ULTimingAdvanceOffset,'ReceivedRARTiming',ta, ...
    'TimingAdvanceAvailableAtSample',receivedAtSample);
cfg.SharedULTimingContext=context;
timing=sixgr.phy.ra.sharedULStageTiming(cfg,effectiveULSlot0*1e-3/2^ulMu,fs,1,ta.NTA_Tc);
context.TimingAdvanceEffectiveAtSample=timing.TransmitStartSample;
assert(context.TimingAdvanceEffectiveAtSample>=receivedAtSample, ...
    'sixgr:mac:ra:LateRARTimingDelivery','A late decoder cannot retroactively install timing authority.');
timer=string(common.TimeAlignmentTimerCommon);
if timer=="infinity"
    expiry=Inf;
else
    % TS 38.331 TimeAlignmentTimer enumeration; absence is not infinity.
    enums=["ms500","ms750","ms1280","ms1920","ms2560","ms5120","ms10240"];
    durations=[500 750 1280 1920 2560 5120 10240];
    timerIndex=find(enums==timer,1);
    assert(~isempty(timerIndex),'sixgr:mac:ra:InvalidReceivedTimeAlignmentTimer','Invalid decoded timeAlignmentTimerCommon.');
    samples=durations(timerIndex)*fs/1000;
    assert(samples==fix(samples),'sixgr:mac:ra:TimeAlignmentTimerOffClock','Timer expiry must preserve the sample clock.');
    expiry=receivedAtSample+samples;
end
context.TimeAlignmentExpirySampleExclusive=expiry;
context.TimeAlignmentTimerCommon=timer;
context.Application=struct('Source',"received_initial_TAG_RAR_TS_38.213_4.2", ...
    'ReceivedPDSCHAbsoluteSlot0Based',rarDLSlot0,'LastOverlappingULSlot0Based',n, ...
    'EffectiveULSlot0Based',effectiveULSlot0,'ProcessingMu',processingMu, ...
    'ULMu',ulMu,'N1Symbols',n1(index),'N2Symbols',cap.PUSCHN2Symbols, ...
    'ProcessingTicks',processingTicks,'MaximumTATicks',maximumTATicks, ...
    'ApplicationDelaySlotsK',k,'Koffset',0, ...
    'Scope',"initial_single_cell_TAG_before_dedicated_BWP_or_NTN_configuration");
end
