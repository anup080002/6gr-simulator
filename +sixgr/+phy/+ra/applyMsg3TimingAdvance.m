function out = applyMsg3TimingAdvance(waveform, timingAdvanceSamples)
%APPLYMSG3TIMINGADVANCE Apply decoded TA to Msg3 waveform before gNB Rx.
% Msg3 now delegates to the same explicit UL waveform placement contract
% used by FDD. Fractional or negative commands are rejected rather than
% rounded into a different timing instruction.
out = sixgr.phy.frame.applyULTimingAdvance( ...
    waveform, double(timingAdvanceSamples));
end
