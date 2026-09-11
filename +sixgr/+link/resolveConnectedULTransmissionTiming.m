function timing=resolveConnectedULTransmissionTiming(cfg,nominalStartSeconds,fs,sampleCount)
% Resolve one complete connected-UL contribution from received initial TAG.
% No waveform, RF/channel state or decoder is executed or modified here.
% RAR NTA excludes the received/common NTA offset. Neither is a receiver's
% sample-alignment estimate. The gNB observation does not follow UE phase.
% Relative TA MAC CEs, later BWP changes and NTN need their own TAG authority;
% this adapter must not reinterpret those as an initial absolute RAR command.
validateattributes(nominalStartSeconds,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(sampleCount,{'numeric'},{'scalar','real','finite','integer','positive'});
context=sixgr.util.structGet(cfg,'SharedULTimingContext',struct());
required={'DLReference','Offset','ReceivedRARTiming','TimingAdvanceAvailableAtSample', ...
    'TimingAdvanceEffectiveAtSample','TimeAlignmentExpirySampleExclusive'};
assert(isstruct(context) && isscalar(context) && all(isfield(context,required)), ...
    'sixgr:link:MissingConnectedULTiming','Retain the received DL clock, common offset, RAR timing and TAG lifetime.');
reference=context.DLReference;
assert(isstruct(reference) && isscalar(reference) && all(isfield(reference, ...
    {'Source','SampleRateHz','DLPhaseOffsetSamples','AvailableAtSample'})), ...
    'sixgr:link:MissingConnectedULClock','A complete received DL timing reference is required.');
validateattributes(reference.DLPhaseOffsetSamples,{'numeric'},{'scalar','real','finite','integer'});
validateattributes(reference.AvailableAtSample,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
ta=context.ReceivedRARTiming;
assert(isstruct(ta) && isscalar(ta) && all(isfield(ta,{'Command','FirstULSCSkHz'})), ...
    'sixgr:link:MissingConnectedULRAR','Retain the decoded absolute RAR timing command and first UL numerology.');
resolvedTA=sixgr.phy.ra.resolveRARTimingAdvance(ta.Command,ta.FirstULSCSkHz,fs);
assert(isequaln(ta,resolvedTA),'sixgr:link:ConnectedULTimingAuthorityMismatch', ...
    'RAR command, numerology, sample rate and timing conversion must agree exactly.');
offset=context.Offset;
assert(isstruct(offset) && isscalar(offset) && all(isfield(offset, ...
    {'IEPresent','ReceivedIE','FrequencyRange'})), ...
    'sixgr:link:MissingConnectedULOffset','Retain received common-offset IE presence and frequency range.');
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',offset.IEPresent, ...
    'TimingAdvanceOffset',offset.ReceivedIE);
resolvedOffset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,offset.FrequencyRange);
assert(isequaln(offset,resolvedOffset),'sixgr:link:ConnectedULOffsetAuthorityMismatch', ...
    'Common timing offset must agree with its received IE and normative frequency-range rule.');
timing=sixgr.phy.ra.sharedULStageTiming(cfg,nominalStartSeconds,fs,sampleCount,ta.NTA_Tc);
available=context.TimingAdvanceAvailableAtSample;
effective=context.TimingAdvanceEffectiveAtSample;
validateattributes(available,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(effective,{'numeric'},{'scalar','real','finite','integer','>=',available});
assert(timing.TransmitStartSample>=available,'sixgr:link:ConnectedULBeforeReceivedTA', ...
    'A connected UL contribution cannot use a future decoded timing command.');
assert(timing.TransmitStartSample>=effective,'sixgr:link:ConnectedULBeforeTAApplication', ...
    'The received timing command must be applicable before the contribution starts.');
expiry=context.TimeAlignmentExpirySampleExclusive;
validateattributes(expiry,{'numeric'},{'scalar','real','positive','nonnan'});
assert(isinf(expiry) || expiry==fix(expiry),'sixgr:link:InvalidConnectedULExpiry', ...
    'TAG expiry must lie on the physical sample clock or be explicitly infinite.');
assert(timing.TransmitEndSampleExclusive<=expiry,'sixgr:link:ConnectedULAfterTAExpiry', ...
    'The complete connected UL contribution requires valid time alignment.');
timing.TimingAdvanceAvailableAtSample=available;
timing.TimingAdvanceEffectiveAtSample=effective;
timing.TimeAlignmentExpirySampleExclusive=expiry;
timing.ReceivedRARTiming=ta;
timing.TotalAdvanceTicks=int64(ta.NTA_Tc)+offset.NTAOffset_Tc;
% Resolution alone does not place a transmitted sample. The preparation
% owner must record application after installing these exact origins.
timing.OriginsResolved=true;
timing.WaveformTimingApplied=false;
end
