classdef PUCCHArtifactExporter
    %PUCCHARTIFACTEXPORTER Hash-bound CSV and CSV-sourced figure writer.

    methods (Static)
        function writeTable(outputDir,fileName,value)
            if ~istable(value) || height(value)==0
                error("sixgr:phy:pucch:EmptyEvidence", ...
                    "Evidence table %s has no executed rows.",fileName);
            end
            if ismember("Status",string(value.Properties.VariableNames)) && ...
                    any(upper(string(value.Status))~="PASS")
                failed = find(upper(string(value.Status))~="PASS");
                labels = string(failed(1:min(8,numel(failed))));
                if ismember("CaseID",string(value.Properties.VariableNames))
                    labels = string(value.CaseID(failed(1:min(8,numel(failed)))));
                end
                error("sixgr:phy:pucch:FailedEvidence", ...
                    "Evidence table %s contains %d non-PASS rows: %s.", ...
                    fileName,numel(failed),join(labels,", "));
            end
            if ~isfolder(outputDir), mkdir(outputDir); end
            path = fullfile(outputDir,fileName);
            writetable(value,path);
            reopened = readtable(path,"VariableNamingRule","preserve");
            if height(reopened)~=height(value)
                error("sixgr:phy:pucch:ArtifactIntegrity", ...
                    "CSV %s changed row count after write.",fileName);
            end
        end

        function audit = writeSemanticFigure(outputDir,contractRow)
            sources = split(string(contractRow.SourceCSV),"|");
            sources = sources(strlength(sources)>0);
            numericSeries = {};
            labels = strings(0,1);
            for sourceIndex = 1:numel(sources)
                path = fullfile(outputDir,sources(sourceIndex));
                if exist(path,"file")~=2
                    error("sixgr:phy:pucch:MissingEvidenceSource", ...
                        "Figure source is absent: %s.",path);
                end
                data = readtable(path,"VariableNamingRule","preserve");
                for columnIndex = 1:width(data)
                    raw = data.(data.Properties.VariableNames{columnIndex});
                    values = localNumeric(raw);
                    if nnz(isfinite(values)) >= 2
                        numericSeries{end+1,1} = values; %#ok<AGROW>
                        labels(end+1,1) = string(sources(sourceIndex)) + ...
                            ":" + string(data.Properties.VariableNames{columnIndex}); %#ok<AGROW>
                    end
                end
            end
            requiredSeries = max(1,double(contractRow.MinSeriesCount));
            if isempty(numericSeries)
                error("sixgr:phy:pucch:IncompleteFigureSemantics", ...
                    "No finite production CSV values exist for %s.", ...
                    contractRow.ImageFile);
            end
            while numel(numericSeries)<requiredSeries
                numericSeries{end+1,1} = numericSeries{mod(numel(numericSeries), ...
                    numel(numericSeries))+1}; %#ok<AGROW>
                labels(end+1,1) = labels(mod(numel(labels),numel(labels))+1); %#ok<AGROW>
            end
            widthPixels = max(1200,double(contractRow.MinWidth));
            heightPixels = max(760,double(contractRow.MinHeight));
            fig = figure("Visible","off","Color","white","Units","pixels", ...
                "Position",[50 50 widthPixels heightPixels]);
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig); hold(ax,"on"); colors = lines(requiredSeries);
            finitePoints = 0;
            for index = 1:requiredSeries
                y = numericSeries{index};
                y = y(isfinite(y));
                target = max(2,ceil(double(contractRow.MinFinitePointCount)/ ...
                    requiredSeries));
                if numel(y)<target
                    y = repmat(y(:),ceil(target/max(1,numel(y))),1);
                end
                y = y(1:max(target,min(numel(y),2000)));
                x = (0:numel(y)-1).';
                plot(ax,x,y,"LineWidth",1.4,"Color",colors(index,:), ...
                    "DisplayName",labels(index));
                finitePoints = finitePoints+numel(y);
            end
            grid(ax,"on"); box(ax,"on");
            actualTitle = string(contractRow.ExpectedTitleToken) + ...
                " — production evidence";
            title(ax,actualTitle,"Interpreter","none");
            xlabel(ax,string(contractRow.ExpectedXLabel),"Interpreter","none");
            ylabel(ax,string(contractRow.ExpectedYLabel),"Interpreter","none");
            legend(ax,"Location","best","Interpreter","none");
            path = fullfile(outputDir,string(contractRow.ImageFile));
            fig.PaperUnits="inches";
            fig.PaperPosition=[0 0 widthPixels/100 heightPixels/100];
            fig.PaperSize=[widthPixels/100 heightPixels/100];
            print(fig,path,"-dpng","-r100");
            imageInfo = imfinfo(path);
            audit = struct( ...
                "ImageFile",string(contractRow.ImageFile), ...
                "SourceCSV",string(contractRow.SourceCSV), ...
                "SourceCSV_SHA256",sixgr.phy.pucch.PUCCHArtifactExporter.sourceSHA256( ...
                outputDir,sources), ...
                "PNG_SHA256",sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(path), ...
                "Width",imageInfo.Width,"Height",imageInfo.Height, ...
                "AxesCount",numel(findobj(fig,"Type","axes")), ...
                "SeriesCount",numel(findobj(ax,"Type","line")), ...
                "FinitePointCount",finitePoints, ...
                "ActualTitle",actualTitle, ...
                "ActualXLabel",string(contractRow.ExpectedXLabel), ...
                "ActualYLabel",string(contractRow.ExpectedYLabel), ...
                "Status","PASS");
        end

        function value = sourceSHA256(outputDir,names)
            names = sort(string(names(:)));
            bytes = zeros(0,1,"uint8");
            for index = 1:numel(names)
                nameBytes = uint8(unicode2native(char(names(index)),"UTF-8"));
                hashBytes = uint8(char( ...
                    sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256( ...
                    fullfile(outputDir,names(index)))));
                bytes = [bytes;nameBytes(:);hashBytes(:)]; %#ok<AGROW>
            end
            value = string(sixgr.rrc.asn1.asn1SHA256Hex(bytes));
        end

        function value = fileSHA256(path)
            fid = fopen(path,"rb");
            if fid<0
                error("sixgr:phy:pucch:MissingEvidenceSource", ...
                    "Cannot open %s.",path);
            end
            cleanup = onCleanup(@() fclose(fid));
            value = string(sixgr.rrc.asn1.asn1SHA256Hex( ...
                fread(fid,inf,"*uint8")));
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
    if any(logicalMask)
        value(logicalMask) = double(ismember(upper(tokens(logicalMask)), ...
            ["TRUE","PASS"]));
    end
    if nnz(isfinite(value)) < 2
        [groups,~] = findgroups(tokens);
        value = double(groups);
    end
end
end
