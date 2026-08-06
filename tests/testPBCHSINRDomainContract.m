function ok = testPBCHSINRDomainContract()
%TESTPBCHSINRDOMAINCONTRACT Calibrate PBCH SINR on occupied-RE AWGN.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;

[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
[cleanWaveform, ~, txInfo] = sixgr.phy.dl.SSB_Tx( ...
    cfg, "NumSubframes", 5, "SSBIndex", 0);
requested = [10, 20];
measured = NaN(size(requested));
for index = 1:numel(requested)
    [rxWaveform, noise] = sixgr.conformance.addReferenceNoise( ...
        cleanWaveform, carrier, requested(index), ...
        "Seed", 88000 + index, "SignalEnergyPerOccupiedRE", 1);
    [rxGrid, sync] = sixgr.phy.dl.SSB_Rx( ...
        rxWaveform, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz);
    [pbch, ~] = sixgr.phy.dl.PBCH_Recovery(rxGrid, sync, cfg);

    assert(logical(pbch.Ok), ...
        "PBCH must decode on the %g dB occupied-RE AWGN calibration point.", ...
        requested(index));
    assert(logical(pbch.PostEqSINRAvailable) && ...
        isfinite(double(pbch.PostEqSINR_dB)), ...
        "PBCH post-equalization SINR must be available and finite.");
    assert(string(pbch.PostEqSINRValueStatus) == "OK", ...
        "Finite-noise PBCH calibration must not be labeled as a noise-floor bound.");
    assert(~logical(pbch.PreEqualizationNoiseVarianceFloorApplied), ...
        "Finite-noise PBCH calibration unexpectedly used the numerical floor.");
    assert(string(pbch.PreEqualizationNoiseVarianceDomain) == ...
        "resource_grid_pre_equalization_per_receive_branch");
    assert(string(pbch.PostEqualizationNoiseVarianceDomain) == ...
        "unit_energy_pbch_symbol_post_equalization");
    sixgr.phy.rx.validatePBCHNoiseDomainEvidence(pbch);

    measured(index) = double(pbch.PostEqSINR_dB);
    assert(abs(measured(index) - requested(index)) <= 3.0, ...
        ["PBCH occupied-RE AWGN calibration missed: requested %.3f dB, " + ...
        "measured %.3f dB."], requested(index), measured(index));
    assert(~logical(noise.WaveformPowerUsed), ...
        "PBCH calibration must not derive AWGN from sparse whole-waveform power.");
end
assert(measured(2) > measured(1) + 6, ...
    "PBCH measured post-equalization SINR must track the requested AWGN sweep.");

bad = pbch;
bad.PostEqSINR_dB = bad.PostEqSINR_dB + 1;
identifier = localCaptureError(@() ...
    sixgr.phy.rx.validatePBCHNoiseDomainEvidence(bad));
assert(identifier == "sixgr:phy:pbch:MixedNoiseDomainEvidence", ...
    "PBCH mixed-domain SINR evidence must fail with the typed error.");

bad = pbch;
bad.PostEqSINRAvailable = false;
identifier = localCaptureError(@() ...
    sixgr.phy.rx.validatePBCHNoiseDomainEvidence(bad));
assert(identifier == "sixgr:phy:pbch:InvalidSINRAvailabilityStatus", ...
    "Finite PBCH SINR marked unavailable must fail with the typed error.");

ok = true;
end

function identifier = localCaptureError(fcn)
identifier = "";
try
    fcn();
catch cause
    identifier = string(cause.identifier);
end
end
