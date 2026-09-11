function common=decodedSSBPowerCodecFixture(cfg,power,cellId,availableSlot)
% Explicit codec fixture, NOT an on-air SIB1 or measured SSB result.
% Use the real UPER encoder/decoder and UE installation path.
bc=sixgr.config.defaultConfig(); bc.frequency.band_name='n77';
bc.phy.carrier.NSizeGrid=25; bc.phy.carrier.SubcarrierSpacing=15;
bc.phy.prach.configurationIndex=157; bc.phy.prach.preambleFormat='B4';
bc.phy.prach.subcarrierSpacing_kHz=30;
bc.rrc.sib1.ss_pbch_block_power_dbm=power;
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(bc);
received=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),received);
common=installed.UECommonCellConfiguration;
common.ServingCell=cellId; common.AvailableSlot=availableSlot;
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
end
