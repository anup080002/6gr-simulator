function ok=testServingSSBTrackingPolicy()
% Policy/configuration checks, not on-air acquisition qualification.
cfg=struct(); cfg.phy.prach.enable=true;
p=sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
assert(p.Required && p.RASSBPowerReferenceRequired && ...
    ~p.ConnectedMeasuredPathlossReferenceRequired, ...
    'PRACH retries require periodic measured SSB power even with connected UL power control disabled.');
cfg.phy.pusch.powerControl.requireMeasuredReferenceRS=true;
cfg.phy.pusch.powerControl.pathlossReference=struct( ...
    'reference_signal_type','CSI-RS','reference_signal_id',7,'maximum_age_slots',20);
p=sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
assert(p.Required && p.RASSBPowerReferenceRequired && ...
    p.ConnectedMeasuredPathlossReferenceRequired && ~p.ConnectedSSBPowerReferenceRequired, ...
    'Connected CSI-RS does not replace the SSB selected for PRACH.');
cfg.phy.prach.enable=false;
p=sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
assert(~p.Required && ~p.RASSBPowerReferenceRequired);
cfg.phy.pusch.powerControl.pathlossReference.reference_signal_type='SSB';
p=sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
assert(p.Required && p.ConnectedSSBPowerReferenceRequired);
cfg=struct(); cfg.phy.prach.enable=true;
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true);
p=sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
assert(~p.Required && ~p.RASSBPowerReferenceRequired, ...
    'Do not introduce an absolute-power requirement into normalized fixed-Es/N0 PRACH.');
% Preserve every installed connected-control spelling. The production
% resolver and the gating path must not have different lists of consumers.
paths=["phy.pusch.power_control.require_measured_reference_rs", ...
    "phy.pusch.powerControl.requireMeasuredReferenceRS", ...
    "lls6g.pucch_resources.power_control.require_measured_reference_rs", ...
    "lls6g.resolvedConfig.pucch_resources.power_control.require_measured_reference_rs", ...
    "validation.pucch_resources.power_control.require_measured_reference_rs", ...
    "pucch_resources.power_control.require_measured_reference_rs"];
for path=paths
    c=struct(); c.phy.prach.enable=false;
    c.phy.pusch.powerControl.pathlossReference=struct( ...
        'reference_signal_type','SSB','reference_signal_id',0,'maximum_age_slots',20);
    c=sixgr.util.structSet(c,path,true);
    p=sixgr.truth.resolveServingSSBTrackingPolicy(c);
    assert(p.Required && p.ConnectedSSBPowerReferenceRequired && ~p.RASSBPowerReferenceRequired);
end
ok=true;
disp('SERVING_SSB_TRACKING_POLICY_PASS: PRACH and connected consumers retain separate measured-reference authority.');
end
