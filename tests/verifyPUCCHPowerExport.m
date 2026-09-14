function verifyPUCCHPowerExport(T,cfg)
% Check the actual shared receiver row and a lossless diagnostic CSV roundtrip.
assert(istable(T) && height(T)==1);
mu=log2(cfg.phy.carrier.SubcarrierSpacing/15);
assert(T.PUCCHPowerControlMu==mu && T.PUCCHPowerControlMRB==T.PUCCHPRBCount);
assert(abs(T.PUCCHPowerBandwidthTerm_dB-10*log10(2^mu*T.PUCCHPRBCount))<1e-12);
assert(string(T.PUCCHPowerBandwidthSource)=="selected_pucch_resource_and_active_carrier_scs");
% Integration is optional for the physical-link-budget FDD fixture. Only an
% explicitly configured normalized sweep changes the absolute-power contract,
% matching applyPowerContext; never infer the expected plane from output rows.
fixedReference=upper(strtrim(string(sixgr.util.structGet(cfg, ...
    'integration.run_mode',''))))=="FIXED_SNR_SWEEP" && ...
    logical(sixgr.util.structGet(cfg,'integration.configured_snr_is_link_authority',false));
if fixedReference
    assert(~T.PUCCHPowerHeadroomApplicable && isnan(T.PUCCHPowerHeadroom_dB));
    assert(isnan(T.PUCCHRequestedTxPower_dBm) && isnan(T.PUCCHPowerControlPathloss_dB) && ...
        isnan(T.PUCCHPowerControlTargetHeadroom_dB) && isnan(T.PUCCHPCMAX_dBm), ...
        'Normalized TX must not manufacture an absolute power-control target or pathloss.');
    assert(string(T.PUCCHPowerHeadroomSource)=="not_applicable_normalized_esn0_no_absolute_power_target");
    assert(T.PUCCHNormalizedPowerReference && ~T.PUCCHPhysicalPowerApplicable && isnan(T.PUCCHAppliedTxPower_dBm));
    assert(T.PUCCHNormalizedReferenceEnergyPerRE==1 && ...
        isfinite(T.PUCCHNormalizedActiveMeanSquare) && T.PUCCHNormalizedActiveMeanSquare>0);
    assert(string(T.PUCCHAppliedTxPowerReferencePlane)=="normalized_occupied_re_pre_node_rf_contribution");
else
    assert(isfinite(T.PUCCHRequestedTxPower_dBm) && isfinite(T.PUCCHPowerControlPathloss_dB));
    assert(T.PUCCHPhysicalPowerApplicable && ~T.PUCCHNormalizedPowerReference);
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
        "PUCCHPowerHeadroom_dB","PUCCHPowerControlTargetHeadroom_dB", ...
        "ReceiverInjectedNoiseVarianceConsumed"]
    assert(isequaln(double(T.(name)),double(persisted.(name))) || ...
        abs(double(T.(name))-double(persisted.(name)))<1e-12, ...
        'Actual PUCCH power evidence did not survive CSV serialization: %s.',name);
end
assert(string(persisted.ReceiverInputSampleNoiseVarianceValueRole)== ...
    string(T.ReceiverInputSampleNoiseVarianceValueRole), ...
    'Receiver-vs-injection provenance must survive CSV serialization.');
disp('PUCCH_POWER_EXPORT_PASS: actual shared receiver ledger, scoped power plane, CSV roundtrip.');
end

function localRemove(file)
if isfile(file), delete(file); end
end
