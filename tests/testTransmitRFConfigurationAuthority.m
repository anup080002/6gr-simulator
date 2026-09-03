function ok = testTransmitRFConfigurationAuthority()
%TESTTRANSMITRFCONFIGURATIONAUTHORITY Shared desired/interferer TX authority.

setup6GRSimToolkit("Verbose", false);
cfg = struct();
assert(~sixgr.rf.hasExplicitTransmitConfig(cfg));

cfg.rf.tx.cfo_Hz = 125;
assert(sixgr.rf.hasExplicitTransmitConfig(cfg));
cfg.rf.tx.cfo_Hz = 0;
assert(~sixgr.rf.hasExplicitTransmitConfig(cfg));

cfg.rf.tx.phaseNoise.enabled = true;
assert(sixgr.rf.hasExplicitTransmitConfig(cfg));
cfg.rf.tx.phaseNoise.enabled = false;
assert(~sixgr.rf.hasExplicitTransmitConfig(cfg));

cfg.rf.tx.iqImbalance.enable = "enabled";
assert(sixgr.rf.hasExplicitTransmitConfig(cfg));
cfg.rf.tx.iqImbalance.enable = "off";
assert(~sixgr.rf.hasExplicitTransmitConfig(cfg));

ok = true;
end
