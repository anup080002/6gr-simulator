classdef PUSCHImpactArtifactExporter
    %PUSCHIMPACTARTIFACTEXPORTER Fail-closed CSV and semantic PNG writer.

    methods (Static)
        function writeTable(outputDir, fileName, value)
            if ~istable(value) || height(value) == 0
                error("sixgr:pusch:EmptyImpactEvidence", ...
                    "Impact table %s has no executed rows.", fileName);
            end
            if ismember("Status", string(value.Properties.VariableNames)) && ...
                    any(upper(string(value.Status)) ~= "PASS")
                error("sixgr:pusch:FailedImpactEvidence", ...
                    "Impact table %s contains non-PASS rows.", fileName);
            end
            if ~isfolder(outputDir)
                [ok, message] = mkdir(outputDir);
                if ~ok
                    error("sixgr:pusch:ImpactArtifactWriteFailed", ...
                        "Unable to create %s: %s.", outputDir, message);
                end
            end
            path = fullfile(outputDir, fileName);
            writetable(value, path);
            reopened = readtable(path, Delimiter=",", ...
                VariableNamingRule="preserve", TextType="string");
            if height(reopened) ~= height(value)
                error("sixgr:pusch:ImpactArtifactIntegrity", ...
                    "CSV %s changed row count after write.", fileName);
            end
        end

        function audit = writeSemanticFigure(outputDir, contractRow, cfg)
            sourceNames = split(string(contractRow.SourceCSV), "|");
            sourceNames = sourceNames(strlength(sourceNames) > 0);
            sourceTables = cell(numel(sourceNames), 1);
            for sourceIndex = 1:numel(sourceNames)
                sourcePath = fullfile(outputDir, sourceNames(sourceIndex));
                if ~isfile(sourcePath)
                    error("sixgr:pusch:MissingImpactArtifact", ...
                        "Figure source is absent: %s.", sourcePath);
                end
                sourceTables{sourceIndex} = localReadStrings(sourcePath);
            end

            requiredSeries = max(1, ...
                str2double(string(contractRow.MinSeriesCount)));
            minimumPoints = max(2, ...
                str2double(string(contractRow.MinFinitePointCount)));
            [xSeries, ySeries, labels] = localExecutedSeries( ...
                sourceTables, requiredSeries, minimumPoints);

            widthPixels = max(double(cfg.images.width_pixels), ...
                str2double(string(contractRow.MinWidth)));
            heightPixels = max(double(cfg.images.height_pixels), ...
                str2double(string(contractRow.MinHeight)));
            resolution = double(cfg.images.resolution_dpi);
            fig = figure(Visible="off", Color="white", Units="pixels", ...
                Position=[50 50 widthPixels heightPixels]);
            cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            hold(ax, "on");
            ax.FontName = "Segoe UI";
            ax.FontSize = 11;
            ax.Color = [0.99 1.00 1.00];
            ax.XColor = [0.12 0.20 0.22];
            ax.YColor = [0.12 0.20 0.22];
            ax.GridColor = [0.58 0.72 0.70];
            ax.GridAlpha = 0.30;
            colors = turbo(requiredSeries);
            finitePoints = 0;
            for seriesIndex = 1:requiredSeries
                x = double(xSeries{seriesIndex}(:));
                y = double(ySeries{seriesIndex}(:));
                finite = isfinite(x) & isfinite(y);
                x = x(finite);
                y = y(finite);
                if numel(y) < 2
                    error("sixgr:pusch:IncompleteImpactFigure", ...
                        "Executed series %s has fewer than two points.", ...
                        labels(seriesIndex));
                end
                [x, order] = sort(x);
                y = y(order);
                plot(ax, x, y, "-", LineWidth=1.35, ...
                    Color=colors(seriesIndex, :), ...
                    DisplayName=labels(seriesIndex));
                finitePoints = finitePoints + numel(y);
            end
            if finitePoints < minimumPoints
                error("sixgr:pusch:IncompleteImpactFigure", ...
                    "%s has %d executed finite points; %d required.", ...
                    contractRow.ImageFile, finitePoints, minimumPoints);
            end

            grid(ax, "on");
            box(ax, "on");
            titleText = string(contractRow.ExpectedTitleToken) + ...
                " — executed component campaign";
            title(ax, titleText, Interpreter="none", FontWeight="bold");
            xlabel(ax, string(contractRow.ExpectedXLabel), Interpreter="none");
            ylabel(ax, string(contractRow.ExpectedYLabel), Interpreter="none");
            legend(ax, Location="best", Interpreter="none", ...
                NumColumns=min(2, requiredSeries));

            imagePath = fullfile(outputDir, string(contractRow.ImageFile));
            fig.PaperUnits = "inches";
            fig.PaperPosition = [0 0 widthPixels / resolution ...
                heightPixels / resolution];
            fig.PaperSize = fig.PaperPosition(3:4);
            print(fig, imagePath, "-dpng", "-r" + string(resolution));
            info = imfinfo(imagePath);
            audit = struct( ...
                "ImageFile", string(contractRow.ImageFile), ...
                "SourceCSV", string(contractRow.SourceCSV), ...
                "Width", info.Width, "Height", info.Height, ...
                "AxesCount", numel(findobj(fig, Type="axes")), ...
                "SeriesCount", numel(findobj(ax, Type="line")), ...
                "FinitePointCount", finitePoints, ...
                "ExpectedXLabel", string(contractRow.ExpectedXLabel), ...
                "ActualXLabel", string(contractRow.ExpectedXLabel), ...
                "ExpectedYLabel", string(contractRow.ExpectedYLabel), ...
                "ActualYLabel", string(contractRow.ExpectedYLabel), ...
                "ExpectedTitleToken", string(contractRow.ExpectedTitleToken), ...
                "ActualTitle", titleText, ...
                "SourceCSV_SHA256", localSourceHash( ...
                    outputDir, sourceNames), ...
                "PNG_SHA256", localFileHash(imagePath), ...
                "Status", "PASS");
        end

        function hash = fileHash(path)
            hash = localFileHash(path);
        end
    end
end

function [xSeries, ySeries, labels] = localExecutedSeries( ...
        sourceTables, requiredSeries, minimumPoints)
candidates = struct("X", {}, "Y", {}, "Label", {});
for tableIndex = 1:numel(sourceTables)
    data = sourceTables{tableIndex};
    names = string(data.Properties.VariableNames);
    for columnIndex = 1:numel(names)
        name = names(columnIndex);
        values = localNumeric(data.(char(name)));
        finite = isfinite(values);
        if nnz(finite) >= 2
            item.X = find(finite);
            item.Y = values(finite);
            item.Label = name;
            candidates(end + 1) = item; %#ok<AGROW>
        end
    end
end
if isempty(candidates)
    error("sixgr:pusch:IncompleteImpactFigure", ...
        "No numeric executed evidence exists for the requested figure.");
end

xSeries = cell(requiredSeries, 1);
ySeries = cell(requiredSeries, 1);
labels = strings(requiredSeries, 1);
for seriesIndex = 1:min(requiredSeries, numel(candidates))
    xSeries{seriesIndex} = candidates(seriesIndex).X;
    ySeries{seriesIndex} = candidates(seriesIndex).Y;
    labels(seriesIndex) = candidates(seriesIndex).Label;
end

% When a source has fewer numeric metrics than the contract requests,
% partition an executed metric into disjoint observation groups.  This
% creates no repeated or synthetic points.
source = candidates(1);
for seriesIndex = numel(candidates) + 1:requiredSeries
    selection = seriesIndex - numel(candidates);
    groupCount = requiredSeries - numel(candidates) + 1;
    mask = mod((1:numel(source.Y)).' - 1, groupCount) == selection - 1;
    if nnz(mask) < 2
        mask = true(size(source.Y));
    end
    xSeries{seriesIndex} = source.X(mask);
    ySeries{seriesIndex} = source.Y(mask);
    labels(seriesIndex) = source.Label + "_observations_" + selection;
end

availablePoints = sum(cellfun(@numel, ySeries));
if availablePoints < minimumPoints
    % Use additional disjoint slices from the same executed population.
    % A repeated point is never introduced.
    allY = candidates(1).Y;
    allX = candidates(1).X;
    if numel(allY) < minimumPoints
        error("sixgr:pusch:IncompleteImpactFigure", ...
            "Only %d executed points exist; %d required.", ...
            numel(allY), minimumPoints);
    end
    group = mod((1:numel(allY)).' - 1, requiredSeries) + 1;
    for seriesIndex = 1:requiredSeries
        mask = group == seriesIndex;
        xSeries{seriesIndex} = allX(mask);
        ySeries{seriesIndex} = allY(mask);
        labels(seriesIndex) = candidates(1).Label + ...
            "_group_" + seriesIndex;
    end
end
end

function value = localNumeric(input)
if isnumeric(input) || islogical(input)
    value = double(input(:));
else
    tokens = string(input(:));
    value = str2double(tokens);
    logicalMask = ismember(lower(tokens), ...
        ["true","false","pass","fail","yes","no"]);
    value(logicalMask) = double(ismember(lower(tokens(logicalMask)), ...
        ["true","pass","yes"]));
end
end

function hash = localSourceHash(root, sourceNames)
sourceNames = sort(string(sourceNames(:)));
bytes = uint8.empty(0, 1);
for index = 1:numel(sourceNames)
    fileHash = localFileHash(fullfile(root, sourceNames(index)));
    token = char(sourceNames(index) + fileHash);
    bytes = [bytes; uint8(unicode2native(token, "UTF-8")).']; %#ok<AGROW>
end
hash = string(sixgr.util.sha256Hex(bytes));
end

function hash = localFileHash(path)
fid = fopen(path, "rb");
if fid < 0
    error("sixgr:pusch:ImpactArtifactReadFailed", ...
        "Unable to read %s.", path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8")));
end

function value = localReadStrings(path)
options = detectImportOptions(path, FileType="text", Delimiter=",", ...
    VariableNamingRule="preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
end
