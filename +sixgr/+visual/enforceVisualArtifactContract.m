function report = enforceVisualArtifactContract(runFolder, varargin)
%ENFORCEVISUALARTIFACTCONTRACT Remove stale visual artifacts in strict mode.

opts = struct("StrictMode", false, "CreateUnavailableCards", false);
if rem(numel(varargin), 2) ~= 0
    error("sixgr:visual:enforceVisualArtifactContract:BadNV", "Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    if isfield(opts, name)
        opts.(name) = varargin{i + 1};
    else
        error("sixgr:visual:enforceVisualArtifactContract:BadOpt", "Unknown option: %s", char(name));
    end
end

runFolder = string(runFolder);
contracts = sixgr.visual.loadVisualArtifactContract();
rows = repmat(struct("PlotId", "", "ImagePath", "", "UnavailablePath", "", "SourceCSV", "", ...
    "VisualValidity", "", "EnforcementStatus", "", "SuppressionReason", ""), 0, 1);

for i = 1:numel(contracts)
    spec = contracts(i);
    imagePath = string(fullfile(char(runFolder), char(spec.ImagePath)));
    unavailablePath = sixgr.visual.unavailableArtifactPath(imagePath);
    sourcePath = string(fullfile(char(runFolder), char(spec.SourceCSV)));
    if exist(sourcePath, "file") == 2
        try
            sourceT = readtable(sourcePath, "VariableNamingRule", "preserve");
            status = sixgr.visual.evaluateVisualArtifactContract(spec, sourceT);
        catch ME
            status = localUnavailableStatus(spec, "source_csv_unreadable:" + string(ME.identifier));
        end
    else
        status = localUnavailableStatus(spec, "source_csv_missing");
    end

    enforcement = "not_required";
    if logical(opts.StrictMode)
        if string(status.PlotRenderStatus) ~= "rendered"
            localDeleteIfExists(imagePath);
            enforcement = "deleted_stale_normal_artifact";
            if logical(opts.CreateUnavailableCards)
                sixgr.visual.writeUnavailablePlotCard(unavailablePath, spec.PlotId, ...
                    "Plot unavailable: " + string(status.PlotSuppressionReason));
                enforcement = enforcement + "|wrote_unavailable_card";
            end
        else
            localDeleteIfExists(unavailablePath);
            enforcement = "source_satisfies_contract";
        end
    end

    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "PlotId", string(spec.PlotId), ...
        "ImagePath", string(spec.ImagePath), ...
        "UnavailablePath", string(sixgr.visual.unavailableArtifactPath(spec.ImagePath)), ...
        "SourceCSV", string(spec.SourceCSV), ...
        "VisualValidity", string(status.VisualValidity), ...
        "EnforcementStatus", enforcement, ...
        "SuppressionReason", string(status.PlotSuppressionReason));
end

report = struct2table(rows);
end

function status = localUnavailableStatus(spec, reason)
status = sixgr.visual.validatePlotData(spec.PlotType, [], [], ...
    "MinimumRows", spec.MinRows, ...
    "MinimumUniqueX", spec.MinUniqueX, ...
    "MinimumUniqueY", spec.MinUniqueY, ...
    "LLSValidity", "unavailable");
status.PlotRenderStatus = "suppressed";
status.PlotSuppressionReason = string(reason);
status.CountsAsRealPlot = false;
status.VisualValidity = "unavailable";
status.WarningBannerText = "";
end

function localDeleteIfExists(path)
try
    if exist(path, "file") == 2
        delete(path);
    end
catch
end
end
