function gate = checkVisualArtifactRenderGate(filePath)
%CHECKVISUALARTIFACTRENDERGATE Decide if a visual artifact may be exported.

gate = struct( ...
    "Matched", false, ...
    "AllowRender", true, ...
    "PlotId", "", ...
    "SourceCSV", "", ...
    "RunFolder", "", ...
    "VisualValidity", "", ...
    "SuppressionReason", "", ...
    "WarningBannerText", "", ...
    "UnavailablePath", "");

filePath = string(filePath);
if endsWith(lower(filePath), "_unavailable.png")
    return;
end

[matched, spec, runFolder] = localMatchContract(filePath);
if ~matched
    return;
end

gate.Matched = true;
gate.PlotId = string(spec.PlotId);
gate.SourceCSV = string(spec.SourceCSV);
gate.RunFolder = string(runFolder);
gate.UnavailablePath = sixgr.visual.unavailableArtifactPath(filePath);

[sourceT, sourceInfo] = sixgr.visual.readContractSourceData(runFolder, spec.SourceCSV);
if ~logical(sourceInfo.Ok)
    status = localUnavailableStatus(spec, string(sourceInfo.Reason));
else
    status = sixgr.visual.evaluateVisualArtifactContract(spec, sourceT);
end

gate.VisualValidity = string(status.VisualValidity);
gate.SuppressionReason = string(status.PlotSuppressionReason);
gate.WarningBannerText = string(status.WarningBannerText);
gate.AllowRender = string(status.PlotRenderStatus) == "rendered" && any(string(status.VisualValidity) == ["real_lls_evidence","diagnostic_only"]);
end

function [matched, spec, runFolder] = localMatchContract(filePath)
matched = false;
spec = struct();
runFolder = "";
contracts = sixgr.visual.loadVisualArtifactContract();
if isempty(contracts)
    return;
end
normalizedFile = localNormalizePath(filePath);
for i = 1:numel(contracts)
    rel = localNormalizePath(contracts(i).ImagePath);
    if endsWith(normalizedFile, "/" + rel) || normalizedFile == rel
        matched = true;
        spec = contracts(i);
        prefixLen = strlength(normalizedFile) - strlength(rel);
        rootText = extractBefore(normalizedFile, max(prefixLen + 1, 1));
        rootText = regexprep(rootText, "/+$", "");
        runFolder = string(rootText);
        return;
    end
end
end

function out = localNormalizePath(path)
out = replace(string(path), "\", "/");
out = regexprep(out, "/+", "/");
out = regexprep(out, "^/+","");
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
