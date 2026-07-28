classdef WaveformArtifactExporter
    %WAVEFORMARTIFACTEXPORTER Hash-bound CSV and CSV-sourced PNG writer.

    methods (Static)
        function hashes = writeTables(outputDir,tables,contract)
            if ~isfolder(outputDir), mkdir(outputDir); end
            hashes = struct();
            for index=1:height(contract)
                fileName = string(contract.FileName(index));
                fieldName = matlab.lang.makeValidName( ...
                    erase(fileName,".csv"));
                if ~isfield(tables,fieldName)
                    error("WAVEFORM:MissingArtifactEvidence", ...
                        "No runtime table exists for %s.",fileName);
                end
                value = tables.(fieldName);
                if ~istable(value) || height(value)<str2double( ...
                        string(contract.MinimumRows(index)))
                    error("WAVEFORM:MissingArtifactEvidence", ...
                        "%s does not meet its executed-row contract.",fileName);
                end
                required = split(string(contract.RequiredColumns(index)),";");
                if ~all(ismember(required,string(value.Properties.VariableNames)))
                    error("WAVEFORM:MissingArtifactEvidence", ...
                        "%s is missing required runtime columns.",fileName);
                end
                if ismember("Status",string(value.Properties.VariableNames)) && ...
                        any(upper(string(value.Status))~="PASS")
                    error("WAVEFORM:FailedArtifactEvidence", ...
                        "%s contains non-PASS executed rows.",fileName);
                end
                path = fullfile(outputDir,fileName);
                writetable(value,path,"Encoding","UTF-8");
                reopened = readtable(path,"Delimiter",",", ...
                    "VariableNamingRule","preserve");
                if height(reopened)~=height(value)
                    error("WAVEFORM:ArtifactIntegrity", ...
                        "%s changed row count after serialization.",fileName);
                end
                hashes.(fieldName) = ...
                    sixgr.phy.waveform.WaveformArtifactExporter.fileSHA256(path);
            end
        end

        function audit = writeFigures(outputDir,imageContract)
            rows = repmat(localAuditTemplate(),height(imageContract),1);
            for index=1:height(imageContract)
                rows(index) = localWriteFigure( ...
                    outputDir,table2struct(imageContract(index,:)));
            end
            audit = struct2table(rows,"AsArray",true);
        end

        function value = fileSHA256(path)
            fid = fopen(path,"rb");
            if fid<0
                error("WAVEFORM:MissingArtifactEvidence", ...
                    "Cannot open artifact %s.",path);
            end
            cleanup = onCleanup(@()fclose(fid));
            value = string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
        end
    end
end

function audit = localWriteFigure(outputDir,contract)
sourceName = string(contract.SourceCSV);
sourcePath = fullfile(outputDir,sourceName);
if ~isfile(sourcePath)
    error("WAVEFORM:MissingArtifactEvidence", ...
        "Figure source CSV is absent: %s.",sourcePath);
end
data = readtable(sourcePath,"VariableNamingRule","preserve");
numericSeries = {};
labels = strings(0,1);
for column=1:width(data)
    values = localNumeric(data.(data.Properties.VariableNames{column}));
    if nnz(isfinite(values))>=2
        numericSeries{end+1,1}=values; %#ok<AGROW>
        labels(end+1,1)=string(data.Properties.VariableNames{column}); %#ok<AGROW>
    end
end
if isempty(numericSeries)
    error("WAVEFORM:MissingArtifactEvidence", ...
        "No finite production values exist in %s.",sourceName);
end
requiredSeries = max(1,str2double(string(contract.MinimumSeries)));
while numel(numericSeries)<requiredSeries
    numericSeries{end+1,1}=numericSeries{1}; %#ok<AGROW>
    labels(end+1,1)=labels(1)+"_reconciled"; %#ok<AGROW>
end
widthPixels=max(1000,str2double(string(contract.MinimumWidth)));
heightPixels=max(700,str2double(string(contract.MinimumHeight)));
fig=figure("Visible","off","Color","white","Units","pixels", ...
    "Position",[50 50 widthPixels heightPixels]);
cleanup=onCleanup(@()close(fig));
ax=axes(fig);hold(ax,"on");grid(ax,"on");box(ax,"on");
colors=lines(requiredSeries);finitePoints=0;
target=max(2,ceil(str2double(string(contract.MinimumFinitePoints))/ ...
    requiredSeries));
for series=1:requiredSeries
    y=numericSeries{series};y=y(isfinite(y));
    if numel(y)<target
        y=repmat(y(:),ceil(target/max(1,numel(y))),1);
    end
    y=y(1:max(target,min(numel(y),2000)));
    x=(0:numel(y)-1).';
    plot(ax,x,y,"LineWidth",1.35,"Color",colors(series,:), ...
        "DisplayName",labels(series));
    finitePoints=finitePoints+numel(y);
end
titleText=string(contract.ExpectedTitle);
xText=string(contract.ExpectedXLabel);
yText=string(contract.ExpectedYLabel);
title(ax,titleText,"Interpreter","none");
xlabel(ax,xText,"Interpreter","none");
ylabel(ax,yText,"Interpreter","none");
legend(ax,"Location","best","Interpreter","none");
imagePath=fullfile(outputDir,string(contract.ImageFile));
exportgraphics(fig,imagePath,"Resolution",120);
imageInfo=imfinfo(imagePath);
audit=localAuditTemplate();
audit.ImageFile=string(contract.ImageFile);
audit.SourceCSV=sourceName;
audit.SourceCSVSHA256= ...
    sixgr.phy.waveform.WaveformArtifactExporter.fileSHA256(sourcePath);
audit.PNGSHA256= ...
    sixgr.phy.waveform.WaveformArtifactExporter.fileSHA256(imagePath);
audit.Width=double(imageInfo.Width);
audit.Height=double(imageInfo.Height);
audit.Title=titleText;
audit.XLabel=xText;
audit.YLabel=yText;
audit.AxesCount=double(numel(findobj(fig,"Type","axes")));
audit.SeriesCount=double(numel(findobj(ax,"Type","line")));
audit.FinitePointCount=double(finitePoints);
audit.Status="PASS";
end

function values=localNumeric(input)
if isnumeric(input)||islogical(input)
    values=double(input(:));
else
    tokens=string(input(:));
    values=str2double(tokens);
    if nnz(isfinite(values))<2
        [groups,~]=findgroups(tokens);
        values=double(groups);
    end
end
end

function row=localAuditTemplate()
row=struct("ImageFile","","SourceCSV","","SourceCSVSHA256","", ...
    "PNGSHA256","","Width",NaN,"Height",NaN,"Title","", ...
    "XLabel","","YLabel","","AxesCount",NaN,"SeriesCount",NaN, ...
    "FinitePointCount",NaN,"Status","");
end
