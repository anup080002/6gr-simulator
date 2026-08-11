function ok = testRAN1LLSNTN()
%TESTRAN1LLSNTN Dedicated NR NTN waveform/configuration integration gate.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
[cfg,provenance] = sixgr.lls.loadConfig( ...
    "configs/lls/pdsch_ntn_leo_tdl_d_example.yaml");
assert(cfg.ntn.enabled && string(cfg.channel.model) == "NTN-TDL-D");
assert(string(cfg.ntn.standardReference) == "3GPP TR 38.811");
assert(strlength(provenance.ConfigSHA256) == 64);
[ulCfg,~] = sixgr.lls.loadConfig( ...
    "configs/lls/pusch_ntn_leo_tdl_d_example.yaml");
assert(ulCfg.ntn.enabled && string(ulCfg.simulation.link) == "PUSCH" && ...
    string(ulCfg.channel.model) == "NTN-TDL-D");

carrier = nrCarrierConfig("SubcarrierSpacing", ...
    double(cfg.carrier.subcarrierSpacingKHz), ...
    "NSizeGrid",double(cfg.carrier.nSizeGrid));
ofdm = nrOFDMInfo(carrier);
state = sixgr.lls.resolveNTNState(cfg,double(ofdm.SampleRate));
expectedRange = slantRangeCircularOrbit( ...
    cfg.ntn.orbit.elevationAngleDeg,cfg.ntn.orbit.satelliteAltitudeM, ...
    cfg.ntn.orbit.groundAltitudeM);
expectedDoppler = dopplerShiftCircularOrbit( ...
    cfg.ntn.orbit.elevationAngleDeg,cfg.ntn.orbit.satelliteAltitudeM, ...
    cfg.ntn.orbit.groundAltitudeM,cfg.carrier.frequencyHz);
localAssertNear(state.SlantRangeM,expectedRange);
localAssertNear(state.PhysicalSatelliteDopplerHz,expectedDoppler);
assert(state.PropagationDelaySeconds > 0 && state.PropagationDelaySamples > 0);
assert(state.DopplerCompensationHz == state.PhysicalSatelliteDopplerHz);
assert(abs(state.ResidualSatelliteDopplerHz) < 1e-12);

bad = cfg;
bad.channel.model = "AWGN";
localAssertError(@() sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:NTNEnableProfileMismatch");
bad = cfg;
bad.ntn.atmosphericLoss.enabled = true;
localAssertError(@() sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:NTNAtmosphericLossRequiresPowerBudgetMode");
bad = cfg;
bad.interference.enabled = true;
bad.simulation.studyType = "interference_bler";
localAssertError(@() sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:NTNInterferenceConfigurationRequired");

tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
result = sixgr.lls.runLLS( ...
    "configs/lls/pdsch_ntn_leo_tdl_d_example.yaml", ...
    "OutputRoot",tmp,"RunTag","ntn_waveform_gate","GeneratePlots",true);
assert(result.Status == "complete_valid" && all(result.ValidityTable.Pass));
assert(height(result.TrialTable) == 1 && ~result.TrialTable.CRCError);
assert(result.TruthContractTable.ActualNTNChannel && ...
    result.TruthContractTable.NTNEvidenceValid);
trial = result.TrialTable(1,:);
assert(trial.ChannelModel == "NTN-TDL-D" && trial.NTNEnabled);
assert(contains(trial.ChannelRealizationSource,"nrTDLChannel_NTN_profile"));
localAssertNear(trial.NTNSlantRangeM,state.SlantRangeM);
localAssertNear(trial.NTNPhysicalSatelliteDopplerHz, ...
    state.PhysicalSatelliteDopplerHz);
localAssertNear(trial.NTNResidualSatelliteDopplerHz,0);
assert(trial.NTNPropagationDelaySamples == state.PropagationDelaySamples);
assert(trial.NTNPropagationDelayCompensationMode == ...
    "perfect_geometry_timing_advance");
assert(trial.NTNDopplerCompensationMode == "ideal_transmitter_geometry");
assert(trial.PTRSRE > 0,"Enabled PT-RS must occupy executed resource elements.");

expected = ["ntn_channel_state.csv","ntn_geometry_and_doppler.png", ...
    "bler_vs_snr.png","throughput_vs_snr.png","pdsch_resource_grid.png"];
for index = 1:numel(expected)
    path = fullfile(result.RunFolder,expected(index));
    assert(exist(path,"file") == 2,"Missing NTN artifact: %s",expected(index));
end
imageInfo = imfinfo(fullfile(result.RunFolder,"ntn_geometry_and_doppler.png"));
assert(imageInfo.Width >= 1000 && imageInfo.Height >= 500);
assert(string(imageInfo.Format) == "png");
listing = dir(fullfile(result.RunFolder,"*"));
assert(~any(endsWith(string({listing.name}),".svg","IgnoreCase",true)));
manifestNames = string(result.ArtifactManifest.RelativePath);
assert(all(ismember(expected,manifestNames)));

ulResult = sixgr.lls.runLLS( ...
    "configs/lls/pusch_ntn_leo_tdl_d_example.yaml", ...
    "OutputRoot",tmp,"RunTag","ntn_uplink_waveform_gate", ...
    "GeneratePlots",false);
assert(ulResult.Status == "complete_valid" && all(ulResult.ValidityTable.Pass));
assert(height(ulResult.TrialTable) == 1 && ~ulResult.TrialTable.CRCError);
assert(ulResult.TrialTable.ChannelTransmissionDirection == "Uplink");
assert(ulResult.TrialTable.LLRSource == "nrPUSCHDecode_soft_llr");
assert(ulResult.TrialTable.NTNEnabled && ...
    ulResult.TruthContractTable.NTNEvidenceValid);
assert(ulResult.TrialTable.PTRSRE > 0, ...
    "Enabled uplink PT-RS must occupy executed resource elements.");

fprintf("RAN1LLSNTN: actual PDSCH and PUSCH passed through NTN-TDL-D; " + ...
    "range %.3f km, physical Doppler %.3f Hz, residual %.3f Hz.\n", ...
    trial.NTNSlantRangeM/1e3,trial.NTNPhysicalSatelliteDopplerHz, ...
    trial.NTNResidualSatelliteDopplerHz);
ok = true;
end

function localAssertNear(actual,expected)
tolerance = 128*eps(max(abs(double(expected)),1));
assert(abs(double(actual)-double(expected)) <= tolerance, ...
    "Actual %.17g differs from expected %.17g.",actual,expected);
end

function localAssertError(fcn,identifier)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier,identifier), ...
        "Expected %s, received %s: %s",identifier,ME.identifier,ME.message);
    return;
end
error("testRAN1LLSNTN:MissingError","Expected typed error %s.",identifier);
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
