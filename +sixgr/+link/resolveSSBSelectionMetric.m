function metric = resolveSSBSelectionMetric(cfg)
%RESOLVESSBSELECTIONMETRIC Select the receiver-measured SSB power domain.
% A configured-SNR run is normalized occupied-RE Es/N0 and therefore uses a
% relative power metric. Absolute dBm selection is reserved for a physical
% link-budget run with calibrated samples and receiver thermal noise.

if sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)
    metric = "SS_RSRP_dB_re_UnitOccupiedRE_Es";
else
    metric = "SS_RSRP_dBm";
end
end
