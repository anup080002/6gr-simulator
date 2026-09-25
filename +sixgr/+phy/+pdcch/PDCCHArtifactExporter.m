classdef PDCCHArtifactExporter
    %PDCCHARTIFACTEXPORTER Deterministic, hash-bound Phase-04 evidence writer.

    methods (Static)
        function writeTable(outputDir, fileName, value)
            if ~istable(value) || height(value) == 0
                error("sixgr:phy:pdcch:empty_evidence", ...
                    "Evidence table %s must contain production rows.", fileName);
            end
            if ~isfolder(outputDir)
                mkdir(outputDir);
            end
            writetable(value, fullfile(outputDir, fileName));
        end

        function audit = writeSemanticFigure(outputDir, contractRow)
            sourceNames = split(string(contractRow.SourceCSV), "|");
            sourceNames = sourceNames(strlength(sourceNames) > 0);
            sourceTables = cell(numel(sourceNames),1);
            for ii = 1:numel(sourceNames)
                sourcePath = fullfile(outputDir, sourceNames(ii));
                if exist(sourcePath, "file") ~= 2
                    error("sixgr:phy:pdcch:missing_evidence_source", ...
                        "Figure source CSV is absent: %s.", sourcePath);
                end
                sourceTables{ii} = readtable(sourcePath, ...
                    "VariableNamingRule", "preserve", "TextType", "string");
            end

            width = max(double(contractRow.MinWidth), 1200);
            heightPixels = max(double(contractRow.MinHeight), 760);

            figureHandle = figure("Visible", "off", "Color", "white", ...
                "Units", "pixels", "Position", [50 50 width heightPixels]);
            cleanup = onCleanup(@() close(figureHandle));
            axesHandle = axes(figureHandle);
            hold(axesHandle, "on");
            sixgr.phy.pdcch.plotArtifactEvidence(axesHandle, ...
                string(contractRow.ImageFile),sourceNames,sourceTables);
            grid(axesHandle, "on");
            box(axesHandle, "on");
            titleText = string(contractRow.ExpectedTitleToken) + " — CSV evidence";
            title(axesHandle, titleText, "Interpreter", "none", "Color", "black");
            xlabel(axesHandle, string(contractRow.ExpectedXLabel), "Interpreter", "none");
            ylabel(axesHandle, string(contractRow.ExpectedYLabel), "Interpreter", "none");
            legend(axesHandle, "Location", "eastoutside", "Interpreter", "none", ...
                "Color", "white", "TextColor", "black");

            lineObjects = findobj(axesHandle, "Type", "line");
            finitePoints = 0;
            for ii = 1:numel(lineObjects)
                xData = double(lineObjects(ii).XData);
                yData = double(lineObjects(ii).YData);
                finitePoints = finitePoints + sum(isfinite(xData) & isfinite(yData));
            end
            axesCount = numel(findobj(figureHandle, "Type", "axes"));
            actualSeriesCount = numel(lineObjects);
            actualTitle = string(axesHandle.Title.String);
            actualXLabel = string(axesHandle.XLabel.String);
            actualYLabel = string(axesHandle.YLabel.String);
            if axesCount < double(contractRow.MinAxesCount) || ...
                    actualSeriesCount < double(contractRow.MinSeriesCount) || ...
                    finitePoints < double(contractRow.MinFinitePointCount)
                error("sixgr:phy:pdcch:incomplete_figure_semantics", ...
                    "Figure %s does not meet its semantic contract.", contractRow.ImageFile);
            end

            imagePath = fullfile(outputDir, string(contractRow.ImageFile));
            figureHandle.PaperUnits = "inches";
            figureHandle.PaperPosition = [0 0 width/100 heightPixels/100];
            figureHandle.PaperSize = [width/100 heightPixels/100];
            print(figureHandle, imagePath, "-dpng", "-r100");
            info = imfinfo(imagePath);
            if info.Width < double(contractRow.MinWidth) || ...
                    info.Height < double(contractRow.MinHeight)
                error("sixgr:phy:pdcch:incomplete_figure_semantics", ...
                    "Figure %s was exported at %dx%d.", ...
                    contractRow.ImageFile, info.Width, info.Height);
            end

            audit = struct( ...
                "ImageFile", string(contractRow.ImageFile), ...
                "SourceCSV", string(contractRow.SourceCSV), ...
                "Width", info.Width, ...
                "Height", info.Height, ...
                "AxesCount", axesCount, ...
                "SeriesCount", actualSeriesCount, ...
                "FinitePointCount", finitePoints, ...
                "ExpectedTitleToken", string(contractRow.ExpectedTitleToken), ...
                "ActualTitle", actualTitle, ...
                "ExpectedXLabel", string(contractRow.ExpectedXLabel), ...
                "ActualXLabel", actualXLabel, ...
                "ExpectedYLabel", string(contractRow.ExpectedYLabel), ...
                "ActualYLabel", actualYLabel, ...
                "SourceCSV_SHA256", sixgr.phy.pdcch.PDCCHArtifactExporter.sourceSHA256( ...
                    outputDir, sourceNames), ...
                "PNG_SHA256", sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256(imagePath), ...
                "Status", "PASS");
        end

        function value = sourceSHA256(outputDir, sourceNames)
            sourceNames = sort(string(sourceNames(:)));
            payload = zeros(0, 1, "uint8");
            for ii = 1:numel(sourceNames)
                nameBytes = unicode2native(char(sourceNames(ii)), "UTF-8");
                hashBytes = uint8(char(sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256( ...
                    fullfile(outputDir, sourceNames(ii)))));
                payload = [payload; uint8(nameBytes(:)); hashBytes(:)]; %#ok<AGROW>
            end
            value = string(sixgr.rrc.asn1.asn1SHA256Hex(payload));
        end

        function value = fileSHA256(path)
            fileId = fopen(path, "rb");
            if fileId < 0
                error("sixgr:phy:pdcch:missing_evidence_source", ...
                    "Cannot open evidence file %s.", path);
            end
            cleanup = onCleanup(@() fclose(fileId));
            bytes = fread(fileId, inf, "*uint8");
            value = string(sixgr.rrc.asn1.asn1SHA256Hex(bytes));
        end
    end
end
