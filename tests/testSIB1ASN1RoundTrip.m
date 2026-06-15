function ok = testSIB1ASN1RoundTrip()
%TESTSIB1ASN1ROUNDTRIP Anchor SIB1 ASN.1 profile must roundtrip exactly.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.NSizeGrid = 52;
tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits, encMeta] = sixgr.rrc.asn1.encodeSIB1UPER(tree);
[rxTree, decMeta] = sixgr.rrc.asn1.decodeSIB1UPER(bits);
[equal, cmp] = sixgr.rrc.asn1.compareSIB1Trees(tree, rxTree);
assert(logical(equal), "SIB1 ASN.1 anchor profile tree must roundtrip exactly.");
assert(string(encMeta.PayloadHash) == string(decMeta.PayloadHash), "SIB1 payload hash must roundtrip.");
assert(string(cmp.TxTreeHash) == string(cmp.RxTreeHash), "SIB1 tree hashes must match.");

bad = tree;
bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.restrictedSet = "restricted_type_A";
threw = false;
try
    sixgr.rrc.asn1.encodeSIB1UPER(bad);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:rrc:asn1:UnsupportedSIB1IE");
end
assert(threw, "Unsupported restricted-set PRACH IE must fail closed.");
ok = true;
end
