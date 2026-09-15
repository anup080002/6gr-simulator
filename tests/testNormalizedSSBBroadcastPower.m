function ok=testNormalizedSSBBroadcastPower()
% Full-burst completion's actual TX/RX power adapter, not access qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml');
root=tempname(fullfile(pwd,'logs')); mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
out=sixgr.link.runCellSearch_MIB_SIB1(cfg,'UseRuntimeChannel',true, ...
    'RuntimeSlot',0,'SSBIndex',0,'NumSubframes',5);
assert(~out.Crash && out.PBCH.Ok && isfinite(out.SS_RSRP_dB_re_UnitOccupiedRE_Es), ...
    'test:MissingActualNormalizedSSB','A decoded measured SSB is required: %s',out.FailureReason);
assert(isfinite(out.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es) && ...
    out.SSPhysicalMeasurementStatus=="available_normalized_fixed_esn0_not_absolute_dbm" && ...
    isnan(out.ReferenceSignalTxEPRE_dBm) && isnan(out.SS_RSRP_dBm));
assert(out.SSPowerReferenceOffset_dB==20*log10(out.SSMeasurementFFTSize) && ...
    out.ReferenceSignalTxPowerReferenceOffset_dB==20*log10(out.ReferenceSignalTxMeasurementFFTSize));
tx=str2double(split(erase(out.ReferenceSignalTxEPREPerAntenna_dB_re_UnitOccupiedRE_Es,["[","]"]),','));
assert(abs(out.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es-10*log10(sum(10.^(tx/10))))<1e-8);
assert(abs(out.MeasuredReferenceSignalChannelGain_dB-(out.SS_RSRP_dB_re_UnitOccupiedRE_Es- ...
    out.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es))<1e-9);
fields=sixgr.link.ssbPowerReferenceEvidence(out);
for name=string(fieldnames(fields)).'
    assert(isequaln(out.PBCH.(name),fields.(name)) && isequaln(out.SIB1.(name),fields.(name)), ...
        'Full-burst result views must retain the same actual power-reference evidence.');
end
row=struct2table(fields,'AsArray',true);
file=fullfile(root,'normalized_ssb_broadcast_power.csv');
sixgr.util.csvWriteTable(file,row,'PreserveSchema',true);
read=sixgr.util.csvReadTable(file,'TextType','string');
assert(abs(read.SS_RSRP_dB_re_UnitOccupiedRE_Es-row.SS_RSRP_dB_re_UnitOccupiedRE_Es)<1e-10);
fprintf('NORMALIZED_SSB_BROADCAST_POWER_PASS rx=%g tx=%g gain=%g csv=%s\n', ...
    out.SS_RSRP_dB_re_UnitOccupiedRE_Es,out.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es, ...
    out.MeasuredReferenceSignalChannelGain_dB,file);
ok=true;
end
