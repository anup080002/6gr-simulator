function ok = testPowerContextPhysicalUnits()
%TESTPOWERCONTEXTPHYSICALUNITS Validate entity-specific sample power units.

setup6GRSimToolkit("Verbose", false);

cfg = struct();
cfg.powerAndRF.bsTxPower_dBm = 46;
cfg.powerAndRF.ueTxPower_dBm = 23;
cfg.powerAndRF.bsRFChainCount = 64;
cfg.powerAndRF.ueRFChainCount = 2;
cfg.scenario.ue.nTxAnt = 2;
cfg.phy.nTxAnt = 64;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.channel.pathlossEnabled = true;
cfg.channel.pathloss_dB = 100;
cfg.channel.bandwidth_Hz = 20e6;
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.energy.bs.staticW = 0;
cfg.energy.bs.perTRxPW = 5;
cfg.energy.bs.sleepW = 10;
cfg.energy.bs.efficiencyPA = 1;
cfg.energy.ue.idleW = 1;
cfg.energy.ue.rxW = 1.5;
cfg.energy.ue.sleepW = 0.1;
cfg.energy.ue.txWPerWattRF = 1;
cfg.lls6g.energy_efficiency.rf_chain_count = 64;
cfg.lls6g.energy_efficiency.pa_efficiency = 1;
cfg.lls6g.energy_efficiency.bs_static_power_w = 0;
cfg.lls6g.energy_efficiency.bs_per_rf_chain_power_w = 5;
cfg.lls6g.energy_efficiency.bs_sleep_power_w = 10;
cfg.lls6g.energy_efficiency.bs_pa_efficiency = 1;
cfg.lls6g.energy_efficiency.ue_idle_power_w = 1;
cfg.lls6g.energy_efficiency.ue_rx_power_w = 1.5;
cfg.lls6g.energy_efficiency.ue_sleep_power_w = 0.1;
cfg.lls6g.energy_efficiency.ue_tx_dc_per_watt_rf = 1;
cfg.lls6g.energy_efficiency.bs_tx_power_dbm = 46;
cfg.lls6g.energy_efficiency.ue_tx_power_dbm = 23;
cfg.lls6g.energy_efficiency.bs_rf_chain_count = 64;
cfg.lls6g.energy_efficiency.ue_rf_chain_count = 2;

xDL = complex(ones(2048, 4), zeros(2048, 4));
[yDL, ctxDL] = sixgr.rf.applyPowerContext(xDL, cfg, "DL", struct());
assert(abs(ctxDL.OutputTotalPower_dBm - 46) < 1e-10, ...
    "DL waveform total sample power must close to 46 dBm.");
assert(abs(sum(ctxDL.OutputPerPortPower_mW) - ctxDL.TotalTxPower_mW) < 1e-6, ...
    "DL per-port powers must sum to total transmit power.");

xUL = complex(ones(2048, 2), zeros(2048, 2));
[~, ctxUL] = sixgr.rf.applyPowerContext(xUL, cfg, "UL", struct());
assert(abs(ctxUL.OutputTotalPower_dBm - 23) < 1e-10, ...
    "UL waveform total sample power must close to 23 dBm.");
assert(ctxUL.RFChainCount == 2, ...
    "UE RF-chain count must not inherit the 64-chain gNB configuration.");

% Under the explicit DL full-BWP EPRE policy, narrowing an allocation must
% reduce emitted power rather than boosting the occupied REs back to the
% full cell-power budget.  Use exact OFDM waveforms and exact transmit grids
% so this checks the production reference plane, not an algebraic proxy.
carrier = nrCarrierConfig;
carrier.NSizeGrid = 25;
carrier.SubcarrierSpacing = 15;
nsc = 12 * carrier.NSizeGrid;
fullGrid = complex(ones(nsc, 14, 1));
sparseGrid = complex(zeros(nsc, 14, 1));
sparseGrid(1:12, :, 1) = 1;
[fullWaveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate( ...
    carrier, fullGrid);
[sparseWaveform, sparseOFDMInfo] = sixgr.phy.waveform.ofdmModulate( ...
    carrier, sparseGrid);
cfgFixedEPRE = cfg;
cfgFixedEPRE.powerAndRF.downlinkPowerNormalizationPolicy = ...
    "fixed_epre_over_configured_bwp";
[fullScaled, fullContext] = sixgr.rf.applyPowerContext( ...
    fullWaveform, cfgFixedEPRE, "DL", ...
    struct("OFDM", ofdmInfo, "PortGrid", fullGrid));
[sparseScaled, sparseContext] = sixgr.rf.applyPowerContext( ...
    sparseWaveform, cfgFixedEPRE, "DL", ...
    struct("OFDM", sparseOFDMInfo, "PortGrid", sparseGrid));
assert(abs(fullContext.ReferenceOutputPower_dBm - 46) < 1e-9 && ...
        abs(sparseContext.ReferenceOutputPower_dBm - 46) < 1e-9, ...
    "Full-BWP-equivalent DL power must close to the configured cell budget.");
expectedBackoff_dB = 10 * log10(12 / nsc);
assert(abs(sparseContext.ActualEmittedPowerBackoffFromBudget_dB - ...
        expectedBackoff_dB) < 1e-8, ...
    "A one-PRB DL allocation must emit its occupied-band fraction of the full-BWP budget.");
fullRecovered = nrOFDMDemodulate(carrier, fullScaled);
sparseRecovered = nrOFDMDemodulate(carrier, sparseScaled);
fullEPRE = mean(abs(double(fullRecovered(:))).^2, "omitnan");
sparseEPRE = mean(abs(double(sparseRecovered(1:12, :, 1))).^2, "all", "omitnan");
assert(abs(10 * log10(sparseEPRE / fullEPRE)) < 1e-8, ...
    "Occupied DL RE EPRE must be invariant to scheduled PRB occupancy.");
assert(string(sparseContext.NormalizationGridSource) == "tx_info.PortGrid" && ...
        abs(sparseContext.FullBWPActivityFactor - 12 / nsc) < 1e-12, ...
    "The DL power ledger must identify its exact grid and measured occupancy factor.");
assert(isfinite(sparseContext.ReferenceInputPower_dBm) && ...
        isfinite(sparseContext.ReferenceOutputPower_dBm) && ...
        isfinite(sparseContext.PowerClosureError_dB) && ...
        strlength(strtrim(string(sparseContext.ConversionEquation))) > 0, ...
    "The power ledger must expose its measured input/output planes and exact conversion equation.");

% Sparse physical signals must be normalized on the symbols in which they
% actually transmit.  Averaging a one-symbol SRS/PUCCH waveform across an
% otherwise empty slot would boost its active-symbol power by 10log10(14).
nfft = 128;
cpLength = 9;
nSymbols = 14;
symbolLength = nfft + cpLength;
xSparse = complex(zeros(symbolLength * nSymbols, 2));
activeSymbol = 11;
activeInterval = (activeSymbol - 1) * symbolLength + (1:symbolLength);
useful = (activeSymbol - 1) * symbolLength + cpLength + (1:nfft);
% Populate a physically complete OFDM symbol, including its cyclic prefix.
% The active-power reference deliberately excludes CP, while the independent
% whole-slot duty-cycle check includes it.
xSparse(activeInterval, :) = 1;
ofdm = struct("Nfft", nfft, ...
    "CyclicPrefixLengths", repmat(cpLength, 1, nSymbols));
[ySparse, ctxSparse] = sixgr.rf.applyPowerContext( ...
    xSparse, cfg, "UL", struct("OFDM", ofdm));
[activePower_mW, ~, activeInfo] = ...
    sixgr.rf.measureActiveOFDMTotalPower(ySparse, struct("OFDM", ofdm));
wholeSlotPower_mW = mean(sum(abs(double(ySparse)).^2, 2), "omitnan");
assert(abs(10 * log10(activePower_mW) - 23) < 1e-10 && ...
    abs(10 * log10(wholeSlotPower_mW) - ...
    (23 - 10 * log10(nSymbols))) < 0.05, ...
    "Sparse UL power must close at the configured value during its active " + ...
    "OFDM symbol, without duty-cycle boosting.");
assert(string(ctxSparse.ReferencePowerDomain) == ...
    "active_nonzero_ofdm_symbols_excluding_cp" && ...
    double(activeInfo.ActiveSymbolCount) == 1 && ...
    isequal(double(activeInfo.ActiveSymbolIndices(:)), activeSymbol - 1), ...
    "The physical power ledger must disclose the exact active OFDM-symbol reference plane.");

% A disturbance waveform is nonzero in every symbol, but its comparison
% against a sparse desired signal must use the desired signal's transmitted
% symbols.  Otherwise the signal and disturbance are measured over different
% time supports and their SINR is not dimensionally meaningful.
rsSparse = RandStream("mt19937ar", "Seed", 9080);
noiseSparse = complex(randn(rsSparse,size(ySparse)), ...
    randn(rsSparse,size(ySparse))) / sqrt(2);
[~,noisePerPort_mW,noiseInfo] = sixgr.rf.measureActiveOFDMTotalPower( ...
    noiseSparse,struct("OFDM",ofdm),"ActiveSymbolIndices", ...
    activeInfo.ActiveSymbolIndices);
expectedNoisePerPort_mW = mean(abs(double(noiseSparse(useful,:))).^2,1);
assert(max(abs(noisePerPort_mW-expectedNoisePerPort_mW)) < 1e-12 && ...
    string(noiseInfo.ReferenceDomain) == ...
    "specified_active_ofdm_symbols_excluding_cp", ...
    "Sparse-signal disturbance power must be measured on the exact same " + ...
    "active OFDM-symbol support as the desired waveform.");

cfgPA = cfg;
cfgPA.rf.pa.enable = true;
cfgPA.rf.pa.method = "softlimiter";
cfgPA.rf.pa.backoff_dB = 0;
rs = RandStream("mt19937ar", "Seed", 9081);
xPA = complex(randn(rs, 2048, 2), randn(rs, 2048, 2)) / sqrt(2);
[yLinear, ~] = sixgr.rf.applyPowerContext(xPA, cfg, "UL", struct());
[yPA, ctxPA] = sixgr.rf.applyPowerContext(xPA, cfgPA, "UL", struct());
[yDeferred, ctxDeferred] = sixgr.rf.applyPowerContext( ...
    xPA,cfgPA,"UL",struct(),"ApplyPA",false);
assert(isequal(yDeferred,yLinear) && ctxDeferred.PAEnabled && ...
    ctxDeferred.PAExecutionDeferred && ~ctxDeferred.PAApplied && ...
    string(ctxDeferred.PAExecutionStatus)=="deferred_until_transmitter_waveform_composition", ...
    "Prepared samples must remain linear while retaining the configured PA authority.");
assert(isnan(ctxDeferred.PACompression_dB) && isnan(ctxDeferred.PAOutputTotalPower_mW), ...
    "A deferred PA must not manufacture measured compression or output power.");
assert(logical(ctxPA.PAApplied) && strcmp(string(ctxPA.PAExecutionStatus), "applied_soft_limiter_pa_in_physical_sample_units"), ...
    "Configured PA nonlinearity must execute in the physical sample-power path.");
paInput_dBm = 10 * log10(max(double(ctxPA.PAInputTotalPower_mW), realmin));
assert(abs(paInput_dBm - 23) < 1e-10, ...
    "Configured Tx power must define the physical pre-PA input reference plane.");
assert(isfinite(ctxPA.OutputTotalPower_dBm) && isfinite(ctxPA.PACompression_dB), ...
    "PA output power and compression must be measured in physical power units.");
assert(abs((ctxPA.OutputTotalPower_dBm - paInput_dBm) - ...
        ctxPA.PACompression_dB) < 1e-10, ...
    "Measured PA power delta must equal the exported compression without post-PA restoration.");
assert(~logical(ctxPA.PAPowerRestorationApplied) && ...
        abs(ctxPA.PAPowerRestorationScale - 1) < 1e-12, ...
    "The physical PA path must not renormalize away nonlinear compression.");
assert(localRelativeNorm(yPA - yLinear) > 1e-4, ...
    "PA nonlinearity must change the waveform samples, not only report metadata.");

cfgMemPA = cfgPA;
cfgMemPA.rf.pa.method = "memorypolynomial";
cfgMemPA.rf.pa.memory.enable = true;
cfgMemPA.rf.pa.memory.taps = [1 0.2];
cfgMemPA.rf.pa.memory.orders = [1 3];
cfgMemPA.rf.pa.memory.orderWeights = [1 -0.05];
[yMemPA, ctxMemPA] = sixgr.rf.applyPowerContext(xPA, cfgMemPA, "UL", struct());
assert(logical(ctxMemPA.PAApplied) && ...
        strcmp(string(ctxMemPA.PAExecutionStatus), "applied_memory_polynomial_pa_in_physical_sample_units"), ...
    "Memory-polynomial PA must execute in the physical sample-power path with model-specific evidence.");
assert(localRelativeNorm(yMemPA - yLinear) > 1e-4, ...
    "Memory-polynomial PA must change samples in the physical power path.");

cfgDL = sixgr.util.structSet(cfg, "lls6g.runtimePowerContext", ctxDL);
cfgDL = sixgr.util.structSet(cfgDL, "lls6g.userContext", struct( ...
    "RuntimeCurrentDirection", "DL"));
[rxDL, replayDL] = sixgr.link.applyWaveformImpairments(yDL, cfgDL, 30.72e6);
rxPower_dBm = localMeanTotalPowerDbm(rxDL);
assert(abs(rxPower_dBm - (-54)) < 1e-9, ...
    "Known 46 dBm, 100 dB pathloss link budget must close to -54 dBm.");
assert(abs(double(replayDL.ServingRxPower_dBm) - (-54)) < 1e-9, ...
    "Replay ServingRxPower_dBm must match the PowerContext link budget.");
assert(strcmp(string(replayDL.ServingRxPowerSource), "power_context_link_budget"), ...
    "Replay must label the dimensional link-budget source.");

bsModel = sixgr.rf.EnergyModelBS(cfg);
p4 = bsModel.power('active', 4, 1, 0);
p8 = bsModel.power('active', 8, 1, 0);
assert(abs((p8.trxW / p4.trxW) - 2) < 1e-12, ...
    "Doubling active gNB RF chains must double, not square, TRx chain power.");

root = tempname;
airFolder = fullfile(root, "air_interface");
mkdir(airFolder);
cleanupObj = onCleanup(@() localCleanup(root)); %#ok<NASGU>
rawTrials = struct();
rawTrials.DL = table("PASS", 1, 1, 10, 1000, 1, ...
    'VariableNames', {'Status','Frame','Slot','PRBs','TBSize_bits','UEID'});
rawTrials.UL = table("PASS", 1, 2, 10, 1000, 1, ...
    'VariableNames', {'Status','Frame','Slot','PRBs','TBSize_bits','UEID'});
artifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, rawTrials);
T = artifacts.TimelineTable;
assert(~isempty(T), "Energy timeline must be generated for measured raw trial rows.");
dlGnb = T(string(T.Entity) == "gNB" & string(T.Direction) == "DL" & string(T.Domain) == "DL_data", :);
ulUe = T(string(T.Entity) == "UE" & string(T.Direction) == "UL" & string(T.Domain) == "UL_data", :);
assert(dlGnb.RFChainCount(1) == 64, "DL gNB timeline rows must use gNB RF-chain count.");
assert(ulUe.RFChainCount(1) == 2, "UL UE timeline rows must use UE RF-chain count.");
assert(abs(dlGnb.TxPower_dBm(1) - 46) < 1e-12, "DL gNB rows must use gNB transmit power.");
assert(abs(ulUe.TxPower_dBm(1) - 23) < 1e-12, "UL UE rows must use UE transmit power.");

ok = true;
end

function dbm = localMeanTotalPowerDbm(x)
power_mW = mean(sum(abs(double(x)).^2, 2), "omitnan");
dbm = 10 * log10(max(power_mW, realmin));
end

function e = localRelativeNorm(x)
e = norm(double(x(:))) / max(1, sqrt(numel(x)));
end
function localCleanup(root)
if isfolder(root)
    try
        rmdir(root, "s");
    catch
    end
end
end
