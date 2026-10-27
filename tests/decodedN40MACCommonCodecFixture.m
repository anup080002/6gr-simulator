function [cfg,common,receipt]=decodedN40MACCommonCodecFixture(cfg,cellId,availableSlot)
% Declared component boundary: real original n40 codec/install, no RF access claim.
assert(cfg.phy.carrier.NSizeGrid==51&&cfg.phy.carrier.SubcarrierSpacing==30&&cfg.phy.ssb.scs_kHz==30, ...
    'test:N40CommonGeometry','This fixture requires the actual selected 20MHz/30kHz carrier.');
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits,tx]=sixgr.rrc.asn1.encodeSIB1UPER(tree);
[decoded,rx]=sixgr.rrc.asn1.decodeSIB1UPER(bits);
[equal,comparison]=sixgr.rrc.asn1.compareSIB1Trees(tree,decoded);
assert(equal&&tx.PayloadHash==rx.PayloadHash);
evidence=struct('SIB1RxTree',decoded,'SIB1PayloadHashRx',rx.PayloadHash,'SIB1RxTreeHash',comparison.RxTreeHash);
[cfg,installation]=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,evidence);
common=cfg.UECommonCellConfiguration;
assert(common.InitialULBWP.SizeRB==51&&common.InitialDLBWP.SizeRB==51&& ...
    common.InitialULBWP.SubcarrierSpacing_kHz==30&&common.InitialDLBWP.SubcarrierSpacing_kHz==30&& ...
    common.PayloadHash==rx.PayloadHash&&common.TreeHash==comparison.RxTreeHash);
common.ServingCell=cellId;common.AvailableSlot=availableSlot;
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
cfg.UECommonCellConfiguration=common;cfg.ue_common_cell_configuration=common;
receipt=struct('Scope',"declared_component_common_codec_not_received_RF_access", ...
    'PayloadHash',rx.PayloadHash,'TreeHash',comparison.RxTreeHash,'EncodedBits',bits, ...
    'OriginalTree',tree,'DecodedTree',decoded,'Installation',installation, ...
    'DecoderRecovery',evidence);
end
