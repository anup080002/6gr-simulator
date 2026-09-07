function timing = sharedULStageTiming(cfg, nominalStartSeconds, sampleRateHz, sampleCount, ntaTicks)
% TS 38.211 4.3.1: complete UE TX origin relative to received DL timing.
% gNB RX window is based on its own nominal grid/common offset/search budget,
% never shifted to the UE's estimated phase or the UE's actual TX timestamp.
context=cfg.SharedULTimingContext; reference=context.DLReference; offset=context.Offset;
assert(reference.Source=="received_SSB_timing_and_decoded_BCH" && reference.SampleRateHz==sampleRateHz, ...
    'sixgr:phy:ra:MissingReceivedDLClock','Shared UL requires the received DL sample clock.');
validateattributes(ntaTicks,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/sampleRateHz;
nominal=nominalStartSeconds*sampleRateHz;
advanceTicks=int64(ntaTicks)+offset.NTAOffset_Tc;
if tc~=fix(tc) || rem(advanceTicks,int64(tc))~=0 || rem(offset.NTAOffset_Tc,int64(tc))~=0 || ...
        abs(nominal-round(nominal))>8*eps(max(1,abs(nominal)))
    error('sixgr:phy:ra:SharedULOriginOffSampleClock','Full UL origins must be exactly representable; do not round TA.');
end
[guard,guardSource]=sixgr.phy.sync.resolveTimingSearchGuard(cfg,sampleRateHz);
nominal=round(nominal);
txStart=nominal+reference.DLPhaseOffsetSamples-double(advanceTicks)/tc;
rxCenter=nominal-double(offset.NTAOffset_Tc)/tc;
if txStart<reference.AvailableAtSample || rxCenter-guard<0
    error('sixgr:phy:ra:ULBeforeReceivedTimingAuthority','UL cannot use a future DL reference or precede the physical clock.');
end
timing=struct('Source',"received_DL_reference_received_RAR_TA_and_common_offset", ...
    'NominalStartSample',nominal,'TransmitStartSample',txStart, ...
    'TransmitEndSampleExclusive',txStart+sampleCount, ...
    'ReceiveStartSample',rxCenter-guard,'ReceiveEndWithoutChannelTail',rxCenter+sampleCount+guard, ...
    'ReceiveSearchGuardSamples',guard,'ReceiveSearchGuardSource',guardSource, ...
    'SampleRateHz',sampleRateHz,'NTA_Tc',int64(ntaTicks),'NTAOffset_Tc',offset.NTAOffset_Tc, ...
    'DLReference',reference,'TimingOffsetSource',offset.Source, ...
    'WaveformTimingApplied',true,'FiniteWaveformCropped',false);
end
