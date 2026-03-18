classdef HybridRunner
% sixgr.hybrid.HybridRunner
% Hybrid path: LLS BLER calibration -> SLS with abstract PHY LUT.

    methods(Static)
        function out = run(ctx, params)
            if nargin < 2 || isempty(params)
                params = struct();
            end

            cfg = ctx.Cfg;
            log = ctx.Logger;

            out = struct();
            out.Ok = true;
            out.Errors = strings(0,1);
            out.Calibration = struct();
            out.System = struct();
            out.Artifacts = struct('csv',{{}},'mat',{{}},'json',{{}});

            try
                out.Calibration = sixgr.hybrid.CalibrateBLER(ctx, params);
            catch ME
                out.Ok = false;
                out.Errors(end+1,1) = "BLER calibration failed: " + string(ME.message);
                return;
            end

            p2 = params;
            p2.BLERLUT = out.Calibration.LUT;
            p2.BLERDB = sixgr.util.structGet(out.Calibration, "DB", struct());
            try
                out.System = sixgr.system.SystemLevelRunner.run(ctx, p2);
                out.Ok = logical(sixgr.util.structGet(out.System, "Ok", false));
            catch ME
                out.Ok = false;
                out.Errors(end+1,1) = "System runner failed: " + string(ME.message);
            end

            doCSV = logical(sixgr.util.structGet(cfg, "outputs.saveCSV", true));
            doMAT = logical(sixgr.util.structGet(cfg, "outputs.saveMAT", true));
            if doCSV
                csvFile = fullfile(ctx.RunFolder, "csv", "hybrid_bler_lut.csv");
                lutObj = sixgr.util.structGet(out.Calibration, "LUT", struct());
                lutT = table(double(sixgr.util.structGet(lutObj, "SNR_dB", [])), ...
                    double(sixgr.util.structGet(lutObj, "BLER", [])), ...
                    'VariableNames', {'SNR_dB','BLER'});
                sixgr.util.csvWriteTable(csvFile, lutT);
                out.Artifacts.csv{end+1} = csvFile;
                dbCsv = fullfile(ctx.RunFolder, "csv", "hybrid_bler_db_points.csv");
                sixgr.util.csvWriteTable(dbCsv, sixgr.util.structGet(out.Calibration, "Table", table()));
                out.Artifacts.csv{end+1} = dbCsv;
                comboCsv = fullfile(ctx.RunFolder, "csv", "hybrid_bler_db_combos.csv");
                sixgr.util.csvWriteTable(comboCsv, sixgr.util.structGet(out.Calibration, "ComboTable", table()));
                out.Artifacts.csv{end+1} = comboCsv;
            end
            if doMAT
                matFile = fullfile(ctx.RunFolder, "mat", "hybrid_calibration.mat");
                sixgr.util.matSave(matFile, struct("calibration", out.Calibration, "hybrid", out));
                out.Artifacts.mat{end+1} = matFile;
            end
            try
                calibOut = sixgr.hybrid.ExportCalibrationArtifacts(ctx.RunFolder, out.Calibration, ...
                    "StrictMode", logical(sixgr.util.structGet(cfg, "run.strictMode", false)), ...
                    "SourceRun", ctx.RunFolder);
                out.CalibrationArtifacts = calibOut;
                if doCSV
                    out.Artifacts.csv{end+1} = calibOut.CoverageCSV;
                    out.Artifacts.csv{end+1} = calibOut.ValidationCSV;
                end
                if doMAT
                    out.Artifacts.mat{end+1} = calibOut.BLERDBMat;
                end
                out.Artifacts.json{end+1} = calibOut.MetadataJSON;
            catch ME
                out.Errors(end+1,1) = "Calibration artifact export failed: " + string(ME.message);
            end

            if out.Ok
                log.info("HybridRunner completed.");
            else
                log.warn("HybridRunner completed with errors.");
            end
        end
    end
end
