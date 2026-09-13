function verifyPUCCHPowerExport(T,cfg)
% Check the actual shared receiver row and a lossless diagnostic CSV roundtrip.
assert(istable(T) && height(T)==1);
mu=log2(cfg.phy.carrier.SubcarrierSpacing/15);
assert(T.PUCCHPowerControlMu==mu && T.PUCCHPowerControlMRB==T.PUCCHPRBCount);
assert(abs(T.PUCCHPowerBandwidthTerm_dB-10*log10(2^mu*T.PUCCHPRBCount))<1e-12);
assert(string(T.PUCCHPowerBandwidthSource)=="selected_pucch_resource_and_active_carrier_scs");
assert(isfinite(T.PUCCHRequestedTxPower_dBm) && isfinite(T.PUCCHPowerControlPathloss_dB));
fixedReference=upper(string(cfg.integration.run_mode))=="FIXED_SNR_SWEEP" && ...
    cfg.integration.configured_snr_is_link_authority;
if fixedReference
    assert(~T.PUCCHPowerHeadroomApplicable && isnan(T.PUCCHPowerHeadroom_dB));
    assert(T.PUCCHPowerControlTargetHeadroom_dB==T.PUCCHPCMAX_dBm-T.PUCCHRequestedTxPower_dBm);
    assert(contains(string(T.PUCCHPowerHeadroomSource),"diagnostic_only"));
    assert(T.PUCCHNormalizedPowerReference && ~T.PUCCHPhysicalPowerApplicable && isnan(T.PUCCHAppliedTxPower_dBm));
    assert(T.PUCCHNormalizedReferenceEnergyPerRE==1 && ...
        isfinite(T.PUCCHNormalizedActiveMeanSquare) && T.PUCCHNormalizedActiveMeanSquare>0);
    assert(string(T.PUCCHAppliedTxPowerReferencePlane)=="normalized_occupied_re_pre_node_rf_contribution");
else
    assert(T.PUCCHPowerHeadroomApplicable && isfinite(T.PUCCHPowerHeadroom_dB));
    assert(T.PUCCHAppliedTxPower_dBm==min(T.PUCCHPCMAX_dBm,T.PUCCHRequestedTxPower_dBm));
    assert(string(T.PUCCHAppliedTxPowerReferencePlane)=="pre_node_rf_transmitter_contribution");
end
file=[tempname '.csv'];
cleanup=onCleanup(@()localRemove(file)); %#ok<NASGU>
sixgr.util.csvWriteTable(file,T,'PreserveSchema',true);
persisted=sixgr.util.csvReadTable(file,'TextType','string');
for name=["PUCCHPowerControlMu","PUCCHPowerControlMRB","PUCCHPowerBandwidthTerm_dB", ...
        "PUCCHRequestedTxPower_dBm","PUCCHAppliedTxPower_dBm", ...
        "PUCCHPowerHeadroom_dB","PUCCHPowerControlTargetHeadroom_dB"]
    assert(isequaln(double(T.(name)),double(persisted.(name))) || ...
        abs(double(T.(name))-double(persisted.(name)))<1e-12, ...
        'Actual PUCCH power evidence did not survive CSV serialization: %s.',name);
end
disp('PUCCH_POWER_EXPORT_PASS: actual shared receiver ledger, scoped power plane, CSV roundtrip.');
end

function localRemove(file)
if isfile(file), delete(file); end
end
