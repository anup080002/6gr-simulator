function plotPaths = exportISACArtifacts(runFolder,cfg,diagnostic,generatePlots,options)
%EXPORTISACARTIFACTS Publish measured ISAC tables and PNG visualizations.

arguments
    runFolder (1,:) char
    cfg (1,1) struct
    diagnostic (1,1) struct
    generatePlots (1,1) logical
    options (1,1) struct = struct()
end

plotPaths = strings(0,1);
if ~logical(cfg.isac.enabled)
    return;
end
if ~isfield(diagnostic,"ISAC") || isempty(diagnostic.ISAC) || ...
        ~logical(sixgr.util.structGet(diagnostic.ISAC,"EvidenceValid",false))
    error("sixgr:lls:MissingISACRuntimeEvidence", ...
        "Enabled ISAC artifacts require a valid executed sensing capture.");
end
sensing = diagnostic.ISAC;
if ~logical(cfg.isac.output.enabled)
    error("sixgr:isac:OutputDisabled", ...
        "Enabled ISAC execution requires isac.output.enabled=true.");
end
structured = logical(cfg.isac.output.structuredComponentFolders);
if isfield(options,"StructuredComponentFolders") && ...
        logical(options.StructuredComponentFolders) ~= structured
    error("sixgr:isac:OutputLayoutOverrideRejected", ...
        "ISAC output layout is YAML-owned and cannot be overridden at runtime.");
end
csvDir = string(runFolder);
imageDir = string(runFolder);
if structured
    component = string(sixgr.util.structGet(cfg,"isac.output.componentFolder",""));
    if ~isscalar(component) || isempty(regexp(char(component),'^[A-Za-z0-9_-]+$','once'))
        error("sixgr:isac:InvalidComponentFolder", ...
            "isac.output.componentFolder must be one safe relative folder name.");
    end
    csvDir = string(fullfile(runFolder,char(component),"csv"));
    imageDir = string(fullfile(runFolder,char(component),"image"));
end
saveCSV = logical(cfg.isac.output.saveCSV);
saveRaster = logical(cfg.isac.output.savePNG);
imageFormat = lower(string(cfg.isac.output.imageFormat));
resolutionDPI = double(cfg.isac.output.imageResolutionDPI);
if saveCSV
    sixgr.util.ensureFolder(char(csvDir));
    writetable(sensing.ConfigTable,fullfile(csvDir,"isac_config_resolved.csv"));
    writetable(sensing.TargetTruthTable,fullfile(csvDir,"isac_target_truth.csv"));
    writetable(sensing.RangeProfileTable,fullfile(csvDir,"isac_range_profile.csv"));
    writetable(sensing.RangeAngleTable,fullfile(csvDir,"isac_range_angle_map.csv"));
    writetable(sensing.RangeDopplerTable,fullfile(csvDir,"isac_range_doppler_map.csv"));
    writetable(sensing.DetectionTable,fullfile(csvDir,"isac_detections.csv"));
    writetable(sensing.CFARThresholdTable,fullfile(csvDir,"isac_cfar_thresholds.csv"));
    writetable(sensing.RuntimeTable,fullfile(csvDir,"isac_runtime_evidence.csv"));
end
if ~generatePlots || ~saveRaster
    return;
end
if ~saveCSV
    error("sixgr:isac:RasterRequiresCSVLineage", ...
        "ISAC raster publication requires saveCSV=true so every image has exact runtime source lineage.");
end
sixgr.util.ensureFolder(char(imageDir));

scenarioPath = localRasterPath(imageDir,"isac_scenario_geometry",imageFormat);
fig = figure("Visible","off","Color","white","Position",[100 100 1060 700]);
cleanup = onCleanup(@() localClose(fig)); %#ok<NASGU>
truth = sensing.TargetTruthTable;
gnb = double(sensing.GNBPositionM(:));
ue = double(sensing.UEPositionM(:));
if numel(gnb) ~= 3 || numel(ue) ~= 3 || ...
        any(~isfinite([gnb;ue]))
    error("sixgr:isac:MissingRuntimeNodePositionEvidence", ...
        "ISAC geometry images require the exact executed gNB and UE positions.");
end
plot3(gnb(1),gnb(2),gnb(3),'^','MarkerSize',13,'LineWidth',2, ...
    'MarkerFaceColor',[0.00 0.45 0.74],'DisplayName','gNB / sensing Tx');
hold on;
plot3(ue(1),ue(2),ue(3),'pentagram','MarkerSize',13,'LineWidth',2, ...
    'MarkerFaceColor',[0.85 0.33 0.10],'DisplayName','UE');
for index = 1:height(truth)
    plot3(truth.X_m(index),truth.Y_m(index),truth.Z_m(index),'o', ...
        'MarkerSize',10,'LineWidth',2,'MarkerFaceColor',[0.47 0.67 0.19], ...
        'DisplayName',sprintf('Target %d',truth.TargetId(index)));
    quiver3(truth.X_m(index),truth.Y_m(index),truth.Z_m(index), ...
        truth.Vx_mps(index),truth.Vy_mps(index),truth.Vz_mps(index),0, ...
        'LineWidth',1.5,'Color',[0.30 0.30 0.30],'HandleVisibility','off');
end
axis equal; grid on; view(35,25);
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
title(sprintf('Executed ISAC scene | %s',strrep(char(cfg.isac.sensingMode),'_',' ')));
legend('Location','best'); localStyle(gca);
exportgraphics(fig,scenarioPath,"Resolution",resolutionDPI);
plotPaths(end+1,1) = string(scenarioPath);
close(fig); clear cleanup;

profilePath = localRasterPath(imageDir,"isac_range_profile",imageFormat);
fig = figure("Visible","off","Color","white","Position",[100 100 1040 650]);
cleanup = onCleanup(@() localClose(fig)); %#ok<NASGU>
plot(sensing.RangeProfileTable.RangeM,sensing.RangeProfileTable.PowerRelativeDb, ...
    'LineWidth',1.8,'Color',[0.00 0.45 0.74]);
hold on;
for index = 1:height(truth)
    xline(truth.ExpectedRangeM(index),'--','LineWidth',1.3, ...
        'Label',sprintf('Target %d',truth.TargetId(index)));
end
grid on; ylim([-80 3]); xlabel('Range (m)'); ylabel('Relative power (dB)');
title('PDSCH waveform matched-filter range profile'); localStyle(gca);
exportgraphics(fig,profilePath,"Resolution",resolutionDPI);
plotPaths(end+1,1) = string(profilePath);
close(fig); clear cleanup;

anglePath = localRasterPath(imageDir,"isac_range_angle_map",imageFormat);
fig = figure("Visible","off","Color","white","Position",[100 100 1100 700]);
cleanup = onCleanup(@() localClose(fig)); %#ok<NASGU>
imagesc(sensing.AzimuthDeg,sensing.RangeM, ...
    max(10*log10(max(sensing.RangeAnglePower,realmin)/ ...
    max(sensing.RangeAnglePower,[],"all")),-60));
axis xy; colorbar; colormap turbo; hold on;
plot(truth.ExpectedAzimuthDeg,truth.ExpectedRangeM,'wo','MarkerSize',10, ...
    'LineWidth',2,'DisplayName','Target truth');
if ~isempty(sensing.DetectionTable)
    plot(sensing.DetectionTable.MeasuredAzimuthDeg, ...
        sensing.DetectionTable.MeasuredRangeM,'rx','MarkerSize',10, ...
        'LineWidth',2,'DisplayName','CA-CFAR detection');
end
xlabel('Local receive azimuth (deg)'); ylabel('Range (m)');
title('Measured ISAC range-azimuth response'); legend('Location','best');
localStyle(gca);
exportgraphics(fig,anglePath,"Resolution",resolutionDPI);
plotPaths(end+1,1) = string(anglePath);
close(fig); clear cleanup;

dopplerPath = localRasterPath(imageDir,"isac_range_doppler_map",imageFormat);
fig = figure("Visible","off","Color","white","Position",[100 100 1100 700]);
cleanup = onCleanup(@() localClose(fig)); %#ok<NASGU>
imagesc(sensing.DopplerHz,sensing.RangeM, ...
    max(10*log10(max(sensing.RangeDopplerPower,realmin)/ ...
    max(sensing.RangeDopplerPower,[],"all")),-60));
axis xy; colorbar; colormap turbo; hold on;
plot(truth.ExpectedDopplerHz,truth.ExpectedRangeM,'wo','MarkerSize',10, ...
    'LineWidth',2,'DisplayName','Target truth');
xlabel('Doppler frequency (Hz)'); ylabel('Range (m)');
title('Measured ISAC range-Doppler response'); legend('Location','best');
localStyle(gca);
exportgraphics(fig,dopplerPath,"Resolution",resolutionDPI);
plotPaths(end+1,1) = string(dopplerPath);
close(fig); clear cleanup;

localWriteISACPlotLineage(runFolder,csvDir, ...
    [string(scenarioPath);string(profilePath);string(anglePath);string(dopplerPath)]);
end

function localWriteISACPlotLineage(runFolder,csvDir,imagePaths)
plotIds = ["isac_scenario_geometry";"isac_range_profile"; ...
    "isac_range_angle_map";"isac_range_doppler_map"];
sourceNames = { ...
    ["isac_config_resolved.csv";"isac_target_truth.csv";"isac_runtime_evidence.csv"], ...
    ["isac_range_profile.csv";"isac_target_truth.csv"], ...
    ["isac_range_angle_map.csv";"isac_detections.csv";"isac_target_truth.csv"], ...
    ["isac_range_doppler_map.csv";"isac_target_truth.csv"]};
rows = repmat(localEmptyLineageRow(),numel(plotIds),1);
for index = 1:numel(plotIds)
    names = sourceNames{index};
    paths = strings(numel(names),1);
    hashes = strings(numel(names),1);
    for sourceIndex = 1:numel(names)
        sourcePath = fullfile(csvDir,char(names(sourceIndex)));
        if ~isfile(sourcePath)
            error("sixgr:isac:PlotLineageSourceMissing", ...
                "ISAC image %s is missing runtime source CSV %s.", ...
                plotIds(index),sourcePath);
        end
        paths(sourceIndex) = localRelativePath(runFolder,sourcePath);
        hashes(sourceIndex) = localFileSHA256(sourcePath);
    end
    rows(index) = struct( ...
        "PlotId",plotIds(index), ...
        "ImagePath",localRelativePath(runFolder,imagePaths(index)), ...
        "SourceCSV",strjoin(paths,"|"), ...
        "SourceCSV_SHA256",strjoin(hashes,"|"), ...
        "ImageSHA256",localFileSHA256(imagePaths(index)), ...
        "Status","PASS", ...
        "LineageStatus","rendered_component_plot");
end
sixgr.util.csvWriteTable(fullfile(csvDir,"isac_plot_lineage.csv"), ...
    struct2table(rows,"AsArray",true));
end

function row = localEmptyLineageRow()
row = struct( ...
    "PlotId","", ...
    "ImagePath","", ...
    "SourceCSV","", ...
    "SourceCSV_SHA256","", ...
    "ImageSHA256","", ...
    "Status","", ...
    "LineageStatus","");
end

function pathValue = localRelativePath(root,pathValue)
root = string(java.io.File(char(string(root))).getCanonicalPath());
pathValue = string(java.io.File(char(string(pathValue))).getCanonicalPath());
prefix = root + string(filesep);
if pathValue == root
    pathValue = ".";
elseif startsWith(pathValue,prefix,"IgnoreCase",ispc)
    pathValue = extractAfter(pathValue,strlength(prefix));
else
    error("sixgr:isac:PlotLineagePathEscape", ...
        "ISAC plot lineage path escapes the run folder: %s",pathValue);
end
pathValue = replace(pathValue,"\","/");
end

function hash = localFileSHA256(pathValue)
fid = fopen(pathValue,"rb");
if fid < 0
    error("sixgr:isac:PlotLineageFileUnreadable", ...
        "Cannot read ISAC plot-lineage artifact: %s",pathValue);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function localStyle(axisHandle)
set(axisHandle,'Color','white','XColor',[0.12 0.12 0.12], ...
    'YColor',[0.12 0.12 0.12],'ZColor',[0.12 0.12 0.12], ...
    'GridColor',[0.40 0.40 0.40],'FontSize',11);
fig = ancestor(axisHandle,'figure');
textObjects = findall(fig,'Type','text');
for index = 1:numel(textObjects)
    set(textObjects(index),'Color',[0.08 0.08 0.08]);
end
colorbars = findall(fig,'Type','ColorBar');
for index = 1:numel(colorbars)
    set(colorbars(index),'Color',[0.12 0.12 0.12]);
end
end

function localClose(fig)
if isgraphics(fig)
    close(fig);
end
end

function path = localRasterPath(folder,stem,imageFormat)
if imageFormat == "jpeg"
    extension = ".jpeg";
else
    extension = ".png";
end
path = fullfile(folder,char(string(stem)+extension));
end
