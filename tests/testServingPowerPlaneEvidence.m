function ok=testServingPowerPlaneEvidence()
state=struct('NoiseOperatingMode',"fixed_reference_snr", ...
    'LargeScaleState',struct('RxPower_dBm',31.488,'PathlossEnabled',false));
original=state;
row=sixgr.truth.bindServingPowerEvidence(struct(),state,1,1);
assert(isnan(row.RxPower_dBm) && row.ModelPredictedRxPower_dBm==31.488);
assert(isequaln(state,original),'Publication must not change the channel/power state.');
state.LargeScaleState.PathlossEnabled=true;
row=sixgr.truth.bindServingPowerEvidence(struct(),state,1,1);
assert(isnan(row.RxPower_dBm),'Path loss alone is not an absolute IQ calibration.');
state.NoiseOperatingMode="receiver_noise_figure_thermal_noise";
state.LargeScaleState.RxPower_dBm=-90;
row=sixgr.truth.bindServingPowerEvidence(struct(),state,1,1);
assert(row.RxPower_dBm==-90 && row.ModelPredictedRxPower_dBm==-90);
assert(row.RxPowerSource=="model_link_budget_not_receiver_sample_measurement");
ok=true;
end
