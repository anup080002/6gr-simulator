function ok = testLLSTruthPathPatches()
%TESTLLSTRUTHPATHPATCHES Regression checks for recent LLS truth-path fixes.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(fileparts(mfilename("fullpath")));

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

baseRes = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 18);
if logical(sixgr.util.structGet(baseRes, "Skipped", false))
    ok = true;
    return;
end

T = baseRes.TrialTable;
requiredCols = ["SFN","Frame","Slot","UEID","RNTI","BaseStationID","AllocatedPRBCount","PRBStart","MCS","Layers","RV","RSRP_dB"];
assert(all(ismember(requiredCols, string(T.Properties.VariableNames))), ...
    "DL truth trial table is missing one or more required truth-trace columns.");

Tenriched = sixgr.util.enrichResultTableContext(T(:, intersect(["Layers","RankEstimate","AllocatedPRBCount","PRBCount"], string(T.Properties.VariableNames))), cfg);
rankMask = isfinite(double(Tenriched.Layers)) & isfinite(double(Tenriched.Rank));
if any(rankMask)
    assert(all(double(Tenriched.Rank(rankMask)) == double(Tenriched.Layers(rankMask))), ...
        "Rank must follow transmitted Layers in enriched truth tables.");
end

cfgPathloss = cfg;
cfgPathloss.channel.pathlossEnabled = true;
cfgPathloss.channel.pathloss_dB = 20;
resPathloss = sixgr.link.runDLPDSCHThroughput(cfgPathloss, "NumFrames", 3, "SNR_dB", 18);
if ~logical(sixgr.util.structGet(resPathloss, "Skipped", false))
    refSinr = localFiniteMean(baseRes.TrialTable, "MeasuredSINR_dB");
    lossSinr = localFiniteMean(resPathloss.TrialTable, "MeasuredSINR_dB");
    if isfinite(refSinr) && isfinite(lossSinr)
        assert(lossSinr < refSinr - 1, ...
            "Configured pathloss should reduce the measured DL SINR in the truth path.");
    end
end

cfgNoComp = cfg;
cfgNoComp.phy.impairments.cfoHz = 3500;
cfgNoComp.phy.rx.cfoCompensation = false;
resNoComp = sixgr.link.runDLPDSCHThroughput(cfgNoComp, "NumFrames", 2, "SNR_dB", 24);
cfgComp = cfgNoComp;
cfgComp.phy.rx.cfoCompensation = true;
resComp = sixgr.link.runDLPDSCHThroughput(cfgComp, "NumFrames", 2, "SNR_dB", 24);
if ~(logical(sixgr.util.structGet(resNoComp, "Skipped", false)) || logical(sixgr.util.structGet(resComp, "Skipped", false)))
    noCompResidual = localFiniteMean(resNoComp.TrialTable, "ResidualCFO_PostCorrection_Hz");
    compResidual = localFiniteMean(resComp.TrialTable, "ResidualCFO_PostCorrection_Hz");
    if isfinite(noCompResidual) && isfinite(compResidual)
        assert(abs(compResidual) <= abs(noCompResidual), ...
            "CFO compensation should not worsen residual CFO in truth mode.");
    end
end

cfgHarq = cfg;
cfgHarq.phy.harq.enable = true;
cfgHarq.mac.harq.maxRetx = 1;
resHarq = sixgr.link.runDLPDSCHThroughput(cfgHarq, "NumFrames", 5, "SNR_dB", -4);
if ~logical(sixgr.util.structGet(resHarq, "Skipped", false))
    TH = resHarq.TrialTable;
    harqCols = ["HARQProcess","HARQRound","IsRetransmission","RV"];
    assert(all(ismember(harqCols, string(TH.Properties.VariableNames))), ...
        "HARQ-integrated truth table is missing HARQ tracking columns.");
    if any(logical(TH.IsRetransmission))
        retxRows = TH(logical(TH.IsRetransmission), :);
        offered = double(retxRows.OfferedBits);
        offered = offered(isfinite(offered));
        if ~isempty(offered)
            assert(all(offered == 0), ...
                "Retransmission rows must not count source OfferedBits again.");
        end
    end
end

dummyRx = struct("ChannelEstimate", complex(ones(12, 14, 1, 1)), "NoiseVar", 1e-3, "RSRP_dB", -75);
metrics = sixgr.link.analyzeWaveformChannelMetrics(dummyRx, cfg);
assert(isfield(metrics, "RSRP_dB"), "Waveform channel metrics must expose RSRP_dB.");

pdschText = fileread(fullfile(repoRoot, "+sixgr", "+phy", "+dl", "PDSCH_Rx.m"));
assert(contains(pdschText, "FastShortcutDisabledInTruth"), ...
    "PDSCH_Rx must guard FastAWGNPath in full truth mode.");
reportText = fileread(fullfile(repoRoot, "+sixgr", "+truth", "exportLLSReportingBundle.m"));
assert(~contains(reportText, "function cqi = localMapSINRToCQI"), ...
    "Reporting bundle must not keep a duplicate CQI mapper.");

ok = true;
end

function value = localFiniteMean(T, varName)
value = NaN;
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
x = x(isfinite(x));
if ~isempty(x)
    value = mean(x, "omitnan");
end
end
