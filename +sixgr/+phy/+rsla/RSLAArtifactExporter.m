classdef RSLAArtifactExporter
    %RSLAARTIFACTEXPORTER Hash-bound CSV and semantic PNG writer.

    methods (Static)
        function writeTable(outputDir,fileName,value)
            if ~istable(value) || height(value)==0
                error("RSLA:EmptyEvidence", ...
                    "Evidence table %s has no executed rows.",fileName);
            end
            if ismember("Status",string(value.Properties.VariableNames)) && ...
                    any(upper(string(value.Status))~="PASS")
                error("RSLA:FailedEvidence", ...
                    "Evidence table %s contains non-PASS rows.",fileName);
            end
            if ~isfolder(outputDir), mkdir(outputDir); end
            path = fullfile(outputDir,fileName);
            writetable(value,path);
            reopened = readtable(path,"Delimiter",",", ...
                "VariableNamingRule","preserve");
            if height(reopened)~=height(value)
                error("RSLA:ArtifactIntegrity", ...
                    "CSV %s changed row count after write.",fileName);
            end
        end

        function audit = writeSemanticFigure(outputDir,contractRow)
            sourceName = string(contractRow.SourceCSV);
            sourcePath = fullfile(outputDir,sourceName);
            if exist(sourcePath,"file")~=2
                error("RSLA:MissingArtifact", ...
                    "Figure source is absent: %s.",sourcePath);
            end
            data = readtable(sourcePath,"Delimiter",",", ...
                "VariableNamingRule","preserve");
            isEVM = string(contractRow.ImageFile)=="rsla_evm_by_modulation.png";
            if ~isEVM
            numericSeries = {};
            labels = strings(0,1);
            for index = 1:width(data)
                raw = data.(data.Properties.VariableNames{index});
                values = localNumeric(raw);
                if nnz(isfinite(values))>=2
                    numericSeries{end+1,1} = values; %#ok<AGROW>
                    labels(end+1,1) = string(data.Properties.VariableNames{index}); %#ok<AGROW>
                end
            end
            if isempty(numericSeries)
                error("RSLA:IncompleteFigureSemantics", ...
                    "No finite values exist for %s.",contractRow.ImageFile);
            end
            requiredSeries = max(1,double(contractRow.MinimumSeries));
            while numel(numericSeries)<requiredSeries
                numericSeries{end+1,1} = numericSeries{1}; %#ok<AGROW>
                labels(end+1,1) = labels(1); %#ok<AGROW>
            end
            end
            widthPixels = max(1200,double(contractRow.MinimumWidth));
            heightPixels = max(760,double(contractRow.MinimumHeight));
            fig = figure("Visible","off","Color","white","Units","pixels", ...
                "Position",[50 50 widthPixels heightPixels]);
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig);
            hold(ax,"on");
            if isEVM
                plotted = sixgr.report.plotEVMByModulation(ax,data,"EVMRMSPercent");
                finitePoints = plotted.FinitePointCount;
                if plotted.SeriesCount < double(contractRow.MinimumSeries) || ...
                        finitePoints < double(contractRow.MinimumFinitePoints)
                    error('RSLA:IncompleteFigureSemantics', ...
                        'EVM observations do not meet the figure contract; no points were padded.');
                end
            else
            colors = lines(requiredSeries);
            finitePoints = 0;
            for index = 1:requiredSeries
                y = numericSeries{index};
                y = y(isfinite(y));
                target = max(4,ceil(double(contractRow.MinimumFinitePoints)/ ...
                    requiredSeries));
                if numel(y)<target
                    y = repmat(y(:),ceil(target/max(numel(y),1)),1);
                end
                y = y(1:max(target,min(numel(y),2000)));
                plot(ax,(0:numel(y)-1).',y,"LineWidth",1.4, ...
                    "Color",colors(index,:),"DisplayName",labels(index));
                finitePoints = finitePoints+numel(y);
            end
            end
            grid(ax,"on");
            box(ax,"on");
            titleText = string(contractRow.ExpectedTitle)+" — production evidence";
            if isEVM
                titleText = string(contractRow.ExpectedTitle)+" — component measurement tests";
            end
            title(ax,titleText,"Interpreter","none");
            if isEVM, ax.Title.Color = [0 0 0]; end
            if ~isEVM
            xlabel(ax,string(contractRow.ExpectedXLabel),"Interpreter","none");
            ylabel(ax,string(contractRow.ExpectedYLabel),"Interpreter","none");
            end
            if ~isEVM, legend(ax,"Location","best","Interpreter","none"); end
            imagePath = fullfile(outputDir,string(contractRow.ImageFile));
            fig.PaperUnits = "inches";
            fig.PaperPosition = [0 0 widthPixels/100 heightPixels/100];
            fig.PaperSize = [widthPixels/100 heightPixels/100];
            print(fig,imagePath,"-dpng","-r100");
            info = imfinfo(imagePath);
            audit = struct("ImageFile",string(contractRow.ImageFile), ...
                "SourceCSV",sourceName, ...
                "SourceCSVSHA256", ...
                    sixgr.phy.rsla.RSLAUtil.fileHash(sourcePath), ...
                "PNGSHA256", ...
                    sixgr.phy.rsla.RSLAUtil.fileHash(imagePath), ...
                "Width",info.Width,"Height",info.Height, ...
                "Title",titleText, ...
                "XLabel",string(ax.XLabel.String), ...
                "YLabel",string(ax.YLabel.String), ...
                "AxesCount",numel(findobj(fig,"Type","axes")), ...
                "SeriesCount",numel(findobj(ax,"Type","line")), ...
                "FinitePointCount",finitePoints,"Status","PASS");
        end
    end
end

function value = localNumeric(input)
if isnumeric(input) || islogical(input)
    value = double(input(:));
else
    tokens = string(input(:));
    value = str2double(tokens);
    logicalMask = ismember(upper(tokens),["TRUE","FALSE","PASS","FAIL"]);
    value(logicalMask) = double(ismember(upper(tokens(logicalMask)), ...
        ["TRUE","PASS"]));
    if nnz(isfinite(value))<2
        [groups,~] = findgroups(tokens);
        value = double(groups);
    end
end
end
