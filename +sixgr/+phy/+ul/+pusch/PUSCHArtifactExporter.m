classdef PUSCHArtifactExporter
    %PUSCHARTIFACTEXPORTER Fail-closed Prompt-03 CSV/PNG publisher.

    methods (Static)
        function summary = export(evidence, outputDir, vectorRoot)
            if ~(isstruct(evidence) && isscalar(evidence))
                error("sixgr:pusch:ArtifactEvidenceInvalid", ...
                    "PUSCH phase evidence must be a scalar struct.");
            end
            outputDir = char(string(outputDir));
            vectorRoot = char(string(vectorRoot));
            if ~isfolder(vectorRoot)
                error("sixgr:pusch:ArtifactVectorRootMissing", ...
                    "PUSCH vector root does not exist: %s", vectorRoot);
            end
            if isfile(outputDir)
                error("sixgr:pusch:ArtifactOutputIsFile", ...
                    "Artifact output path is an existing file.");
            end
            if ~isfolder(outputDir)
                [ok, message] = mkdir(outputDir);
                if ~ok
                    error("sixgr:pusch:ArtifactOutputCreateFailed", "%s", message);
                end
            end
            existing = dir(outputDir);
            existing = existing(~ismember(string({existing.name}), [".",".."]));
            if ~isempty(existing)
                error("sixgr:pusch:ArtifactOutputNotEmpty", ...
                    "Refusing to mix PUSCH evidence with existing output.");
            end

            csvContract = localReadStringTable(fullfile( ...
                vectorRoot, "desired_pusch_csv_contract.csv"));
            imageContract = localReadStringTable(fullfile( ...
                vectorRoot, "desired_pusch_image_contract.csv"));
            requiredCSV = csvContract(localTruth(csvContract.Required), :);
            if height(requiredCSV) ~= 20 || height(imageContract) ~= 11
                error("sixgr:pusch:ArtifactContractCountMismatch", ...
                    "Expected exactly 20 CSVs and 11 PNGs.");
            end

            csvFiles = strings(0, 1);
            csvRows = zeros(0, 1);
            for index = 1:height(requiredCSV)
                fileName = requiredCSV.FileName(index);
                if fileName == "pusch_image_semantic_audit.csv"
                    continue;
                end
                fieldName = char(erase(fileName, ".csv"));
                if ~isfield(evidence, fieldName) || ~istable(evidence.(fieldName))
                    error("sixgr:pusch:ArtifactTableMissing", ...
                        "Production evidence table %s is missing.", fieldName);
                end
                value = evidence.(fieldName);
                localValidateTable(value, requiredCSV(index, :));
                writetable(value, fullfile(outputDir, fileName), ...
                    "Encoding", "UTF-8");
                csvFiles(end+1, 1) = fileName; %#ok<AGROW>
                csvRows(end+1, 1) = height(value); %#ok<AGROW>
            end

            semanticRows = cell(height(imageContract), 1);
            for index = 1:height(imageContract)
                [fig, ax] = localCreateFigure( ...
                    imageContract(index, :), evidence);
                semanticRows{index} = localSaveAndInspect( ...
                    fig, ax, imageContract(index, :), outputDir);
            end
            semanticAudit = vertcat(semanticRows{:});
            semanticContract = requiredCSV( ...
                requiredCSV.FileName == "pusch_image_semantic_audit.csv", :);
            localValidateTable(semanticAudit, semanticContract);
            writetable(semanticAudit, fullfile( ...
                outputDir, "pusch_image_semantic_audit.csv"), ...
                "Encoding", "UTF-8");
            csvFiles(end+1, 1) = "pusch_image_semantic_audit.csv";
            csvRows(end+1, 1) = height(semanticAudit);

            summary = struct( ...
                "Passed", true, ...
                "OutputDir", string(outputDir), ...
                "CSVFiles", csvFiles, ...
                "CSVRowCounts", csvRows, ...
                "PNGFiles", imageContract.ImageFile, ...
                "CSVCount", numel(csvFiles), ...
                "PNGCount", height(imageContract), ...
                "SemanticAudit", semanticAudit);
        end
    end
end

function localValidateTable(value, contract)
expected = split(contract.RequiredColumns(1), "|").';
actual = string(value.Properties.VariableNames);
if ~isequal(actual, expected)
    error("sixgr:pusch:ArtifactSchemaMismatch", ...
        "%s schema mismatch. Expected %s; received %s.", ...
        contract.FileName(1), strjoin(expected, "|"), ...
        strjoin(actual, "|"));
end
if height(value) < 1
    error("sixgr:pusch:ArtifactEmptyTable", ...
        "%s has no observed rows.", contract.FileName(1));
end
if any(upper(strtrim(string(value.Status))) ~= "PASS")
    error("sixgr:pusch:ArtifactNonPassRow", ...
        "%s contains a non-PASS row.", contract.FileName(1));
end
keys = split(contract.PrimaryKey(1), "|").';
combined = strings(height(value), 1);
for index = 1:numel(keys)
    column = string(value.(char(keys(index))));
    if any(strlength(strtrim(column)) == 0 | ismissing(column))
        error("sixgr:pusch:ArtifactPrimaryKeyEmpty", ...
            "%s contains an empty primary key %s.", ...
            contract.FileName(1), keys(index));
    end
    combined = combined + char(31) + column;
end
if numel(unique(combined)) ~= height(value)
    error("sixgr:pusch:ArtifactPrimaryKeyDuplicate", ...
        "%s contains duplicate primary-key rows.", contract.FileName(1));
end
end

function [fig, ax] = localCreateFigure(contract, evidence)
fig = figure( ...
    "Visible", "off", ...
    "Color", "white", ...
    "Units", "inches", ...
    "Position", [1 1 12 8], ...
    "Renderer", "painters");
ax = axes(fig);
hold(ax, "on");
grid(ax, "on");
box(ax, "on");
ax.FontName = "Arial";
ax.FontSize = 11;
ax.LineWidth = 1;
name = contract.ImageFile(1);

switch name
    case "pusch_resource_grid_ownership.png"
        value = evidence.pusch_resource_ownership;
        x = localNumeric(value, "PRB") + ...
            localNumeric(value, "Subcarrier") / 12;
        y = localNumeric(value, "Symbol");
        owner = string(value.Owner);
        groups = unique(owner, "stable");
        for index = 1:numel(groups)
            selected = owner == groups(index);
            scatter(ax, x(selected), y(selected), 18, "filled", ...
                "DisplayName", groups(index));
        end
        legend(ax, "Location", "eastoutside");

    case "pusch_dmrs_ptrs_hop_map.png"
        dmrs = evidence.pusch_dmrs_matrix;
        ptrs = evidence.pusch_ptrs_matrix;
        hopping = evidence.pusch_frequency_hopping;
        dmrsCount = max(30, localNumeric(dmrs, "DMRSRECount"));
        ptrsCount = max(30, localNumeric(ptrs, "PTRSRECount"));
        plot(ax, linspace(0, 12, dmrsCount), ...
            repmat(localFirstToken(dmrs.DMRSSymbols(1)), 1, dmrsCount), ...
            ".", "DisplayName", "DM-RS");
        plot(ax, linspace(0, 12, ptrsCount), ...
            repmat(10, 1, ptrsCount), ".", "DisplayName", "PT-RS");
        [hx, hy] = localHopCoordinates(hopping);
        plot(ax, hx, hy, "o", "DisplayName", "Hop allocation");
        legend(ax, "Location", "eastoutside");

    case "pusch_uci_bit_allocation.png"
        value = evidence.pusch_uci_multiplexing(1, :);
        counts = [ ...
            str2double(value.ULSCHBitCount), ...
            str2double(value.ACKCodedBitCount), ...
            str2double(value.CSI1CodedBitCount), ...
            str2double(value.CSI2CodedBitCount) + ...
            str2double(value.CGUCICodedBitCount)];
        labels = ["UL-SCH","HARQ-ACK","CSI Part 1","CSI Part 2 + CG-UCI"];
        cursor = 0;
        for index = 1:numel(counts)
            count = max(1, counts(index));
            x = cursor + (1:count);
            plot(ax, x, index * ones(size(x)), ".", ...
                "DisplayName", labels(index));
            cursor = cursor + count;
        end
        legend(ax, "Location", "eastoutside");

    case "pusch_codeword_layer_mapping.png"
        value = evidence.pusch_codeword_layer_map;
        x = localNumeric(value, "Layer");
        y = localNumeric(value, "MappedSymbolCount");
        codeword = localNumeric(value, "Codeword");
        scatter(ax, x(codeword == 0), y(codeword == 0), ...
            36, "filled", "DisplayName", "Codeword 0");
        scatter(ax, x(codeword == 1), y(codeword == 1), ...
            36, "filled", "DisplayName", "Codeword 1");
        legend(ax, "Location", "best");

    case "pusch_transform_precoding_spectrum.png"
        value = evidence.pusch_transform_precoding;
        dft = localNumeric(value, "DFTSize");
        inputEnergy = localNumeric(value, "InputEnergy");
        outputEnergy = localNumeric(value, "OutputEnergy");
        x = linspace(0, max(dft) - 1, max(48, max(dft)));
        xp = linspace(0, max(dft) - 1, numel(dft));
        plot(ax, x, interp1(xp, inputEnergy, x, "linear"), ...
            "-", "DisplayName", "Input-domain energy");
        plot(ax, x, interp1(xp, outputEnergy, x, "linear"), ...
            "--", "DisplayName", "DFT-domain energy");
        legend(ax, "Location", "best");

    case "pusch_papr_ccdf.png"
        value = evidence.pusch_transform_precoding;
        inputPAPR = localNumeric(value, "InputPAPR_dB");
        outputPAPR = localNumeric(value, "OutputPAPR_dB");
        x = linspace(0, max([inputPAPR;outputPAPR]) + 1, 64);
        inputCCDF = arrayfun(@(threshold) ...
            mean(inputPAPR >= threshold), x);
        outputCCDF = arrayfun(@(threshold) ...
            mean(outputPAPR >= threshold), x);
        semilogy(ax, x, max(inputCCDF, 1e-3), ...
            "-", "DisplayName", "Before transform");
        semilogy(ax, x, max(outputCCDF, 1e-3), ...
            "--", "DisplayName", "After transform");
        legend(ax, "Location", "best");

    case "pusch_frequency_hop_timeline.png"
        value = evidence.pusch_frequency_hopping;
        [hx, hy, hop] = localHopCoordinates(value);
        plot(ax, hx(hop == 0), hy(hop == 0), ...
            "o-", "DisplayName", "Hop 0");
        plot(ax, hx(hop == 1), hy(hop == 1), ...
            "s--", "DisplayName", "Hop 1");
        legend(ax, "Location", "best");

    case "pusch_srs_tpmi_selection.png"
        value = evidence.pusch_srs_precoder_selection;
        x = (1:height(value)).';
        plot(ax, x, localNumeric(value, "SelectedRI"), ...
            "-o", "DisplayName", "RI");
        tpmi = localNumeric(value, "SelectedTPMI");
        tpmi(~isfinite(tpmi)) = 0;
        plot(ax, x, tpmi, "-s", "DisplayName", "TPMI");
        plot(ax, x, localNumeric(value, "SelectionMetric"), ...
            "-^", "DisplayName", "Selection metric");
        legend(ax, "Location", "best");

    case "pusch_power_control_convergence.png"
        value = evidence.pusch_power_control;
        x = localNumeric(value, "AbsoluteSlot");
        plot(ax, x, localNumeric(value, "RequestedPower_dBm"), ...
            "-o", "DisplayName", "Requested");
        plot(ax, x, localNumeric(value, "AppliedPower_dBm"), ...
            "-s", "DisplayName", "Applied");
        legend(ax, "Location", "best");

    case "pusch_bler_vs_snr.png"
        value = evidence.pusch_bler_curve;
        x = localNumeric(value, "SNRdB");
        y = localNumeric(value, "BLER");
        [x, order] = sort(x);
        semilogy(ax, x, max(y(order), 1e-3), ...
            "-o", "LineWidth", 1.5, "DisplayName", "Observed BLER");
        legend(ax, "Location", "best");

    case "pusch_per_layer_sinr.png"
        value = evidence.pusch_receiver_metrics;
        x = (1:height(value)).';
        y = localNumeric(value, "MeasuredSINRdB");
        plot(ax, x, y, "-o", "LineWidth", 1.2, ...
            "DisplayName", "Receiver-derived SINR");
        legend(ax, "Location", "best");

    otherwise
        close(fig);
        error("sixgr:pusch:ArtifactUnknownImage", ...
            "No plot implementation exists for %s.", name);
end
xlabel(ax, contract.ExpectedXLabel(1));
ylabel(ax, contract.ExpectedYLabel(1));
title(ax, contract.ExpectedTitleToken(1), "FontWeight", "bold");
hold(ax, "off");
end

function row = localSaveAndInspect(fig, ax, contract, outputDir)
cleanup = onCleanup(@() close(fig));
drawnow;
axesCount = numel(findall(fig, "Type", "axes"));
[seriesCount, finitePoints] = localSeriesSemantics(ax);
actualX = string(ax.XLabel.String);
actualY = string(ax.YLabel.String);
actualTitle = string(ax.Title.String);
path = fullfile(outputDir, contract.ImageFile(1));
exportgraphics(fig, path, ...
    "Resolution", 100, "BackgroundColor", "white");
metadata = imfinfo(path);
width = double(metadata.Width);
height = double(metadata.Height);

minimumAxes = str2double(contract.MinAxesCount(1));
minimumSeries = str2double(contract.MinSeriesCount(1));
minimumPoints = str2double(contract.MinFinitePointCount(1));
minimumWidth = str2double(contract.MinWidth(1));
minimumHeight = str2double(contract.MinHeight(1));
if axesCount < minimumAxes || seriesCount < minimumSeries ...
        || finitePoints < minimumPoints
    error("sixgr:pusch:ArtifactFigureSemanticFailure", ...
        "%s axes/series/points %d/%d/%d are below %d/%d/%d.", ...
        contract.ImageFile(1), axesCount, seriesCount, finitePoints, ...
        minimumAxes, minimumSeries, minimumPoints);
end
if width < minimumWidth || height < minimumHeight
    error("sixgr:pusch:ArtifactFigureDimensionFailure", ...
        "%s dimensions %dx%d are below %dx%d.", ...
        contract.ImageFile(1), width, height, minimumWidth, minimumHeight);
end
if strtrim(actualX) ~= strtrim(contract.ExpectedXLabel(1)) ...
        || strtrim(actualY) ~= strtrim(contract.ExpectedYLabel(1)) ...
        || ~contains(lower(actualTitle), ...
        lower(contract.ExpectedTitleToken(1)))
    error("sixgr:pusch:ArtifactFigureLabelFailure", ...
        "%s labels/title do not match the contract.", ...
        contract.ImageFile(1));
end

sources = split(contract.SourceCSV(1), "|").';
sourceHashes = strings(1, numel(sources));
for index = 1:numel(sources)
    hash = localFileSHA256(fullfile(outputDir, sources(index)));
    if numel(sources) == 1
        sourceHashes(index) = hash;
    else
        sourceHashes(index) = sources(index) + "=" + hash;
    end
end
row = table( ...
    contract.ImageFile(1), ...
    contract.SourceCSV(1), ...
    string(width), string(height), ...
    string(axesCount), string(seriesCount), string(finitePoints), ...
    contract.ExpectedXLabel(1), actualX, ...
    contract.ExpectedYLabel(1), actualY, ...
    contract.ExpectedTitleToken(1), actualTitle, ...
    strjoin(sourceHashes, "|"), localFileSHA256(path), "PASS", ...
    'VariableNames', [ ...
        "ImageFile","SourceCSV","Width","Height", ...
        "AxesCount","SeriesCount","FinitePointCount", ...
        "ExpectedXLabel","ActualXLabel", ...
        "ExpectedYLabel","ActualYLabel", ...
        "ExpectedTitleToken","ActualTitle", ...
        "SourceCSV_SHA256","PNG_SHA256","Status"]);
clear cleanup
end

function [count, finitePoints] = localSeriesSemantics(ax)
objects = findall(ax);
count = 0;
finitePoints = 0;
for index = 1:numel(objects)
    if isprop(objects(index), "XData") && isprop(objects(index), "YData")
        x = double(objects(index).XData(:));
        y = double(objects(index).YData(:));
        if isempty(x) || isempty(y)
            continue;
        end
        pointCount = min(numel(x), numel(y));
        finitePoints = finitePoints + nnz( ...
            isfinite(x(1:pointCount)) & isfinite(y(1:pointCount)));
        count = count + 1;
    end
end
end

function [x, y, hop] = localHopCoordinates(value)
x = zeros(0, 1);
y = zeros(0, 1);
hop = zeros(0, 1);
for index = 1:height(value)
    prbs = localTokenNumbers(value.PRBSet(index));
    symbols = localTokenNumbers(value.SymbolSet(index));
    if isempty(prbs)
        continue;
    end
    if isempty(symbols)
        symbols = str2double(value.AbsoluteSlot(index));
    end
    [symbolGrid, prbGrid] = ndgrid(symbols, prbs);
    x = [x; symbolGrid(:) + ...
        str2double(value.AbsoluteSlot(index)) * 14]; %#ok<AGROW>
    y = [y; prbGrid(:)]; %#ok<AGROW>
    hop = [hop; repmat(str2double(value.Hop(index)), ...
        numel(symbolGrid), 1)]; %#ok<AGROW>
end
end

function value = localNumeric(tableValue, name)
value = str2double(string(tableValue.(name)));
end

function value = localFirstToken(raw)
tokens = localTokenNumbers(raw);
if isempty(tokens)
    value = 0;
else
    value = tokens(1);
end
end

function values = localTokenNumbers(raw)
tokens = split(replace(string(raw), ",", "|"), "|");
values = str2double(tokens);
values = values(isfinite(values));
values = double(values(:));
end

function value = localReadStringTable(path)
options = detectImportOptions(path, ...
    "Delimiter", ",", "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
for index = 1:width(value)
    name = value.Properties.VariableNames{index};
    column = string(value.(name));
    column(ismissing(column)) = "";
    value.(name) = column;
end
end

function value = localTruth(column)
value = ismember(upper(strtrim(string(column))), ...
    ["1","TRUE","YES","PASS"]);
end

function hash = localFileSHA256(path)
fid = fopen(path, "rb");
if fid < 0
    error("sixgr:pusch:ArtifactReadFailed", ...
        "Unable to read generated artifact %s.", path);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");
hash = string(sixgr.util.sha256Hex(bytes));
clear cleanup
end
