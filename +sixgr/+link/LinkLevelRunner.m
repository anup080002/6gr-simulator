classdef LinkLevelRunner
% sixgr.link.LinkLevelRunner
% Unified link-level runner for smoke and KPI generation.

    methods(Static)
        function out = run(ctx, params)
            if nargin < 2 || isempty(params)
                params = struct();
            end

            cfg = ctx.Cfg;
            log = ctx.Logger;

            out = struct();
            out.Ok = true;
            out.Skipped = false;
            out.Errors = strings(0,1);
            out.Cases = struct();
            out.KPITable = table();
            out.Artifacts = struct('csv',{{}},'mat',{{}},'fig',{{}});

            numFrames = double(sixgr.util.structGet(params, "NumFrames", ...
                             sixgr.util.structGet(cfg, "run.numFrames", 10)));
            if sixgr.util.structGet(cfg, "run.shortRun", false)
                numFrames = min(numFrames, 8);
            end
            numFrames = max(1, round(numFrames));
            baseSNR_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", 30));

            rows = repmat(localCaseRow("", struct()), 0, 1);

            caseDefs = { ...
                struct('name',"CellSearch_MIB_SIB1", 'fcn', @() sixgr.link.runCellSearch_MIB_SIB1(cfg, "Logger", log)); ...
                struct('name',"PRACH_Detection",     'fcn', @() sixgr.link.runPRACHDetection(cfg, "Logger", log, "SNR_dB", baseSNR_dB)); ...
                struct('name',"DL_PDSCH_Throughput", 'fcn', @() sixgr.link.runDLPDSCHThroughput(cfg, "Logger", log, "NumFrames", numFrames)); ...
                struct('name',"UL_PUSCH_Throughput", 'fcn', @() sixgr.link.runULPUSCHThroughput(cfg, "Logger", log, "NumFrames", numFrames, "SNR_dB", baseSNR_dB)); ...
                struct('name',"UL_SRS_ChannelEst",   'fcn', @() sixgr.link.runSRSChannelEstimation(cfg, "Logger", log, "SNR_dB", baseSNR_dB)); ...
                struct('name',"UL_LowPAPR",          'fcn', @() sixgr.link.runULLowPAPR(cfg, "Logger", log, "NumFrames", numFrames)) ...
                };
            seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
            useParallelCases = localCanParallelizeCases(cfg, numel(caseDefs));

            if useParallelCases
                caseNames = strings(numel(caseDefs), 1);
                caseResults = cell(numel(caseDefs), 1);
                for k = 1:numel(caseDefs)
                    caseNames(k) = string(caseDefs{k}.name);
                end
                parfor k = 1:numel(caseDefs)
                    caseResults{k} = localRunCaseDeterministic(caseNames(k), cfg, numFrames, seedBase + 100*k);
                end
                for k = 1:numel(caseDefs)
                    cName = caseDefs{k}.name;
                    cres = caseResults{k};
                    if ~logical(sixgr.util.structGet(cres, "Ok", false)) && ...
                            ~logical(sixgr.util.structGet(cres, "Skipped", false))
                        out.Errors(end+1,1) = "Case " + cName + " failed: " + string(sixgr.util.structGet(cres, "Notes", "")); %#ok<AGROW>
                    end
                    out.Cases.(matlab.lang.makeValidName(cName)) = cres;
                    rows(end+1,1) = localCaseRow(cName, cres); %#ok<AGROW>
                end
            else
                for k = 1:numel(caseDefs)
                    c = caseDefs{k};
                    try
                        cres = c.fcn();
                    catch ME
                        cres = struct();
                        cres.Ok = false;
                        cres.Skipped = false;
                        cres.Notes = "Crash: " + string(ME.message);
                        out.Errors(end+1,1) = "Case " + c.name + " failed: " + string(ME.message);
                    end
                    out.Cases.(matlab.lang.makeValidName(c.name)) = cres;
                    rows(end+1,1) = localCaseRow(c.name, cres); %#ok<AGROW>
                end
            end

            if ~isempty(rows)
                out.KPITable = struct2table(rows);
            end

            skippedMask = false(height(out.KPITable), 1);
            if istable(out.KPITable) && ismember("Skipped", string(out.KPITable.Properties.VariableNames))
                skippedMask = logical(out.KPITable.Skipped);
            end
            if any(skippedMask)
                skippedCases = string(out.KPITable.Case(skippedMask));
                out.Errors(end+1,1) = "Skipped link coverage cases: " + strjoin(skippedCases, ", ");
            end
            out.Ok = ~any(~logical(out.KPITable.Ok) | skippedMask);
            if ~out.Ok
                log.warn("LinkLevelRunner completed with failing case(s).");
            else
                log.info("LinkLevelRunner completed.");
            end

            try
                doCSV = logical(sixgr.util.structGet(cfg, "outputs.saveCSV", true));
                doMAT = logical(sixgr.util.structGet(cfg, "outputs.saveMAT", true));
                doFig = localResolveSaveFigures(cfg, false);
                doPNG = logical(sixgr.util.structGet(cfg, "outputs.savePNG", true));
                plotVisible = logical(sixgr.util.structGet(cfg, "outputs.plotVisible", false));
                figRes = max(72, round(double(sixgr.util.structGet(cfg, "outputs.figureResolution", 140))));
                if doCSV || doMAT || doFig
                    out.Artifacts = sixgr.link.exportLinkKPIs(ctx.RunFolder, out.KPITable, out, ...
                        "SaveCSV", doCSV, "SaveMAT", doMAT, ...
                        "SaveFigures", doFig, "SavePNG", doPNG, ...
                        "FigurePrefix", "link", "PlotVisible", plotVisible, ...
                        "FigureResolution", figRes);
                end
            catch ME
                out.Errors(end+1,1) = "Export failed: " + string(ME.message);
            end
        end
    end
end

function tf = localCanParallelizeCases(cfg, nCases)
tf = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
    double(sixgr.util.structGet(cfg, "run.numWorkers", 0)) > 1 && ...
    nCases > 1 && exist("gcp", "file") == 2 && ~isempty(gcp("nocreate"));
end

function cres = localRunCaseDeterministic(caseName, cfg, numFrames, seed)
rng(double(seed), "twister");
baseSNR_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", 30));
try
    switch string(caseName)
        case "CellSearch_MIB_SIB1"
            cres = sixgr.link.runCellSearch_MIB_SIB1(cfg);
        case "PRACH_Detection"
            cres = sixgr.link.runPRACHDetection(cfg, "SNR_dB", baseSNR_dB);
        case "DL_PDSCH_Throughput"
            cres = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", numFrames);
        case "UL_PUSCH_Throughput"
            cres = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", numFrames, "SNR_dB", baseSNR_dB);
        case "UL_SRS_ChannelEst"
            cres = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", baseSNR_dB);
        case "UL_LowPAPR"
            cres = sixgr.link.runULLowPAPR(cfg, "NumFrames", numFrames);
        otherwise
            error("sixgr:link:UnknownCase", "Unknown link case '%s'.", string(caseName));
    end
catch ME
    cres = struct();
    cres.Ok = false;
    cres.Skipped = false;
    cres.Notes = "Crash: " + string(ME.message);
end
end

function doFig = localResolveSaveFigures(cfg, defaultVal)
if nargin < 2
    defaultVal = false;
end
if isfield(cfg, "outputs") && isstruct(cfg.outputs)
    if isfield(cfg.outputs, "saveFigures")
        doFig = logical(cfg.outputs.saveFigures);
        return;
    end
    if isfield(cfg.outputs, "saveFIG")
        doFig = logical(cfg.outputs.saveFIG);
        return;
    end
end
doFig = logical(defaultVal);
end

function row = localCaseRow(caseName, s)
row = struct();
row.Case = string(caseName);
row.Ok = logical(sixgr.util.structGet(s, "Ok", false));
row.Skipped = logical(sixgr.util.structGet(s, "Skipped", false));
row.BER = double(sixgr.util.structGet(s, "BER", NaN));
row.BLER = double(sixgr.util.structGet(s, "BLER", NaN));
row.Throughput_Mbps = double(sixgr.util.structGet(s, "Throughput_Mbps", NaN));
row.EVM_rms = double(sixgr.util.structGet(s, "EVM_rms", NaN));
row.PAPR_CP_dB = double(sixgr.util.structGet(s, "PAPR_CP_dB", NaN));
row.PAPR_DFTs_dB = double(sixgr.util.structGet(s, "PAPR_DFTs_dB", NaN));
row.PAPR_Gain_dB = double(sixgr.util.structGet(s, "PAPR_Gain_dB", NaN));
row.NMSE_dB = double(sixgr.util.structGet(s, "NMSE_dB", NaN));
row.Notes = string(sixgr.util.structGet(s, "Notes", ""));
end
