function ok = testSharedSlotReceiverFrontEndOrder()
%TESTSHAREDSLOTRECEIVERFRONTENDORDER Guard composite Rx RF/ADC ordering.

setup6GRSimToolkit("Verbose", false);

fs = 30.72e6;
cfg = struct();
cfg.lls6g.userContext.RuntimeCurrentDirection = "DL";
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.rf.adc.enable = true;
cfg.rf.adcBits = 4;
cfg.rf.adc.fullScale = 1;

desired = complex(1e-3 * ones(128, 1), zeros(128, 1));
interferer = complex(0.45 * ones(128, 1), zeros(128, 1));

[earlyQuantized, earlyReplay] = sixgr.link.applyWaveformImpairments(desired, cfg, fs, ...
    "Endpoint", "rx", "ApplyRFChain", true);
assert(logical(earlyReplay.ADCQuantizationApplied), ...
    "Regression setup must enable ADC quantization.");
assert(mean(abs(double(earlyQuantized(:))).^2) == 0, ...
    "A tiny per-link desired waveform should expose the old early-ADC zeroing failure.");

[desiredAnalog, replay] = sixgr.link.applyWaveformImpairments(desired, cfg, fs, ...
    "Endpoint", "rx", "ApplyRFChain", false);
assert(mean(abs(double(desiredAnalog(:))).^2) > 0, ...
    "Per-link large-scale contribution must stay analog before shared-slot summation.");
assert(string(replay.RFExecutionStatus) == "deferred_composite_receiver_front_end", ...
    "Per-link receiver front-end must be deferred until after waveform summation.");

compositeAnalog = desiredAnalog + interferer;
[compositeRx, replay] = sixgr.link.applyCompositeReceiverFrontEnd( ...
    compositeAnalog, cfg, fs, replay, "Direction", "DL");
assert(logical(replay.CompositeReceiverFrontEndApplied) && logical(replay.ADCQuantizationApplied), ...
    "Composite receiver front-end must apply the common AGC/ADC stage once.");
assert(mean(abs(double(compositeRx(:))).^2) > 0, ...
    "Composite receiver waveform must remain nonzero after common ADC.");
assert(string(replay.CompositeReceiverFrontEndOrder) == ...
    "channel_per_link_large_scale_then_shared_slot_sum_then_noise_then_rx_rf_adc", ...
    "Receiver front-end ordering replay must be explicit.");

ok = true;
end
