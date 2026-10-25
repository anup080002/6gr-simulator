function common=decodedSSBPowerCodecFixture(cfg,power,cellId,availableSlot)
% Explicit codec fixture, NOT an on-air SIB1 or measured SSB result.
% Use the real UPER encoder/decoder and UE installation path.
bc=sixgr.config.defaultConfig(); bc.frequency.band_name='n77';
bc.phy.carrier.NSizeGrid=25; bc.phy.carrier.SubcarrierSpacing=15;
% This helper deliberately returns the same fixed 25-RB/15-kHz codec
% boundary for every caller; it does not claim the caller's cell waveform.
% Keep its broadcast reference SCS consistent with those actual codec BWPs,
% rather than inheriting the default configuration's 30-kHz TDD pattern.
bc.phy.duplex.tddCommon=struct('ReferenceSubcarrierSpacingKHz',15, ...
    'Pattern1',struct('PeriodicityMilliseconds',5,'NumDownlinkSlots',2, ...
    'NumDownlinkSymbols',3,'NumUplinkSlots',1,'NumUplinkSymbols',2));
bc.phy.prach.configurationIndex=157; bc.phy.prach.preambleFormat='B4';
bc.phy.prach.subcarrierSpacing_kHz=30;
bc.rrc.sib1.ss_pbch_block_power_dbm=power;
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(bc);
received=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
assert(sixgr.rrc.asn1.compareSIB1Trees(tree,received), ...
    'test:SSBPowerCodecFixture','Preserve the complete original codec tree.');
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),received);
common=installed.UECommonCellConfiguration;
assert(common.InitialULBWP.SubcarrierSpacing_kHz==15 && ...
    common.InitialDLBWP.SubcarrierSpacing_kHz==15 && common.TDDConfigCommonPresent && ...
    string(common.TDDConfigCommon.referenceSubcarrierSpacing)=="kHz15", ...
    'test:SSBPowerCodecFixture','The declared fixture must retain consistent received BWP/TDD clocks.');
common.ServingCell=cellId; common.AvailableSlot=availableSlot;
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
end
