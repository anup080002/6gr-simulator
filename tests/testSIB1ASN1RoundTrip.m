function ok = testSIB1ASN1RoundTrip()
%TESTSIB1ASN1ROUNDTRIP Anchor SIB1 ASN.1 profile must roundtrip exactly.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
cfg.phy.fc_Hz = 700e6;
tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits, encMeta] = sixgr.rrc.asn1.encodeSIB1UPER(tree);
[rxTree, decMeta] = sixgr.rrc.asn1.decodeSIB1UPER(bits);
[equal, cmp] = sixgr.rrc.asn1.compareSIB1Trees(tree, rxTree);
assert(logical(equal), "SIB1 ASN.1 anchor profile tree must roundtrip exactly.");
assert(string(encMeta.PayloadHash) == string(decMeta.PayloadHash), "SIB1 payload hash must roundtrip.");
assert(string(cmp.TxTreeHash) == string(cmp.RxTreeHash), "SIB1 tree hashes must match.");

for restrictedSet = ["RestrictedSetTypeA", "RestrictedSetTypeB"]
    configured = tree;
    configured.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.restrictedSet = restrictedSet;
    configuredBits = sixgr.rrc.asn1.encodeSIB1UPER(configured);
    decoded = sixgr.rrc.asn1.decodeSIB1UPER(configuredBits);
    observed = string(decoded.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.restrictedSet);
    assert(observed == restrictedSet, ...
        "Supported restricted-set PRACH IE must roundtrip exactly.");
end

% Short-sequence PRACH formats are derived from configuration index and
% duplex table. Index 157 in FR1 TDD is B4, not the historical A1 default.
b4cfg = cfg;
b4cfg.frequency.band_name = "n77";
b4cfg.phy.fc_Hz = 4e9;
b4cfg.phy.carrier.NSizeGrid = 273;
b4cfg.phy.prach.configurationIndex = 157;
b4cfg.phy.prach.subcarrierSpacing_kHz = 30;
b4cfg.phy.prach.preambleFormat = "B4";
b4tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(b4cfg);
b4bits = sixgr.rrc.asn1.encodeSIB1UPER(b4tree);
b4decoded = sixgr.rrc.asn1.decodeSIB1UPER(b4bits);
[b4equal, ~] = sixgr.rrc.asn1.compareSIB1Trees(b4tree, b4decoded);
assert(logical(b4equal), ...
    "FR1 TDD PRACH configuration index 157/B4 must roundtrip semantically.");

bad = tree;
bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.restrictedSet = "RestrictedSetTypeC";
assertThrows(@() sixgr.rrc.asn1.encodeSIB1UPER(bad), ...
    "sixgr:rrc:asn1:UnsupportedSIB1IE");
ok = true;
end

function assertThrows(action, identifier)
observed = "";
try
    action();
catch ME
    observed = string(ME.identifier);
end
assert(observed == string(identifier), ...
    "Expected typed error %s, observed %s.", identifier, observed);
end
