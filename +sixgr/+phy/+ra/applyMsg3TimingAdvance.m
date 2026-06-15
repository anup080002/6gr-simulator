function out = applyMsg3TimingAdvance(waveform, timingAdvanceSamples)
%APPLYMSG3TIMINGADVANCE Apply decoded TA to Msg3 waveform before gNB Rx.
timingAdvanceSamples = round(double(timingAdvanceSamples));
out = struct();
out.InputWaveform = waveform;
out.TimingAdvanceApplied = true;
out.TimingAdvanceSamples = double(timingAdvanceSamples);
out.Waveform = sixgr.util.applyFractionalSampleDelay(waveform, -timingAdvanceSamples);
end
