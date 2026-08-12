function record = saveFigureArtifact(fig, figureData, runDirectory, relativeDirectory, basename, evidenceClass, scenario, titleText, options)
%SAVEFIGUREARTIFACT Save figure, source data, MAT and metadata atomically.

arguments
    fig (1,1) matlab.ui.Figure
    figureData table
    runDirectory (1,1) string
    relativeDirectory (1,1) string
    basename (1,1) string
    evidenceClass (1,1) string
    scenario (1,1) struct
    titleText (1,1) string
    options.Metadata (1,1) struct = struct()
end
if height(figureData) == 0
    error("sixgr:ntn:resilientsync:EmptyFigureData", ...
        "Figure %s has no source rows.", char(basename));
end
folder = fullfile(char(runDirectory), char(relativeDirectory));
if exist(folder,"dir") ~= 7, mkdir(folder); end
base = fullfile(folder,char(basename));
pngPath = string(base) + ".png";
exportgraphics(fig,pngPath,"Resolution",double(scenario.outputs.save_png_dpi));
paths = pngPath;
if logical(scenario.outputs.save_pdf_vector)
    pdfPath = string(base) + ".pdf";
    exportgraphics(fig,pdfPath,"ContentType","vector");
    paths(end+1,1) = pdfPath;
end
if logical(scenario.outputs.save_fig)
    figPath = string(base) + ".fig";
    savefig(fig,figPath);
    paths(end+1,1) = figPath;
end
csvPath = string(base) + ".csv";
writetable(figureData,csvPath);
paths(end+1,1) = csvPath;
data = figureData; %#ok<NASGU>
matPath = string(base) + ".mat";
save(matPath,"data","-v7.3");
paths(end+1,1) = matPath;
metadata = struct( ...
    "SchemaVersion","sixgr.ntn.resilientsync.figure/v2", ...
    "Basename",basename,"Title",titleText, ...
    "EvidenceClass",evidenceClass, ...
    "Measured",evidenceClass == "CALIBRATED_LLS" && ...
        string(sixgr.util.structGet(options.Metadata,"CalibrationStatus","")) == "ACCEPTED", ...
    "ProxyUsed",false,"FallbackUsed",false, ...
    "ConfigSHA256",string(scenario.ConfigSHA256), ...
    "StateProfileSHA256",string(scenario.StateProfileSHA256), ...
    "Rows",height(figureData), ...
    "Columns",string(figureData.Properties.VariableNames), ...
    "ColumnUnits",string(figureData.Properties.VariableUnits), ...
    "CreatedUTC",string(datetime("now","TimeZone","UTC", ...
        "Format","yyyy-MM-dd'T'HH:mm:ss'Z'")));
extraFields=fieldnames(options.Metadata);
for i=1:numel(extraFields)
    metadata.(extraFields{i})=options.Metadata.(extraFields{i});
end
jsonPath = string(base) + ".metadata.json";
localWriteJSON(jsonPath,metadata);
paths(end+1,1) = jsonPath;
record = table(string(relativeDirectory) + "/" + basename, ...
    evidenceClass, metadata.Measured, strjoin(paths,"|"), "PRODUCED", ...
    'VariableNames', {'RelativeBase','EvidenceClass','Measured','Paths','Status'});
end

function localWriteJSON(path,value)
fid = fopen(path,"w","n","UTF-8");
if fid < 0
    error("sixgr:ntn:resilientsync:ArtifactWriteFailed", ...
        "Unable to write %s.",char(path));
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(value,"PrettyPrint",true));
end
