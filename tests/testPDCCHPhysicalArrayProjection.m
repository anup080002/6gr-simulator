function ok = testPDCCHPhysicalArrayProjection()
%TESTPDCCHPHYSICALARRAYPROJECTION Exercise a one-port PDCCH on a 2x2 link.
%
% A PDCCH is a one-port common/control transmission, but that logical port
% still has to traverse the configured physical gNB array.  This regression
% proves that the exact waveform is projected through a unit-norm
% port-to-element matrix instead of either failing a dimension check or
% padding a silent antenna column.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.useMex = false;
cfg.phy.bsArray = [1 2 1];
cfg.phy.ueArray = [1 2 1];
cfg.phy.nTxAnt = 2;
cfg.phy.nRxAnt = 2;
cfg.channel.nTxAnt = 2;
cfg.channel.nRxAnt = 2;
cfg.channel.model = "TDL";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.awgnOnly = false;
cfg.channel.doppler_Hz = 30;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.pdcch.enable = true;
cfg.phy.pdcch.dmrs.enable = true;
cfg.powerAndRF.downlinkPowerNormalizationPolicy = ...
    "fixed_epre_over_configured_bwp";
cfg = sixgr.config.normalizeConfig(cfg);

bs = sixgr.rf.AntennaArrayFactory.build(cfg, "bs", ...
    "usePhased", false, "signal", "PDCCH", "numPorts", 2);
ue = sixgr.rf.AntennaArrayFactory.build(cfg, "ue", ...
    "usePhased", false, "signal", "PDCCH", "numPorts", 2);
assert(double(bs.NumElements) == 2 && double(ue.NumElements) == 2, ...
    "The focused fixture must create two physical elements at both ends.");
assert(~logical(bs.HybridBeamformingEnabled), ...
    "The fixture must remain fully digital; this regression is not a hybrid shortcut.");

cfg.lls6g.userContext.RuntimeServingBSAntenna = bs;
cfg.lls6g.userContext.RuntimeServingBSAntennaMeta = bs;
cfg.lls6g.userContext.RuntimeUEAntenna = ue;
cfg.lls6g.userContext.RuntimeUEAntennaMeta = ue;
cfg.lls6g.userContext.RuntimeSignalFamily = "PDCCH";
cfg.lls6g.userContext.RuntimeCurrentDirection = "DL";
cfg.lls6g.userContext.UEIndex = 1;
cfg.lls6g.userContext.RuntimeServingCellIndex = 1;

dciBits = int8(mod((0:31).', 2));
[tx, txInfo] = sixgr.phy.dl.PDCCH_Tx(cfg, ...
    "DCIBits", dciBits, "K", numel(dciBits));
assert(size(tx.Waveform, 2) == 1, ...
    "PDCCH transmitter must retain its one logical control port.");
assert(isequal(size(txInfo.PortGrid),size(tx.Grid)) && ...
    strcmp(string(txInfo.PowerNormalizationGridSource), ...
    "exact_pdcch_tx_port_grid") && isstruct(txInfo.OFDM), ...
    "PDCCH must publish its exact port grid and OFDM metadata to downstream RF stages.");
[~,pdcchPower] = sixgr.rf.applyPowerContext( ...
    tx.Waveform,cfg,"DL",txInfo);
assert(strcmp(string(pdcchPower.PowerNormalizationPolicy), ...
    "fixed_epre_over_configured_bwp") && ...
    strcmp(string(pdcchPower.NormalizationGridSource), ...
    "exact_pdcch_tx_port_grid") && ...
    isfinite(double(pdcchPower.NormalizationGridMeanEnergyPerRE)), ...
    "PDCCH fixed-EPRE scaling must use the exact generated control grid.");

state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
runtime = state.RuntimeChannelState;
assert(logical(runtime.ElementExpansionApplied), ...
    "The one-port PDCCH must be explicitly projected onto the physical array.");
assert(double(runtime.ExternalLogicalTxPorts) == 1 && ...
    double(runtime.PhysicalChannelTxElements) == 2, ...
    "Runtime state must separate the one logical PDCCH port from two physical gNB elements.");
W = runtime.PortToElementMatrix;
assert(isequal(size(W), [2 1]) && norm(W' * W - 1, "fro") < 1e-12, ...
    "PDCCH port-to-element projection must be 2x1 and power preserving.");

[rxWave, replay] = sixgr.link.applyRuntimeFadingChannel(tx.Waveform, state);
assert(size(rxWave, 2) == 2 && all(isfinite(real(rxWave(:)))) && ...
    all(isfinite(imag(rxWave(:)))), ...
    "The projected PDCCH must produce two finite UE receive branches.");
assert(logical(replay.RuntimeChannelElementExpansionApplied) && ...
    double(replay.RuntimeChannelActiveTxPorts) == 1 && ...
    double(replay.RuntimeChannelPhysicalTxElements) == 2 && ...
    ~logical(replay.RuntimeChannelInputPaddedToMaterializedPorts), ...
    "Replay must disclose true element expansion and no silent-column padding.");

ok = true;
end
