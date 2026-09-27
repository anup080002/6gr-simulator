function ok = testSSBSelectionMetricAuthority()
%TESTSSBSELECTIONMETRICAUTHORITY SNR authority must not imply sample units.

cfg = struct();
cfg.integration = struct( ...
    'run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true, ...
    'power_reference_mode','normalized_unit_es');
assert(sixgr.link.resolveSSBSelectionMetric(cfg) == ...
    "SS_RSRP_dB_re_UnitOccupiedRE_Es", ...
    'Normalized fixed-SNR execution must select beams in relative occupied-RE power.');

cfg.integration.power_reference_mode = 'absolute_calibrated_sqrt_mw';
try
    sixgr.link.resolveSSBSelectionMetric(cfg);
    error('TEST:ExpectedMixedPowerReferenceRejection', ...
        'Absolute device power must not be accepted in a fixed-SNR sweep.');
catch e
    assert(string(e.identifier)=="sixgr:rf:MixedFixedSNRAndAbsolutePower");
end

cfg.integration.run_mode = 'GEOMETRY_NETWORK';
cfg.integration.configured_snr_is_link_authority = false;
assert(sixgr.link.resolveSSBSelectionMetric(cfg) == "SS_RSRP_dBm", ...
    'Geometry/thermal-noise execution must select beams in absolute dBm.');
ok = true;
end
