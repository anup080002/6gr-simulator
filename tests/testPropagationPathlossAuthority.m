function ok=testPropagationPathlossAuthority()
% Explicit physical-link/UE-estimator unit inputs, not campaign evidence.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.lls6g.userContext=struct('RuntimeCurrentDirection','UL', ...
    'RuntimePropagationPathloss_dB',110, ...
    'RuntimePropagationPathlossSource','analytical_physical_link_fixture', ...
    'RuntimeServingPathloss_dB',80, ...
    'RuntimeServingPathlossSource','ue_decoded_sib1_power_minus_filtered_ssb_rsrp');
wave=complex(ones(128,1));
for estimate=[80 140 NaN]
    cfg.lls6g.userContext.RuntimeServingPathloss_dB=estimate;
    [~,replay]=sixgr.link.applyWaveformImpairments(wave,cfg,7.68e6,'ApplyRFChain',false);
    assert(replay.AppliedLargeScaleLoss_dB==110 && replay.AppliedPathloss_dB==110, ...
        'Changing a UE pathloss estimate must not change physical propagation.');
    assert(string(replay.PropagationPathlossAuthority)=="explicit_runtime_physical_propagation");
end
cfg.lls6g.userContext.RuntimePropagationPathloss_dB=100;
[~,replay]=sixgr.link.applyWaveformImpairments(wave,cfg,7.68e6,'ApplyRFChain',false);
assert(replay.AppliedLargeScaleLoss_dB==100,'Physical channel changes must still take effect.');

% A configured-Es/N0 LLS may inherit a dormant geometry context, but it
% must not publish the identity transform as 0 dB pathloss or apply O2I.
cfgFixed = cfg;
cfgFixed.integration = struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true);
cfgFixed.run.noiseOperatingMode = 'standalone_awgn_snr_argument';
cfgFixed.channel.snr_dB = 12;
cfgFixed.lls6g.userContext.RuntimeServingBasePathloss_dB = 91;
cfgFixed.lls6g.userContext.RuntimeServingShadowFading_dB = 4;
cfgFixed.lls6g.userContext.RuntimeServingO2I_dB = 18;
[fixedWave,replayFixed]=sixgr.link.applyWaveformImpairments( ...
    wave,cfgFixed,7.68e6,'ApplyRFChain',false);
assert(all(fixedWave==wave,'all') && replayFixed.AppliedLargeScaleLoss_dB==0 && ...
    isnan(replayFixed.AppliedBasePathloss_dB) && ...
    isnan(replayFixed.AppliedPathloss_dB) && ...
    isnan(replayFixed.AppliedShadowFading_dB) && ...
    isnan(replayFixed.AppliedO2I_dB) && ...
    string(replayFixed.PropagationPathlossAuthority)== ...
        "not_applicable_fixed_configured_esn0", ...
    ['Fixed configured-Es/N0 LLS must use an identity large-scale gain ' ...
     'without claiming a zero-dB pathloss measurement.']);

cfg.lls6g.userContext.RuntimeServingPathloss_dB=80;
cfg.lls6g.userContext.RuntimePropagationPathloss_dB=NaN;
try
    sixgr.link.applyWaveformImpairments(wave,cfg,7.68e6,'ApplyRFChain',false);
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:InvalidPropagationPathloss'),cause.message);
    ok=true; disp('PROPAGATION_PATHLOSS_AUTHORITY_PASS: UE estimate cannot attenuate physical channel.');
    return;
end
error('test:MissingRejection','Invalid explicit physical pathloss must not fall back to a UE estimate.');
end
