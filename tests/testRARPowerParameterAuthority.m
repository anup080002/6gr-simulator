function ok=testRARPowerParameterAuthority()
% Independent clause arithmetic, not a waveform/performance qualification.
cfg=struct('random_access',struct('preamble_received_target_power_dbm',-96));
cfg.phy.pusch.powerControl=struct('p0PUSCH_dBm',-80,'alpha',.8);
p=sixgr.mac.ra.resolveMsg3PowerParameters(cfg);
assert(p.P0Nominal_dBm==-96 && p.Alpha==1 && p.P0UE_dB==0);
cfg.random_access.pusch_common_msg3_delta_preamble=10;
cfg.UECommonCellConfiguration.PUSCHConfigCommon=struct();
p=sixgr.mac.ra.resolveMsg3PowerParameters(cfg);
assert(p.P0Nominal_dBm==-96,'Received absence must override stale configured offset.');
for raw=[-1 6]
    cfg.UECommonCellConfiguration.PUSCHConfigCommon.msg3_DeltaPreamble=raw;
    p=sixgr.mac.ra.resolveMsg3PowerParameters(cfg);
    assert(p.P0Nominal_dBm==-96+2*raw);
end
cfg.random_access.msg3_alpha=.7;
p=sixgr.mac.ra.resolveMsg3PowerParameters(cfg); assert(p.Alpha==.7);
bad=cfg; bad.UECommonCellConfiguration.PUSCHConfigCommon.msg3_DeltaPreamble=NaN;
mustFail(@()sixgr.mac.ra.resolveMsg3PowerParameters(bad));
bad=cfg; bad.random_access.msg3_alpha=.3;
mustFail(@()sixgr.mac.ra.resolveMsg3PowerParameters(bad));
bad=rmfield(cfg,'UECommonCellConfiguration');
bad.random_access.binding_source='decoded_sib1_rach_config_common';
mustFail(@()sixgr.mac.ra.resolveMsg3PowerParameters(bad));
bad=cfg; bad.UECommonCellConfiguration.PUSCHConfigCommon=[];
mustFail(@()sixgr.mac.ra.resolveMsg3PowerParameters(bad));
bad=rmfield(cfg,'UECommonCellConfiguration'); bad.random_access.pusch_common_msg3_delta_preamble=3;
mustFail(@()sixgr.mac.ra.resolveMsg3PowerParameters(bad));
pc=struct('Pcmax_dBm',23,'Msg3P0PUSCH_dBm',-96,'Msg3Alpha',1, ...
    'Msg3DeltaTF_dB',0,'Msg3Numerology',0,'PreamblePowerRampingCounter',1, ...
    'PreamblePowerRampingStep_dB',2,'Msg3Pathloss_dB',90);
grant=struct('NumPRB',4,'TPCCommand',3);
a=sixgr.mac.ra.applyRARGrantPowerCommand(pc,grant);
pc.Msg3Numerology=1; b=sixgr.mac.ra.applyRARGrantPowerCommand(pc,grant);
assert(abs(b.Msg3RequestedTxPower_dBm-a.Msg3RequestedTxPower_dBm-10*log10(2))<1e-12);
% Independent clamp examples. Include negative RAR TPC inside the clamp.
for example=[15 2 6 8;25 -6 4 -2].'
    pc.Msg3P0PUSCH_dBm=example(1); pc.Msg3Pathloss_dB=0; pc.Msg3Numerology=0;
    pc.PreamblePowerRampingCounter=6;
    grant.NumPRB=1; grant.TPCCommand=(example(2)+6)/2;
    out=sixgr.mac.ra.applyRARGrantPowerCommand(pc,grant);
    assert(out.Msg3AppliedRamping_dB==example(3));
    assert(out.Msg3ClosedLoopCorrection_dB==example(4));
    assert(out.Msg3TxPower_dBm==23);
    laterGrant=grant; laterGrant.NumPRB=2;
    later=sixgr.mac.ra.resolveRARPUSCHPower(out,laterGrant,false);
    assert(later.Msg3ClosedLoopCorrection_dB==out.Msg3ClosedLoopCorrection_dB);
    assert(abs(later.Msg3RequestedTxPower_dBm-out.Msg3RequestedTxPower_dBm-10*log10(2))<1e-12);
end
pc.Msg3Pathloss_dB=NaN;
out=sixgr.mac.ra.applyRARGrantPowerCommand(pc,grant);
assert(isnan(out.Msg3TxPower_dBm) && isnan(out.Msg3AppliedRamping_dB));
grant.NumPRB=1.5; mustFail(@()sixgr.mac.ra.applyRARGrantPowerCommand(pc,grant));
ok=true;
fprintf('RAR_POWER_AUTHORITY_PASS: independent parameter/unit/ramp/allocation arithmetic; no physical trial.\n');
end
function mustFail(f)
failed=false; try, f(); catch, failed=true; end
assert(failed,'Malformed power parameters must be rejected.');
end
