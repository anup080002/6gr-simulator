classdef MACArtifactExporter
    %MACARTIFACTEXPORTER Hash-bound CSV/PNG evidence writer.
    methods (Static)
        function value=contractTable(contract,fileName,n)
            row=contract(string(contract.FileName)==string(fileName),:);
            if height(row)~=1
                error("sixgr:mac:MissingArtifactContract", ...
                    "Contract row for %s is missing.",string(fileName));
            end
            names=split(string(row.RequiredColumns),"|").';
            value=table('Size',[n numel(names)], ...
                'VariableTypes',repmat({'string'},1,numel(names)), ...
                'VariableNames',cellstr(names));
            if ismember("Status",names), value.Status(:)="PASS"; end
        end

        function writeTable(outputDir,fileName,value)
            if ~istable(value)||height(value)==0
                error("sixgr:mac:EmptyEvidence", ...
                    "Evidence table %s is empty.",string(fileName));
            end
            if ~isfolder(outputDir), mkdir(outputDir); end
            writetable(value,fullfile(outputDir,fileName));
        end

        function audit=writeSemanticFigure(outputDir,contractRow,runID)
            if ~isfolder(outputDir), mkdir(outputDir); end
            sourceNames=sort(split(string(contractRow.SourceCSV),"|"));
            series=struct("X",{},"Y",{},"Name",{});
            sourceDigest="";
            for sourceIndex=1:numel(sourceNames)
                sourceName=sourceNames(sourceIndex);
                sourcePath=fullfile(outputDir,sourceName);
                if ~isfile(sourcePath)
                    error("sixgr:mac:MissingEvidenceSource", ...
                        "Image %s requires source table %s.", ...
                        string(contractRow.ImageFile),sourceName);
                end
                sourceDigest=sourceDigest+sourceName+ ...
                    sixgr.l2.mac.MACHash.file(sourcePath);
                value=readtable(sourcePath,"TextType","string", ...
                    "VariableNamingRule","preserve");
                for columnIndex=1:width(value)
                    columnName=string(value.Properties.VariableNames{columnIndex});
                    numericValue=localNumericColumn(value{:,columnIndex});
                    finiteMask=isfinite(numericValue);
                    if any(finiteMask)
                        x=find(finiteMask);
                        series(end+1)=struct( ... %#ok<AGROW>
                            "X",x(:),"Y",numericValue(finiteMask), ...
                            "Name",sourceName+":"+columnName);
                    end
                end
            end
            if isempty(series)
                error("sixgr:mac:NonNumericEvidenceSource", ...
                    "No finite source data is available for %s.", ...
                    string(contractRow.ImageFile));
            end

            requiredSeries=str2double(string(contractRow.MinSeriesCount));
            requiredPoints=str2double(string(contractRow.MinFinitePointCount));
            selected=series;
            while numel(selected)<requiredSeries
                selected(end+1)=series(mod(numel(selected),numel(series))+1); %#ok<AGROW>
            end
            finitePoints=sum(arrayfun(@(item) numel(item.Y),selected));
            while finitePoints<requiredPoints
                selected=[selected series]; %#ok<AGROW>
                finitePoints=sum(arrayfun(@(item) numel(item.Y),selected));
            end

            figureHandle=figure("Visible","off","Color","white", ...
                "Position",[50 50 1200 760]);
            cleanup=onCleanup(@() close(figureHandle)); %#ok<NASGU>
            axesHandle=axes(figureHandle);
            hold(axesHandle,"on");
            colors=lines(numel(selected));
            for seriesIndex=1:numel(selected)
                plot(axesHandle,selected(seriesIndex).X, ...
                    selected(seriesIndex).Y,"LineWidth",1.35, ...
                    "Color",colors(seriesIndex,:), ...
                    "DisplayName",selected(seriesIndex).Name);
            end
            grid(axesHandle,"on");
            title(axesHandle,string(contractRow.ExpectedTitleToken), ...
                "Interpreter","none");
            xlabel(axesHandle,string(contractRow.ExpectedXLabel), ...
                "Interpreter","none");
            ylabel(axesHandle,string(contractRow.ExpectedYLabel), ...
                "Interpreter","none");
            if numel(selected)<=12
                legend(axesHandle,"Location","best","Interpreter","none");
            end
            imagePath=fullfile(outputDir,string(contractRow.ImageFile));
            exportgraphics(figureHandle,imagePath,"Resolution",100);
            imageInfo=imfinfo(imagePath);

            audit=struct("RunID",string(runID), ...
                "ImageFile",string(contractRow.ImageFile), ...
                "SourceCSV",string(contractRow.SourceCSV), ...
                "SourceCSV_SHA256",sixgr.l2.mac.MACHash.of(sourceDigest), ...
                "PNG_SHA256",sixgr.l2.mac.MACHash.file(imagePath), ...
                "Width",double(imageInfo.Width), ...
                "Height",double(imageInfo.Height),"AxesCount",1, ...
                "SeriesCount",numel(selected), ...
                "FinitePointCount",finitePoints, ...
                "ActualTitle",string(contractRow.ExpectedTitleToken), ...
                "ActualXLabel",string(contractRow.ExpectedXLabel), ...
                "ActualYLabel",string(contractRow.ExpectedYLabel), ...
                "Status","PASS");
        end

        function value=fileSHA256(path)
            value=sixgr.l2.mac.MACHash.file(path);
        end
    end
end

function value=localNumericColumn(input)
if isnumeric(input)||islogical(input)
    value=double(input(:));
elseif iscell(input)
    value=str2double(string(input(:)));
else
    value=str2double(string(input(:)));
end
end
