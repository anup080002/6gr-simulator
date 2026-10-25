function testPRACHReceiveWindow()
% Declared native-shaped clock operands only; NO native PRACH or RX claim.
resolve=@sixgr.phy.ra.planPRACHReceiveWindow;
tc=int64(64); fs=30.72e6;
row=table(1,9,0,0,9,int64(276480)*tc,int64(307200)*tc, ...
    int64(276500)*tc,int64(305000)*tc,'VariableNames', ...
    {'Ordinal','PRACHSlot','FrequencyIndex','RARNTISymbolIndex','RARNTISlotIndex', ...
    'PRACHWaveformStartTicks','PRACHWaveformEndTicksExclusive','PRACHActiveStartTicks','PRACHActiveEndTicksExclusive'});
n=struct('ContractVersion',"sixgr_prach_occasion_release18/v1",'FrequencyRange',"FR1", ...
    'PeriodFrames',1,'PeriodPRACHSlots',10,'Occasions',row, ...
    'ResolvedValid',true,'FallbackUsed',false,'UnknownIndexDefaulted',false);
r=struct('CellID',1,'ConfigurationEpoch',2,'SampleRateHz',fs,'RadioFrameZeroSample',0, ...
    'ConfigurationAvailableAtSample',0,'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"", ...
    'SearchGuardSamples',32,'FilterTailSamples',17,'NumReceiveAntennas',64,'ULCarrierID',0);
original=n; originalReceiver=r;
a=resolve(n,1,r);
assert(isequaln(n,original) && isequaln(r,originalReceiver));
assert(a.ReceiveStartSample==276480-400-32 && a.ReceiveEndSampleExclusive==307200-400+32+17);
assert(a.ReceiverPRACHSlotOriginSample==276480-400 && a.DetectorInputStartOffsetSamples==32);
assert(a.ExpectedRARNTI==127 && isequal(a.CandidatePreambles0,0:63));
assert(~a.ReceiverArmed && ~a.WaveformExecuted && ~a.UETransmissionRequired);
b=resolve(n,3,r);
assert(b.NativePeriodIndex0==2 && b.PRACHSlotIndex0==29 && ...
    b.ReceiveStartSample==a.ReceiveStartSample+614400 && b.ExpectedRARNTI==a.ExpectedRARNTI);
for ie=["n0","n25600","n39936"]
    changed=r; changed.TimingAdvanceOffsetPresent=true; changed.TimingAdvanceOffset=ie;
    b=resolve(n,1,changed);
    expected=sscanf(char(extractAfter(ie,1)),'%d');
    assert(b.ReceiverPRACHSlotOriginSample==276480-double(expected)/double(tc));
    received=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',true,'TimingAdvanceOffset',ie);
    ue=sixgr.phy.frame.resolveULTimingAdvanceOffset(received,'FR1');
    assert(ue.NTAOffset_Tc==b.CommonOffset.NTAOffset_Tc && ue.Source=="received_SIB1_n_TimingAdvanceOffset");
    assert(b.CommonOffset.Rule=="explicit_common_n_TimingAdvanceOffset" && ~isfield(b.CommonOffset,'ReceivedIE'));
end
bad=r; bad.ConfigurationAvailableAtSample=a.ReceiveStartSample+1;
reject(@()resolve(n,1,bad),'sixgr:phy:ra:PRACHReceiveConfigurationTooLate');
bad=r; bad.DLReference=struct();
reject(@()resolve(n,1,bad),'sixgr:phy:ra:PRACHReceiveUEAuthorityForbidden');
bad=n; bad.Occasions.PRACHActiveStartTicks=double(row.PRACHActiveStartTicks);
reject(@()resolve(bad,1,r),'sixgr:phy:ra:PRACHReceiveNativeRequired');
bad=n; bad.Occasions.PRACHActiveEndTicksExclusive=row.PRACHWaveformEndTicksExclusive+tc;
reject(@()resolve(bad,1,r),'sixgr:phy:ra:PRACHReceiveNativeRequired');
bad=n; bad.Occasions.PRACHActiveStartTicks=row.PRACHActiveStartTicks+1;
reject(@()resolve(bad,1,r),'sixgr:phy:ra:PRACHReceiveClockNotExact');
bad=r; bad.TimingAdvanceOffset='n0';
reject(@()resolve(n,1,bad),'sixgr:phy:frame:InconsistentTimingOffsetPresence');
bad=r; bad.TimingAdvanceOffsetPresent=true; bad.TimingAdvanceOffset=0;
reject(@()resolve(n,1,bad),'sixgr:phy:frame:InconsistentTimingOffsetPresence');
fprintf('PRACH_RECEIVE_WINDOW_PASS declared_clock_boundary_only native_PRACH=0 PHY_RX=0\n');
end

function reject(f,id)
try, f(); catch e, assert(strcmp(e.identifier,id),'Expected %s, got %s: %s',id,e.identifier,e.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
