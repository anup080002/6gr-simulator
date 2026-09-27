function tests = test2GHz5MHzTDDConfiguration
tests = functiontests(localfunctions);
end

function testSinglePointUsesOnlyTDDTwoGHzAuthorities(testCase)
root = localRoot();
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml"));
s = scenario.toStruct();

verifyEqual(testCase, upper(string(s.frequency.duplex_mode)), "TDD");
verifyEqual(testCase, upper(string(s.global_radio_scope.duplex_mode)), "TDD");
verifyEqual(testCase, upper(string(s.random_access.duplex_mode)), "TDD");
verifyEqual(testCase, upper(string(s.bwp.component_carriers(1).duplex_mode)), "TDD");
verifyEqual(testCase, string(s.frequency.band_name), "n39_1900mhz_5mhz_tdd");
verifyEqual(testCase, double(s.frequency.center_frequency_hz), 1.9e9);
verifyEqual(testCase, double(s.global_radio_scope.carrier_frequency_hz), 1.9e9);
verifyEqual(testCase, double(s.random_access.carrier_frequency_hz), 1.9e9);
verifyEqual(testCase, double(s.bwp.component_carriers(1).center_frequency_hz), 1.9e9);
verifyEqual(testCase, double(s.frequency.bandwidth_hz), 5e6);
verifyEqual(testCase, double(s.frequency.n_size_grid), 25);
verifyEqual(testCase, double(s.simulation.snr_db), 0);

cfg = sixgr.lls6g.buildInternalConfig(scenario,tempname);
engine = sixgr.phy.FrameStructureEngine(cfg,"FrameCoreOnly",true);
verifyEqual(testCase, engine.DuplexMode, "TDD");
verifyEqual(testCase, engine.NRB, 25);
verifyEqual(testCase, engine.SCSkHz, 15);
verifyEqual(testCase, engine.FFTSize, 512);
verifyEqual(testCase, engine.SampleRate_Hz, 7.68e6);
verifyEqual(testCase, arrayfun(@(slot)engine.TDDToken(slot),0:4), ...
    ['D','D','D','F','U']);
verifyEqual(testCase, double(cfg.phy.nTxAnt), 4);
verifyEqual(testCase, double(cfg.phy.nRxAnt), 2);
verifyEqual(testCase, double(cfg.phy.pdsch.rank), 1);
verifyEqual(testCase, double(cfg.phy.pusch.rank), 1);
verifyEqual(testCase, double(cfg.phy.pdsch.maxLayers), 2);
verifyEqual(testCase, double(cfg.phy.pusch.maxLayers), 2);
verifyEqual(testCase, string(cfg.phy.linkAdaptation.rankPolicy), "measured_ri");
end

function testSweepPointsRemainIndependentTDDChildren(testCase)
root = localRoot();
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml"));
s = scenario.toStruct();
verifyEqual(testCase, string(s.scenario.runner_profile), "generic_sweep");
verifyEqual(testCase, string(s.scenario.sweep.base_profile), "waveform_bundle");
verifyEqual(testCase, string(s.scenario.sweep.execution_error_policy), ...
    "retain_failure_and_continue");
verifyEqual(testCase, upper(string(s.frequency.duplex_mode)), "TDD");
verifyEqual(testCase, string(s.frequency.band_name), "n39_1900mhz_5mhz_tdd");
verifyEqual(testCase, double(s.frequency.center_frequency_hz), 1.9e9);

points = s.scenario.sweep.overrides;
verifyEqual(testCase, numel(points), 8);
actual = arrayfun(@(point)double(point.config.simulation.snr_db),points);
verifyEqual(testCase, actual(:).', [40 30 20 10 0 -10 -20 -30]);
verifyFalse(testCase, logical(s.canonical_control.launch.sweep_enabled));
verifyFalse(testCase, logical(s.sweeps_and_matrix.snr_sweep.enabled));
end

function testSIB1DerivesTDDPRACHFromN39(testCase)
root = localRoot();
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scenario,tempname);
txTree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits, encoded] = sixgr.rrc.asn1.encodeSIB1UPER(txTree);
[rxTree, decoded] = sixgr.rrc.asn1.decodeSIB1UPER(bits);
[equal, detail] = sixgr.rrc.asn1.compareSIB1Trees(txTree,rxTree);

txSIB1 = txTree.message.c1.systemInformationBlockType1;
rxSIB1 = rxTree.message.c1.systemInformationBlockType1;
verifyEqual(testCase, double(txSIB1.servingCellConfigCommon. ...
    downlinkConfigCommon.frequencyInfoDL.frequencyBandList.freqBandIndicatorNR),39);
verifyEqual(testCase, string(txSIB1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.preambleFormat),"B4");
verifyEqual(testCase, string(rxSIB1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.preambleFormat),"B4");
verifyTrue(testCase,equal,sprintf('SIB1 tree hash mismatch: %s != %s', ...
    detail.TxTreeHash,detail.RxTreeHash));
verifyEqual(testCase,string(encoded.PayloadHash),string(decoded.PayloadHash));
end

function root = localRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
