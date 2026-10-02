function ok=testSLSNativePUSCHUCITransmission()
% Actual PUSCH TX invocation; allocation/TX evidence, not RF qualification.
cfg=sixgr.config.defaultConfig(); cfg.run.useMex=false;
cfg.phy.pusch.mcsTable='qam64_table1'; cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.numLayers=1; cfg.phy.pusch.nLayers=1;
c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',30);
p=nrPUSCHConfig('PRBSet',0:11,'NumLayers',1,'Modulation','QPSK');
payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0;1]), ...
    'CSIPart1',int8(mod((1:10)',2)));
[tx,info]=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',c,'PUSCH',p, ...
    'TargetCodeRate',.3,'NumTxAnt',1,'UCIPayload',payload,'ExecutionProfile','phy_calibration');
plan=tx.NativeUCIResourcePlan;
assert(tx.UCIOnPUSCHApplied && ~isempty(tx.Waveform) && all(isfinite(tx.Waveform),'all'));
assert(isequal(plan.LengthsHARQCSI1CSI2,[3 10 0]) && plan.AllocatedRECount>0);
assert(isequal(plan,info.UCIOnPUSCH.NativeResourcePlan));
assert(plan.GULSCH==info.UCIOnPUSCH.GULSCH);
fprintf('SLS_NATIVE_PUSCH_UCI_TX_PASS actual_transmitter=1 receiver_qualified=0\n'); ok=true;
end
