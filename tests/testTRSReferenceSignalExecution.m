function ok = testTRSReferenceSignalExecution()
%TESTTRSREFERENCESIGNALEXECUTION Verify TRS generation and observation runtime.

setup6GRSimToolkit("Verbose", false);
if exist("nrOFDMModulate", "file") ~= 2 || exist("nrOFDMDemodulate", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.trs.enable = true;
cfg.phy.carrier.NSizeGrid = 24;
cfg.channel.doppler_Hz = 30;
cfg.channel.dopplerHz = 30;
cfg.channel.fading.maxDoppler_Hz = 30;
cfg = sixgr.util.structSet(cfg, "phy.trs.nPorts", 1);
cfg = sixgr.util.structSet(cfg, "phy.trs.scramblingID", 7);
cfg = sixgr.util.structSet(cfg, "phy.trs.symbolLocations", [2 11]);
cfg = sixgr.util.structSet(cfg, "phy.trs.subcarrierComb", 4);

[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
[trsInd, trsSym, info] = sixgr.phy.refsig.trs(carrier, cfg);
assert(logical(info.Enabled), "TRS helper must enable when cfg.phy.trs.enable=true.");
assert(~isempty(trsInd) && ~isempty(trsSym), "TRS helper must generate actual indices and symbols.");

out = sixgr.link.runTRSTracking(cfg, "SNR_dB", 20);
assert(out.Ok, "TRS tracking smoke must complete.");
assert(isfinite(out.NMSE_dB), "TRS runtime must report NMSE.");
assert(isfinite(out.PhaseError_deg), "TRS runtime must report phase error.");
assert(isfinite(out.InjectedDoppler_Hz) && abs(out.InjectedDoppler_Hz - 30) < 1e-9, ...
    "TRS runtime must expose the injected Doppler semantics.");
assert(isfinite(out.EstimatedDoppler_Hz), "TRS runtime must report a finite Doppler estimate.");
assert(abs(out.EstimatedDoppler_Hz - out.InjectedDoppler_Hz) < 20, ...
    "TRS Doppler estimate must stay reasonably close to the injected Doppler in the smoke case.");
assert(out.NMSE_dB < 0, "TRS NMSE should be meaningfully below 0 dB at 20 dB SNR.");

ok = true;
end
