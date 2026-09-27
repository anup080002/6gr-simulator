function tests = test4GHzOnlyCampaignConfiguration
tests = functiontests(localfunctions);
end

function testMasterAndEverySweepChildAreExactly4GHzTDD(testCase)
root = localRoot();
path = fullfile(root,"simulator","configs","campaigns", ...
    "ran1_126bis_4ghz_only.yaml");
matrixCfg = sixgr.lls6g.config.readConfigFile(path);
sixgr.lls6g.config.validateScenarioConfig(matrixCfg,"Kind","matrix", ...
    "AllowPartial",false,"Context",path);
bindingT = sixgr.lls6g.config.validateMatrixCampaignConstraints(matrixCfg,string(path));
verifyNotEmpty(testCase,bindingT);
fcRows = bindingT.Units == "Hz";
verifyTrue(testCase,any(fcRows));
verifyEqual(testCase,unique(bindingT.ResolvedValue(fcRows)),"4000000000");
verifyEqual(testCase,numel(unique(bindingT.CaseID)),8);
end

function testWrongInheritedCarrierFailsBeforeLaunch(testCase)
root = localRoot();
path = fullfile(root,"simulator","configs","campaigns", ...
    "ran1_126bis_4ghz_only.yaml");
matrixCfg = sixgr.lls6g.config.readConfigFile(path);
matrixCfg.execution.required_center_frequency_hz = 3.9e9;
verifyError(testCase,@()sixgr.lls6g.config.validateMatrixCampaignConstraints( ...
    matrixCfg,string(path)),"sixgr:lls6g:config:CampaignCarrierMismatch");
end

function testC420GridAndSweepIdentity(testCase)
root = localRoot();
path = fullfile(root,"simulator","configs","scenarios", ...
    "lls_4ghz_20mhz_4tx2rx_awgn_snr_sweep.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(path);
s = scfg.toStruct();
verifyEqual(testCase,double(s.frequency.center_frequency_hz),4e9);
verifyEqual(testCase,double(s.frequency.bandwidth_hz),20e6);
verifyEqual(testCase,double(s.frequency.n_size_grid),51);
verifyEqual(testCase,double(s.frame.scs_khz),30);
verifyEqual(testCase,double(s.waveform.fft_size),1024);
verifyEqual(testCase,double(s.waveform.sample_rate_hz),30.72e6);
verifyEqual(testCase,double(s.bwp.dl.n_size_bwp),51);
verifyEqual(testCase,double(s.bwp.ul.n_size_bwp),51);
verifyEqual(testCase,double(s.mimo.n_tx_ant),4);
verifyEqual(testCase,double(s.mimo.n_rx_ant),2);
overrides = s.scenario.sweep.overrides;
values = arrayfun(@(x)double(x.config.simulation.snr_db),overrides).';
verifyEqual(testCase,values,[-30 -20 -10 0 10 20 30 40]);
verifyEqual(testCase,unique(arrayfun(@(x)double(x.config.simulation.random_seed),overrides)),1001);

reference = sixgr.lls6g.config.loadScenarioConfig(fullfile(root,"simulator", ...
    "configs","scenarios","lls_4ghz_20mhz_4tx2rx_awgn_reference.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(reference,tempname);
verifyEqual(testCase,double(cfg.frequency.centerFrequencyHz),4e9);
verifyEqual(testCase,double(cfg.phy.carrier.NSizeGrid),51);
verifyEqual(testCase,double(cfg.phy.carrier.SubcarrierSpacing),30);
verifyEqual(testCase,size(cfg.channel.awgnSpatialMatrixDL),[2 4]);
engine = sixgr.phy.FrameStructureEngine(cfg,"FrameCoreOnly",true);
verifyEqual(testCase,engine.SlotsPerFrame,20);
verifyEqual(testCase,engine.SlotDuration_ms,0.5);
end

function root = localRoot()
root = fileparts(fileparts(mfilename("fullpath")));
end
