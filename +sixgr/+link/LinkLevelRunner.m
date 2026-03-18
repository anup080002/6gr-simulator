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

            rows = repmat(localCaseRow("", struct()), 0, 1);

            caseDefs = { ...
                struct('name',"CellSearch_MIB_SIB1", 'fcn', @() sixgr.link.runCellSearch_MIB_SIB1(cfg, "Logger", log)); ...
                struct('name',"PRACH_Detection",     'fcn', @() sixgr.link.runPRACHDetection(cfg, "Logger", log, "SNR_dB", 100)); ...
                struct('name',"DL_PDSCH_Throughput", 'fcn', @() sixgr.link.runDLPDSCHThroughput(cfg, "Logger", log, "NumFrames", numFrames)); ...
                struct('name',"UL_PUSCH_Throughput", 'fcn', @() sixgr.link.runULPUSCHThroughput(cfg, "Logger", log, "NumFrames", numFrames, "SNR_dB", 30)); ...
                struct('name',"UL_SRS_ChannelEst",   'fcn', @() sixgr.link.runSRSChannelEstimation(cfg, "Logger", log, "SNR_dB", 30)); ...
                struct('name',"UL_LowPAPR",          'fcn', @() sixgr.link.runULLowPAPR(cfg, "Logger", log, "NumFrames", numFrames)) ...
                };

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

            if ~isempty(rows)
                out.KPITable = struct2table(rows);
            end

            out.Ok = ~any(out.KPITable.Ok == false & out.KPITable.Skipped == false);
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
