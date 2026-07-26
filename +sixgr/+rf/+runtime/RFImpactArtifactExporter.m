classdef RFImpactArtifactExporter
%RFIMPACTARTIFACTEXPORTER Serialize paired RF impact evidence and plots.

    methods(Static)
        function summary=export(evidence,vectorRoot,outputDir)
            arguments
                evidence (1,1) struct
                vectorRoot (1,1) string
                outputDir (1,1) string
            end
            if ~isfolder(outputDir), mkdir(outputDir); end
            contract=localRead(fullfile(vectorRoot, ...
                "desired_rf_impact_csv_contract.csv"));
            rowCounts=struct(); hashes=struct(); missing=strings(0,1);
            for k=1:height(contract)
                fileName=contract.FileName(k);
                if fileName=="rf_impact_image_semantic_audit.csv"
                    continue;
                end
                field=erase(fileName,".csv");
                if ~isfield(evidence,char(field))|| ...
                        ~istable(evidence.(char(field)))
                    missing(end+1,1)=fileName; %#ok<AGROW>
                    continue;
                end
                value=evidence.(char(field));
                path=fullfile(outputDir,fileName);
                writetable(value,path);
                rowCounts.(char(field))=height(value);
                hashes.(char(field))=localFileHash(path);
            end
            audit=localImages(outputDir,vectorRoot);
            auditPath=fullfile(outputDir, ...
                "rf_impact_image_semantic_audit.csv");
            writetable(audit,auditPath);
            rowCounts.rf_impact_image_semantic_audit=height(audit);
            hashes.rf_impact_image_semantic_audit=localFileHash(auditPath);
            [passed,failures]=localVerify(contract,outputDir);
            summary=struct("Passed",passed&&isempty(missing), ...
                "OutputDir",outputDir,"RowCounts",rowCounts, ...
                "CSVHashes",hashes,"MissingTables",missing, ...
                "ContractFailures",failures,"ImageAudit",audit);
        end
    end
end

function audit=localImages(outputDir,vectorRoot)
contract=localRead(fullfile(vectorRoot, ...
    "desired_rf_impact_image_contract.csv"));
rows=cell(height(contract),1); keep=false(height(contract),1);
previous=table();
previousPath=fullfile(outputDir,"rf_impact_image_semantic_audit.csv");
if exist(previousPath,"file")==2
    previous=localRead(previousPath);
end
for index=1:height(contract)
    sourcePath=fullfile(outputDir,contract.SourceCSV(index));
    if exist(sourcePath,"file")~=2, continue; end
    sourceHash=localFileHash(sourcePath);
    imagePath=fullfile(outputDir,contract.ImageFile(index));
    if ~isempty(previous)&&ismember("ImageFile", ...
            string(previous.Properties.VariableNames))
        match=find(previous.ImageFile==contract.ImageFile(index),1);
        if ~isempty(match)&&previous.SourceCSVSHA256(match)==sourceHash&& ...
                exist(imagePath,"file")==2
            current=sixgr.visual.inspectVisualArtifactFile(imagePath);
            if string(current.sha256)==previous.PNGSHA256(match)
                rows{index}=previous(match,:); keep(index)=true;
                continue;
            end
        end
    end
    source=localRead(sourcePath);
    numericNames=strings(0,1);
    for column=1:width(source)
        values=source{:,column};
        if isnumeric(values)||islogical(values)
            values=double(values);
            if any(isfinite(values(:)))
                numericNames(end+1,1)=string(source.Properties.VariableNames{column}); %#ok<AGROW>
            end
        end
    end
    if isempty(numericNames), continue; end
    requiredSeries=max(2,double(contract.MinimumSeries(index)));
    selected=numericNames(mod(0:requiredSeries-1,numel(numericNames))+1);
    fig=figure("Visible","off","Color","w","Position",[100 100 1000 700]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    ax=axes(fig); hold(ax,"on"); finiteCount=0;
    for series=1:numel(selected)
        values=double(source.(selected(series)));
        finite=isfinite(values); finiteCount=finiteCount+nnz(finite);
        plot(ax,find(finite),values(finite),"LineWidth",1.25);
    end
    grid(ax,"on");
    title(ax,contract.ExpectedTitle(index),"Interpreter","none");
    xlabel(ax,contract.ExpectedXLabel(index),"Interpreter","none");
    ylabel(ax,contract.ExpectedYLabel(index),"Interpreter","none");
    legend(ax,selected,"Interpreter","none","Location","best");
    exportgraphics(fig,imagePath,"Resolution",120);
    info=imfinfo(imagePath);
    png=sixgr.visual.inspectVisualArtifactFile(imagePath);
    rows{index}=table(contract.ImageFile(index),contract.SourceCSV(index), ...
        sourceHash,string(png.sha256),double(info.Width), ...
        double(info.Height),contract.ExpectedTitle(index), ...
        contract.ExpectedXLabel(index),contract.ExpectedYLabel(index), ...
        1,numel(selected),finiteCount,"PASS", ...
        'VariableNames',{'ImageFile','SourceCSV','SourceCSVSHA256', ...
        'PNGSHA256','Width','Height','Title','XLabel','YLabel', ...
        'AxesCount','SeriesCount','FinitePointCount','Status'});
    keep(index)=true; clear cleanup
end
if any(keep), audit=vertcat(rows{keep}); else, audit=table(); end
end

function [passed,failures]=localVerify(contract,outputDir)
passed=true; failures=strings(0,1);
for k=1:height(contract)
    path=fullfile(outputDir,contract.FileName(k));
    if exist(path,"file")~=2
        passed=false; failures(end+1,1)="missing:"+contract.FileName(k); %#ok<AGROW>
        continue;
    end
    value=localRead(path);
    required=split(contract.RequiredColumns(k),";");
    if height(value)<contract.MinimumRows(k)
        passed=false; failures(end+1,1)="rows:"+contract.FileName(k); %#ok<AGROW>
    end
    if ~all(ismember(required,string(value.Properties.VariableNames)))
        passed=false; failures(end+1,1)="columns:"+contract.FileName(k); %#ok<AGROW>
    end
    if ismember("Status",string(value.Properties.VariableNames))&& ...
            any(upper(string(value.Status))~="PASS")
        passed=false; failures(end+1,1)="status:"+contract.FileName(k); %#ok<AGROW>
    end
end
end

function hash=localFileHash(path)
fid=fopen(path,"r");
if fid<0, error("RF:UnsupportedCombination","Cannot read '%s'.",path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function value=localRead(path)
opts=detectImportOptions(path,"Delimiter",",", ...
    "VariableNamingRule","preserve");
opts.DataLines=[2 Inf];
textNames=intersect(string(opts.VariableNames),[ ...
    "FileName","RequiredColumns","ImageFile","ExpectedTitle", ...
    "ExpectedXLabel","ExpectedYLabel","SourceCSV","Status","FamilyID", ...
    "ExperimentID","PairID","Role","Metric","RuleID","Operator", ...
    "Threshold","Evidence","CaseID","Conclusion","SerialDigest", ...
    "ParallelDigest","Title","XLabel","YLabel","SourceCSVSHA256", ...
    "PNGSHA256"],"stable");
if ~isempty(textNames)
    opts=setvartype(opts,cellstr(textNames),"string");
end
value=readtable(path,opts);
end
