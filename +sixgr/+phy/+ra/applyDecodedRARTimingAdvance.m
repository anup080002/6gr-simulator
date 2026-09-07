function out = applyDecodedRARTimingAdvance(waveform, rar, firstULSCSkHz, sampleRateHz)
% UE consumes the actually recovered MAC RAR, never the gNB detector value.
if ~isstruct(rar) || ~isscalar(rar) || ~isfield(rar,'TimingAdvanceCommand')
    error('sixgr:phy:ra:MissingDecodedRARTimingCommand', ...
        'A recovered MAC RAR timing command is required before transmitting scheduled UL.');
end
timing = sixgr.phy.ra.resolveRARTimingAdvance( ...
    rar.TimingAdvanceCommand,firstULSCSkHz,sampleRateHz);
if abs(timing.Samples-round(timing.Samples)) > 1e-9
    error('sixgr:phy:ra:RARTimeNotOnSampleClock', ...
        'RAR TA requires %.12g samples at %.12g Hz; the integer-shift stage cannot round it.', ...
        timing.Samples,sampleRateHz);
end
out = sixgr.phy.ra.applyMsg3TimingAdvance(waveform,round(timing.Samples));
out.RARTiming = timing;
out.TimingAdvanceSource = "received_MAC_RAR_absolute_command_ts_38_213_4_2";
% This existing isolated stage still shifts a finite window. It is not a
% replacement for distinct UE-TX/gNB-RX origins in the shared stream owner.
end
