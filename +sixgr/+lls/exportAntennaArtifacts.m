function plotPaths = exportAntennaArtifacts(runFolder,cfg,trialTable,generatePlots)
%EXPORTANTENNAARTIFACTS Export only executed physical-array evidence.

arguments
    runFolder (1,:) char
    cfg (1,1) struct
    trialTable table
    generatePlots (1,1) logical
end

plotPaths = strings(0,1);
if ~logical(cfg.antenna.enabled)
    return;
end
if isempty(trialTable) || ~all(trialTable.AntennaEnabled) || ...
        ~all(trialTable.AntennaPhysicalElementChannelApplied)
    error("sixgr:lls:MissingAntennaRuntimeEvidence", ...
        "Enabled antenna artifacts require executed physical-element channel rows.");
end
state = sixgr.lls.resolveAntennaState(cfg);

configTable = localConfigTable(state);
elementTable = [localElementTable(state.Tx,true); ...
    localElementTable(state.Rx,false)];
runtimeTable = unique(trialTable(:,[ ...
    "ScenarioId","ChannelModel","AntennaEnabled","AntennaCouplingMode", ...
    "AntennaTxRole","AntennaRxRole","AntennaTxPhysicalElements", ...
    "AntennaRxPhysicalElements","AntennaTxLogicalPorts", ...
    "AntennaTxPortToElementSHA256","AntennaPatternSource", ...
    "AntennaPhysicalElementChannelApplied", ...
    "AntennaTransmitOrientationDeg","AntennaReceiveOrientationDeg"]),"rows");
[patternTable,rolePatterns] = localPatternTables(state);

writetable(configTable,fullfile(runFolder,"antenna_config_resolved.csv"));
writetable(elementTable,fullfile(runFolder,"antenna_array_elements.csv"));
writetable(patternTable,fullfile(runFolder,"antenna_pattern_samples.csv"));
writetable(runtimeTable,fullfile(runFolder,"antenna_runtime_evidence.csv"));
if ~generatePlots
    return;
end

roles = [state.TxRole state.RxRole];
states = {state.Tx,state.Rx};
for index = 1:2
    role = roles(index);
    roleState = states{index};
    array = sixgr.lls.buildAntennaArray(roleState);
    cleanup = onCleanup(@() release(array)); %#ok<NASGU>
    array.Taper = roleState.PortToElementMatrix(:,1);

    threeDPath = fullfile(runFolder,char(role + "_antenna_3d_directivity.png"));
    fig = figure("Visible","off","Color","white","Position",[100 100 1120 760]);
    cleanupFigure = onCleanup(@() localCloseFigure(fig)); %#ok<NASGU>
    pattern(array,roleState.FrequencyHz,-180:2:180,-90:2:90, ...
        "Type","directivity","CoordinateSystem","polar", ...
        "ShowArray",true,"ShowColorbar",true);
    title(sprintf("%s 3GPP TR 38.901 array directivity | %d elements", ...
        upper(char(role)),roleState.NumElements));
    localStyleFigure(fig);
    exportgraphics(fig,threeDPath,"Resolution",180);
    plotPaths(end+1,1) = string(threeDPath); %#ok<AGROW>
    close(fig);
    clear cleanupFigure;

    cutPath = fullfile(runFolder,char(role + "_antenna_azimuth_cut.png"));
    fig = figure("Visible","off","Color","white","Position",[100 100 920 720]);
    cleanupFigure = onCleanup(@() localCloseFigure(fig)); %#ok<NASGU>
    cut = rolePatterns{index};
    cut = sortrows(cut(cut.ElevationDeg == 0,:),"AzimuthDeg");
    peakDbi = max(cut.DirectivityDbi);
    floorDbi = 10*floor((peakDbi-40)/10);
    displayedDbi = max(cut.DirectivityDbi,floorDbi);
    radius = displayedDbi-floorDbi;
    polarAxis = polaraxes(fig);
    polarplot(polarAxis,deg2rad(cut.AzimuthDeg),radius, ...
        "LineWidth",2,"Color",[0.00 0.45 0.74]);
    polarAxis.ThetaZeroLocation = "right";
    polarAxis.ThetaDir = "counterclockwise";
    polarAxis.RLim = [0 max(10,ceil(max(radius)/10)*10)];
    radialTicks = 0:10:polarAxis.RLim(2);
    polarAxis.RTick = radialTicks;
    polarAxis.RTickLabel = compose("%.0f",floorDbi+radialTicks);
    polarAxis.FontSize = 12;
    title(polarAxis,sprintf("%s azimuth cut | elevation 0 deg",upper(char(role))));
    annotation(fig,"textbox",[0.2 0.015 0.6 0.05], ...
        "String",sprintf("Directivity (dBi) | peak %.2f dBi | floor %.0f dBi", ...
        peakDbi,floorDbi),"HorizontalAlignment","center", ...
        "EdgeColor","none","Color",[0.08 0.08 0.08],"FontSize",11);
    localStyleFigure(fig);
    exportgraphics(fig,cutPath,"Resolution",180);
    plotPaths(end+1,1) = string(cutPath); %#ok<AGROW>
    close(fig);
    clear cleanupFigure;
    clear cleanup;
end

geometryPath = fullfile(runFolder,"antenna_array_geometry.png");
fig = figure("Visible","off","Color","white","Position",[100 100 1200 620]);
cleanupFigure = onCleanup(@() localCloseFigure(fig)); %#ok<NASGU>
tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
for index = 1:2
    nexttile;
    roleState = states{index};
    p = roleState.ElementPositionsM ./ roleState.WavelengthM;
    scatter3(p(:,1),p(:,2),p(:,3),38,1:size(p,1),"filled");
    axis equal; grid on; view(35,25);
    xlabel("x / lambda"); ylabel("y / lambda"); zlabel("z / lambda");
    title(sprintf("%s physical array | %d elements", ...
        upper(char(roles(index))),roleState.NumElements));
end
sgtitle("Executed BS/UE antenna geometry");
localStyleFigure(fig);
exportgraphics(fig,geometryPath,"Resolution",180);
plotPaths(end+1,1) = string(geometryPath);

% Guard the image/CSV relationship: every plotted cut is sourced from the
% same numeric table generated above, not from a second hidden descriptor.
if height(patternTable) ~= sum(cellfun(@height,rolePatterns))
    error("sixgr:lls:AntennaArtifactRowMismatch", ...
        "Antenna pattern CSV rows do not match the plotted role tables.");
end
end

function tableOut = localConfigTable(state)
roles = [state.TxRole;state.RxRole];
values = {state.Tx;state.Rx};
rows = cell(2,1);
for index = 1:2
    value = values{index};
    rows{index} = struct( ...
        "Role",roles(index), ...
        "ExecutionSide",string(localSide(index)), ...
        "Model",value.Model, ...
        "Architecture",value.Architecture, ...
        "StandardReference",state.StandardReference, ...
        "CouplingMode",state.CouplingMode, ...
        "PointingMode",state.PointingMode, ...
        "PowerNormalization",state.PowerNormalization, ...
        "FrequencyHz",value.FrequencyHz, ...
        "WavelengthM",value.WavelengthM, ...
        "Size",string(mat2str(value.Size)), ...
        "ChannelArraySize",string(mat2str(value.ChannelArraySize)), ...
        "SpacingWavelength",string(mat2str(value.SpacingWavelength)), ...
        "ConfiguredOrientationDeg",string(mat2str(value.OrientationDeg)), ...
        "SteeringAzElDeg",string(mat2str(value.SteeringAzElDeg)), ...
        "PolarizationAnglesDeg",string(mat2str(value.PolarizationAnglesDeg)), ...
        "PolarizationModel",value.PolarizationModel, ...
        "NumElements",value.NumElements, ...
        "NumRFChains",value.NumRFChains, ...
        "NumLogicalPorts",value.NumLogicalPorts, ...
        "PortToElementSHA256",value.PortToElementSHA256, ...
        "PatternSource",value.PatternSource, ...
        "PatternAppliedBy",value.PatternAppliedBy);
end
tableOut = struct2table(vertcat(rows{:}));
end

function value = localSide(index)
if index == 1
    value = "transmitter";
else
    value = "receiver";
end
end

function tableOut = localElementTable(roleState,isTransmitter)
p = roleState.ElementPositionsM;
n = roleState.NumElements;
weights = roleState.PortToElementMatrix(:,1);
polarization = localPolarizationIndex(p,roleState.PolarizationAnglesDeg);
polarizationAngle = roleState.PolarizationAnglesDeg(polarization);
polarizationAngle = polarizationAngle(:);
tableOut = table;
tableOut.Role = repmat(string(roleState.Role),n,1);
tableOut.ElementIndex = (1:n).';
tableOut.X_m = p(:,1);
tableOut.Y_m = p(:,2);
tableOut.Z_m = p(:,3);
tableOut.PolarizationIndex = polarization(:);
tableOut.PolarizationAngleDeg = polarizationAngle(:);
tableOut.IsWaveformTransmitter = repmat(logical(isTransmitter),n,1);
tableOut.SteeringWeightReal = real(weights(:));
tableOut.SteeringWeightImag = imag(weights(:));
tableOut.SteeringWeightPower = abs(weights(:)).^2;
tableOut.PatternSource = repmat(string(roleState.PatternSource),n,1);
end

function index = localPolarizationIndex(positions,angles)
if numel(angles) == 1
    index = ones(size(positions,1),1);
    return;
end
[~,~,group] = unique(round(positions,12),"rows","stable");
index = ones(size(group));
for value = unique(group).'
    rows = find(group == value);
    if numel(rows) ~= numel(angles)
        error("sixgr:lls:AntennaPolarizationGeometryMismatch", ...
            "Co-located element group has %d entries for %d polarizations.", ...
            numel(rows),numel(angles));
    end
    index(rows) = (1:numel(rows)).';
end
end

function [tableOut,roleTables] = localPatternTables(state)
roles = [state.TxRole state.RxRole];
values = {state.Tx,state.Rx};
roleTables = cell(2,1);
az = -180:2:180;
el = -90:2:90;
for index = 1:2
    roleState = values{index};
    array = sixgr.lls.buildAntennaArray(roleState);
    cleanup = onCleanup(@() release(array)); %#ok<NASGU>
    array.Taper = roleState.PortToElementMatrix(:,1);
    patternValues = pattern(array,roleState.FrequencyHz,az,el, ...
        "Type","directivity","CoordinateSystem","rectangular");
    if isequal(size(patternValues),[numel(el) numel(az)])
        [azGrid,elGrid] = meshgrid(az,el);
    elseif isequal(size(patternValues),[numel(az) numel(el)])
        [elGrid,azGrid] = meshgrid(el,az);
    else
        error("sixgr:lls:UnexpectedAntennaPatternSize", ...
            "%s pattern has size %s.",upper(char(roles(index))), ...
            mat2str(size(patternValues)));
    end
    rowCount = numel(patternValues);
    roleTable = table;
    roleTable.Role = repmat(string(roles(index)),rowCount,1);
    roleTable.AzimuthDeg = azGrid(:);
    roleTable.ElevationDeg = elGrid(:);
    roleTable.DirectivityDbi = double(patternValues(:));
    roleTable.PortToElementSHA256 = repmat( ...
        string(roleState.PortToElementSHA256),rowCount,1);
    roleTables{index} = roleTable;
end
tableOut = vertcat(roleTables{:});
end

function localCloseFigure(fig)
if isgraphics(fig)
    close(fig);
end
end

function localStyleFigure(fig)
set(fig,"Color","white");
axesObjects = findall(fig,"Type","axes");
for index = 1:numel(axesObjects)
    set(axesObjects(index),"Color","white", ...
        "XColor",[0.12 0.12 0.12],"YColor",[0.12 0.12 0.12], ...
        "ZColor",[0.12 0.12 0.12],"GridColor",[0.35 0.35 0.35]);
end
polarObjects = findall(fig,"Type","polaraxes");
for index = 1:numel(polarObjects)
    set(polarObjects(index),"Color","white", ...
        "ThetaColor",[0.12 0.12 0.12],"RColor",[0.12 0.12 0.12], ...
        "GridColor",[0.45 0.45 0.45]);
end
textObjects = findall(fig,"Type","text");
for index = 1:numel(textObjects)
    set(textObjects(index),"Color",[0.08 0.08 0.08]);
end
colorbars = findall(fig,"Type","ColorBar");
for index = 1:numel(colorbars)
    set(colorbars(index),"Color",[0.12 0.12 0.12]);
end
end
