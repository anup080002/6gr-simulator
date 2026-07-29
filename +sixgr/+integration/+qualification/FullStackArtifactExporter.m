classdef FullStackArtifactExporter
    %FULLSTACKARTIFACTEXPORTER Consolidated evidence and semantic figures.
    methods (Static)
        function writeSubcases(ctx,T)
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_subcase_status.csv"),T);
        end

        function T=writeRunManifest(ctx,finalStatus,exitCode)
            endUTC=localUTC();
            status = string(finalStatus);
            T=table(ctx.RunID,ctx.Profile.Preset,ctx.ScenarioID, ...
                ctx.ScenarioRevisionID,ctx.SourceYAMLSHA256, ...
                ctx.EffectiveYAMLSHA256,ctx.ResolvedYAMLSHA256, ...
                ctx.ExecutedYAMLSHA256,ctx.GitCommit,ctx.MATLABVersion, ...
                ctx.ToolboxVersion,ctx.WebGUIURL,ctx.Owner,ctx.StartUTC, ...
                endUTC,double(exitCode),string(finalStatus),status, ...
                'VariableNames',{'RunID','SuitePreset','ScenarioID', ...
                'ScenarioRevisionID','SourceYAMLSHA256', ...
                'EffectiveYAMLSHA256','ResolvedYAMLSHA256', ...
                'ExecutedYAMLSHA256','GitCommit','MATLABVersion', ...
                'ToolboxVersion','WebGUIURL','Owner','StartUTC','EndUTC', ...
                'ExitCode','FinalStatus','Status'});
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_run_manifest.csv"),T);
        end

        function T=writeFailureRegistry(ctx,subcases,components,values, ...
                negatives,acceptance,regression)
            rows=repmat(localFailureRow(),0,1);
            sources={subcases,"SubcaseID","Category"; ...
                components,"ComponentID","Domain"; ...
                values,"CheckID","Domain"; ...
                negatives,"CaseID","Domain"; ...
                acceptance,"RuleID","Category"};
            failureIndex=0;
            for sourceIndex=1:size(sources,1)
                Tsrc=sources{sourceIndex,1};
                idColumn=sources{sourceIndex,2};
                domainColumn=sources{sourceIndex,3};
                mask=upper(string(Tsrc.Status))~="PASS";
                for rowIndex=reshape(find(mask),1,[])
                    failureIndex=failureIndex+1;
                    code="";
                    if ismember("FailureCode",string(Tsrc.Properties.VariableNames))
                        code=string(Tsrc.FailureCode(rowIndex));
                    end
                    subID="";
                    if ismember("SubcaseID",string(Tsrc.Properties.VariableNames))
                        subID=string(Tsrc.SubcaseID(rowIndex));
                    end
                    rows(end+1,1)=localFailureRow(ctx,failureIndex,subID, ... %#ok<AGROW>
                        string(Tsrc.(domainColumn)(rowIndex)),code, ...
                        string(Tsrc.(idColumn)(rowIndex)));
                end
            end
            regMask=upper(string(regression.Status))~="PASS";
            for rowIndex=reshape(find(regMask),1,[])
                failureIndex=failureIndex+1;
                rows(end+1,1)=localFailureRow(ctx,failureIndex,"SC-30", ... %#ok<AGROW>
                    "Regression","FULLSTACK:RegressionFailure", ...
                    string(regression.Suite(rowIndex)));
            end
            if isempty(rows)
                rows=localFailureRow(ctx,0,"","Qualification","","");
                rows.FailureID="NONE";
                rows.Severity="INFO";
                rows.RootCauseStatus="NOT_APPLICABLE";
                rows.Resolution="No failures observed.";
                rows.Status="PASS";
            end
            T=struct2table(rows,"AsArray",true);
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_failure_registry.csv"),T);
        end

        function audit=writeFigures(ctx)
            registry=ctx.Profile.SelectedArtifactRegistry;
            specs=registry(registry.Domain=="Full Stack Qualification" & ...
                registry.ArtifactType=="PNG",:);
            rows=repmat(localImageAuditRow(),0,1);
            artifactIndex=sixgr.integration.qualification. ...
                RunArtifactIndex.build(ctx.RunFolder);
            for index=1:height(specs)
                sourceNames=localList(specs.SourceCSV(index));
                if numel(sourceNames)~=1,continue;end
                source=localFindUniqueOrEmpty( ...
                    artifactIndex,sourceNames(1));
                if strlength(source)==0,continue;end
                T=readtable(source,"TextType","string", ...
                    "VariableNamingRule","preserve");
                if isempty(T),continue;end
                imagePath=fullfile(ctx.CSVDir,string(specs.FileName(index)));
                localPlot(T,imagePath,string(specs.ExpectedTitle(index)), ...
                    string(specs.ExpectedXLabel(index)), ...
                    string(specs.ExpectedYLabel(index)));
                if ~isfile(imagePath)
                    continue;
                end
                info=imfinfo(imagePath);
                sourceHash=sixgr.integration.qualification. ...
                    FullStackRunContext.fileHash(source);
                imageHash=sixgr.integration.qualification. ...
                    FullStackRunContext.fileHash(imagePath);
                rows(end+1,1)=struct( ... %#ok<AGROW>
                    "ImageFile",char(specs.FileName(index)), ...
                    "SourceCSV",char(sourceNames(1)), ...
                    "SourceCSV_SHA256",char(sourceHash), ...
                    "PNG_SHA256",char(imageHash),"Width",info.Width, ...
                    "Height",info.Height,"Title",char(specs.ExpectedTitle(index)), ...
                    "XLabel",char(specs.ExpectedXLabel(index)), ...
                    "YLabel",char(specs.ExpectedYLabel(index)), ...
                    "AxesCount",1,"SeriesCount",1, ...
                    "FinitePointCount",height(T),"Status","PASS");
            end
            if isempty(rows)
                audit=struct2table(repmat(localImageAuditRow(),0,1), ...
                    "AsArray",true);
            else
                audit=struct2table(rows,"AsArray",true);
            end
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_image_semantic_audit.csv"),audit);
        end
    end
end

function localPlot(T,path,titleText,xText,yText)
fig=figure("Visible","off","Color","w","Position",[20 20 1200 700]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig);hold(ax,"on");
if ismember("CompletenessPct",string(T.Properties.VariableNames))
    y=double(T.CompletenessPct);
elseif ismember("Status",string(T.Properties.VariableNames))
    y=double(upper(string(T.Status))=="PASS");
else
    numericNames=string(T.Properties.VariableNames( ...
        varfun(@isnumeric,T,"OutputFormat","uniform")));
    if isempty(numericNames)
        y=zeros(height(T),1);
    else
        y=double(T.(char(numericNames(1))));
    end
end
y=y(:);x=(1:numel(y))';
bar(ax,x,y,0.72,"FaceColor",[0.05 0.55 0.48], ...
    "EdgeColor",[0.03 0.25 0.23]);
grid(ax,"on");box(ax,"on");
title(ax,titleText,"Interpreter","none","FontWeight","bold");
xlabel(ax,xText,"Interpreter","none");ylabel(ax,yText,"Interpreter","none");
xlim(ax,[0.25,max(1.75,numel(y)+0.75)]);
set(ax,"FontName","Segoe UI","FontSize",10);
exportgraphics(fig,path,"Resolution",100);
end

function row=localFailureRow(varargin)
row=struct("RunID","","FailureID","","SubcaseID","","Domain","", ...
    "Severity","ERROR","FailureCode","","FirstEvidenceArtifactID","", ...
    "RootCauseStatus","OPEN","Resolution","Requires correction and rerun.", ...
    "Status","FAIL");
if nargin==0,return;end
ctx=varargin{1};index=varargin{2};subID=varargin{3};
domain=varargin{4};code=varargin{5};evidence=varargin{6};
row.RunID=char(ctx.RunID);row.FailureID=char("FAIL-"+compose("%05d",index));
row.SubcaseID=char(subID);row.Domain=char(domain);
row.FailureCode=char(code);row.FirstEvidenceArtifactID=char(evidence);
end

function row=localImageAuditRow()
row=struct("ImageFile","","SourceCSV","","SourceCSV_SHA256","", ...
    "PNG_SHA256","","Width",0,"Height",0,"Title","","XLabel","", ...
    "YLabel","","AxesCount",0,"SeriesCount",0,"FinitePointCount",0, ...
    "Status","FAIL");
end

function path=localFindUniqueOrEmpty(artifactIndex,name)
[path,uniquePath]=sixgr.integration.qualification. ...
    RunArtifactIndex.findUnique(artifactIndex,name);
if ~uniquePath,path="";end
end

function out=localList(value)
out=strip(split(string(value),"|"));
out=out(strlength(out)>0);
end

function value=localUTC()
value=string(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
