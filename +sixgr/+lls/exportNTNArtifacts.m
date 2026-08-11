function plotPath = exportNTNArtifacts(runFolder, cfg, trialTable, generatePlot)
%EXPORTNTNARTIFACTS Export measured NTN channel state and a raster summary.
%
% Values are reduced only from executed transport-block rows. No configured
% value is substituted into this evidence table.

arguments
    runFolder (1,1) string
    cfg (1,1) struct
    trialTable table
    generatePlot (1,1) logical = false
end

plotPath = "";
if ~logical(cfg.ntn.enabled)
    return;
end
if ~logical(cfg.ntn.output.enabled)
    error("sixgr:ntn:OutputDisabled", ...
        "Enabled NTN execution requires ntn.output.enabled=true.");
end

required = ["NTNEnabled","NTNProfile","NTNOrbitType", ...
    "NTNPayloadArchitecture","NTNSlantRangeM", ...
    "NTNPropagationDelaySeconds","NTNPropagationDelaySamples", ...
    "NTNPropagationDelayCompensationMode", ...
    "NTNPhysicalSatelliteDopplerHz","NTNMobileMaximumDopplerHz", ...
    "NTNDopplerCompensationMode","NTNDopplerCompensationHz", ...
    "NTNResidualSatelliteDopplerHz","NTNSampleRateHz","NTNGeometrySource"];
if ~all(ismember(required,string(trialTable.Properties.VariableNames))) || ...
        isempty(trialTable)
    error("sixgr:lls:MissingNTNRuntimeEvidence", ...
        "Enabled NTN execution did not produce the complete runtime evidence schema.");
end

state = unique(trialTable(:,cellstr(required)),"rows","stable");
if height(state) ~= 1
    error("sixgr:lls:InconsistentNTNRuntimeState", ...
        "A fixed NTN LLS run produced %d distinct runtime channel states.",height(state));
end
structured = logical(cfg.ntn.output.structuredComponentFolders);
csvDir = string(runFolder);
imageDir = string(runFolder);
if structured
    component = string(cfg.ntn.output.componentFolder);
    if ~isscalar(component) || isempty(regexp(char(component),'^[A-Za-z0-9_-]+$','once'))
        error("sixgr:ntn:InvalidComponentFolder", ...
            "ntn.output.componentFolder must be one safe relative folder name.");
    end
    csvDir = string(fullfile(runFolder,char(component),"csv"));
    imageDir = string(fullfile(runFolder,char(component),"image"));
end
if logical(cfg.ntn.output.saveCSV)
    sixgr.util.ensureFolder(char(csvDir));
    writetable(state,fullfile(csvDir,"ntn_channel_state.csv"));
end
if ~generatePlot || ~logical(cfg.ntn.output.savePNG)
    return;
end

sixgr.util.ensureFolder(char(imageDir));
format = lower(string(cfg.ntn.output.imageFormat));
if format == "jpeg"
    extension = ".jpeg";
else
    extension = ".png";
end
plotPath = string(fullfile(imageDir,"ntn_geometry_and_doppler"+extension));
fig = figure("Visible","off","Color","white","Position",[100 100 1120 620]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");

ax1 = nexttile(layout);
bar(ax1,[state.NTNSlantRangeM/1000, ...
    state.NTNPropagationDelaySeconds*1000],0.55);
set(ax1,"XTick",1:2,"XTickLabel",{"Slant range (km)","One-way delay (ms)"});
ylabel(ax1,"Measured geometry value");
title(ax1,"Runtime circular-orbit geometry");
grid(ax1,"on");

ax2 = nexttile(layout);
bar(ax2,[state.NTNPhysicalSatelliteDopplerHz, ...
    state.NTNDopplerCompensationHz,state.NTNResidualSatelliteDopplerHz, ...
    state.NTNMobileMaximumDopplerHz],0.55);
set(ax2,"XTick",1:4,"XTickLabel", ...
    {"Physical satellite","Compensation","Residual satellite","Mobile"});
ylabel(ax2,"Doppler shift (Hz)");
title(ax2,"Physical and residual Doppler");
grid(ax2,"on");
for ax = [ax1 ax2]
    set(ax,"Color","white","XColor",[0.1 0.1 0.1],"YColor",[0.1 0.1 0.1]);
end
title(layout,"Executed NTN-TDL/CDL waveform channel state");
exportgraphics(fig,plotPath,"Resolution",double(cfg.ntn.output.imageResolutionDPI));
end
