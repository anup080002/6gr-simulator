function ok = testMIBPDCCHConfigSIB1Derivation()
%TESTMIBPDCCHCONFIGSIB1DERIVATION MIB-derived Type0 CSS wiring checks.

setup6GRSimToolkit("Verbose", false);

bits = int8(zeros(24, 1));
bits(14:21) = int8([0 0 1 0 1 0 1 0]); % 0x2A
mib = sixgr.phy.broadcast.decodeMIBTransportBlock(bits);
assert(double(mib.PDCCHConfigSIB1) == 42, "pdcch-ConfigSIB1 bit decode failed.");
assert(double(mib.CORESET0Index) == 2 && double(mib.SearchSpaceZero) == 10, ...
    "pdcch-ConfigSIB1 split into CORESET0/SearchSpace0 is wrong.");

if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end

cfgTx = localCfg();
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfgTx, "SNRdB", 35, "Seed", 1517);

% Deliberately poison the receiver-side YAML/control config. A compliant
% receiver must still recover and use the PBCH/MIB pdcch-ConfigSIB1 value.
cfgRx = cfgTx;
cfgRx.phy.sib1.coreset0Index = 15;
cfgRx.phy.sib1.searchSpaceZero = 15;
cfgRx.phy.mib.pdcchConfigSIB1 = 255;
cfgRx.phy.mib.dmrsTypeAPosition = 3;
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfgRx);

assert(logical(rx.StrictOk), "SIB1 recovery must pass using decoded MIB despite poisoned receiver config.");
[treeEqual, ~] = sixgr.rrc.asn1.compareSIB1Trees(tx.TxTree, rx.SIB1RxTree);
assert(logical(treeEqual), "Test-side transmitted/decoded SIB1 trees must match.");
assert(double(rx.PDCCHConfigSIB1) == 0 && double(rx.MIBPDCCHConfigSIB1Recovered) == 0, ...
    "Receiver used YAML/config pdcch-ConfigSIB1 instead of decoded PBCH/MIB value.");
assert(double(rx.MIBCORESET0Index) == 0 && double(rx.MIBSearchSpaceZero) == 0, ...
    "Receiver CORESET0/SearchSpace0 indices must come from decoded MIB.");
assert(string(rx.PDCCHConfigSIB1Source) == "decoded_mib_bch_transport_block", ...
    "Receiver must report decoded-MIB derivation source for Phase 3 control resources.");
ok = true;
end

function cfg = localCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",2);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0);
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
cfg.phy.mib.pdcchConfigSIB1 = 0;
cfg.phy.mib.dmrsTypeAPosition = 2;
end
