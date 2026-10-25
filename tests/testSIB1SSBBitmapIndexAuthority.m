function ok = testSIB1SSBBitmapIndexAuthority()
% Actual SIB1 UPER round trips; no waveform/acquisition/PRACH claim.
% TS 38.331 V18.8.0 ServingCellConfigCommonSIB/inOneGroup assigns the
% leftmost bit to SSB index0. With Lmax4, the rightmost four bits are ignored.
% The installed production codec retains its own actual ASN.1 version label.
setup6GRSimToolkit('Verbose',false);
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
cfg.phy.fc_Hz = 700e6;

% Exhaust every nonempty short bitmap. Assert semantic identity BEFORE
% round-trip equality: a consistently wrong encoder/decoder is not enough.
for value = 1:15
    authored = string(dec2bin(value,4));
    expected = authored + "0000";
    candidate = cfg;
    candidate.initial_access.ssb.positions_in_burst = authored;
    tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(candidate);
    assert(localBitmap(tree)==expected, ...
        'Short bitmap must retain its left-to-right SSB indices.');
    assert(isequal(find(char(localBitmap(tree))=='1')-1, ...
        find(char(authored)=='1')-1), ...
        'Canonicalization must not shift transmitted SSB indices by four.');
    [bits,txMeta] = sixgr.rrc.asn1.encodeSIB1UPER(tree);
    [received,rxMeta] = sixgr.rrc.asn1.decodeSIB1UPER(bits);
    assert(localBitmap(received)==expected);
    assert(isequal(find(char(localBitmap(received))=='1')-1, ...
        find(char(authored)=='1')-1));
    assert(string(txMeta.PayloadHash)==string(rxMeta.PayloadHash));
    [equal,~] = sixgr.rrc.asn1.compareSIB1Trees(tree,received);
    assert(logical(equal),'Actual decoded SIB1 must preserve the complete tree.');

    % Explicit equivalent eight-bit input must produce the same actual
    % payload, not just an equal bitmap in a reconstructed tree.
    candidate.initial_access.ssb.positions_in_burst = expected;
    canonical = sixgr.rrc.asn1.buildBCCHDLSCHMessage(candidate);
    canonicalBits = sixgr.rrc.asn1.encodeSIB1UPER(canonical);
    assert(isequal(bits,canonicalBits));
end

% Existing medium bitmaps, including selected n40's four emitted SSBs,
% remain byte-for-byte semantic inputs (including leading zero bits).
for authored = ["10000000","00000001","01010101","11110000","11111111"]
    candidate = cfg;
    candidate.initial_access.ssb.positions_in_burst = authored;
    tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(candidate);
    assert(localBitmap(tree)==authored);
    bits = sixgr.rrc.asn1.encodeSIB1UPER(tree);
    received = sixgr.rrc.asn1.decodeSIB1UPER(bits);
    assert(localBitmap(received)==authored);
    assert(isequal(sixgr.rrc.asn1.encodeSIB1UPER(received),bits));
end
ok = true;
fprintf('PASS testSIB1SSBBitmapIndexAuthority: 15 short and 5 medium actual UPER round trips; no PHY claim.\n');
end

function value = localBitmap(tree)
value = string(tree.message.c1.systemInformationBlockType1. ...
    servingCellConfigCommon.ssb_PositionsInBurst.inOneGroup);
end
