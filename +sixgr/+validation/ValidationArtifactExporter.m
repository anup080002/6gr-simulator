classdef ValidationArtifactExporter
    %VALIDATIONARTIFACTEXPORTER Export only supplied, validated evidence.
    methods (Static)
        function path=writeTable(outputDir,fileName,input,minimumRows)
            if nargin<4, minimumRows=1; end
            if ~istable(input)
                error("sixgr:validation:SchemaWrongType", ...
                    "Validation artifact input must be a table.");
            end
            if height(input)<double(minimumRows)
                error("sixgr:validation:IncompleteMandatoryPoint", ...
                    "Artifact %s has %d rows; %d are required.", ...
                    string(fileName),height(input),minimumRows);
            end
            sixgr.util.ensureFolder(outputDir);
            path=fullfile(outputDir,fileName);
            sixgr.util.csvWriteTable(path,input);
        end
        function audit=plot(outputDir,imageName,sourceCSV,titleText,xLabel,yLabel,x,y)
            if ~isfile(sourceCSV)
                error("sixgr:validation:ArtifactMissing", ...
                    "Plot source CSV is missing: %s.",string(sourceCSV));
            end
            x=double(x(:)); y=double(y);
            if isempty(x)||isempty(y)||any(~isfinite(x))||any(~isfinite(y),"all")
                error("sixgr:validation:IncompleteMandatoryPoint", ...
                    "Semantic plot input is empty or nonfinite.");
            end
            sixgr.util.ensureFolder(outputDir);
            path=fullfile(outputDir,imageName);
            fig=figure("Visible","off","Color","white", ...
                "Position",[100 100 1000 700]);
            cleanup=onCleanup(@()close(fig));
            ax=axes(fig); plot(ax,x,y,"LineWidth",1.5,"Marker",".");
            grid(ax,"on"); title(ax,titleText); xlabel(ax,xLabel); ylabel(ax,yLabel);
            exportgraphics(fig,path,"Resolution",120);
            sourceHash=localFileHash(sourceCSV);
            imageHash=localFileHash(path);
            info=imfinfo(path);
            audit=table(string(imageName),string(localName(sourceCSV)), ...
                sourceHash,imageHash,double(info.Width),double(info.Height), ...
                1,size(y,2),nnz(isfinite(y)),string(titleText), ...
                string(xLabel),string(yLabel),true,true,"PASS", ...
                'VariableNames',["ImageFile","SourceCSV","SourceCSVSHA256", ...
                "ImageSHA256","Width","Height","Axes","Series", ...
                "FinitePoints","ActualTitle","ActualXLabel","ActualYLabel", ...
                "TitleOK","LabelsOK","Status"]);
        end
    end
end

function hash=localFileHash(path)
fid=fopen(path,"rb");
if fid<0, error("sixgr:validation:ArtifactMissing", ...
        "Cannot open artifact %s.",string(path)); end
cleanup=onCleanup(@()fclose(fid));
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function name=localName(path)
[~,base,ext]=fileparts(path); name=string(base)+string(ext);
end
