classdef CSITDocStudyFigureManifest
    %FIGUREMANIFEST Contract-driven semantic replay for public CSI figures.

    methods (Static)
        function manifest=replay(runFolder,cfg,context)
            runFolder=string(runFolder);
            [specs,contract]=sixgr.csi.CSITDocStudyFigureContract.load();
            figureDir=fullfile(runFolder,"figures");
            if ~isfolder(figureDir), mkdir(figureDir); end
            manifestPath=fullfile(runFolder,"manifests","figure_manifest.csv");
            prior=table();
            if exist(manifestPath,"file")==2
                prior=readtable(manifestPath,"Delimiter",",", ...
                    "VariableNamingRule","preserve");
            end
            rows=repmat(localManifestRow(),numel(specs),1);
            for k=1:numel(specs)
                spec=specs(k); id=string(spec.figure_id);
                [tables,sources,hashes]=localLoadSources(runFolder,spec);
                localValidateRequiredColumns(spec,sources,tables);
                fig=figure("Visible","off","Color","white","Units","pixels", ...
                    "Position",[50 50 double(cfg.execution.image_width_px) ...
                    double(cfg.execution.image_height_px)]);
                cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
                render=sixgr.csi.CSITDocStudySemanticFigureRenderer.render(fig,spec,tables,cfg);
                if ~logical(render.Pass)
                    error("sixgr:csi:SemanticFigureFailed", ...
                        "Figure %s failed its semantic renderer: %s.",id,render.Details);
                end
                png=fullfile(runFolder,string(spec.png_path));
                pdf=fullfile(runFolder,string(spec.pdf_path));
                sixgr.util.exportFigureArtifact(fig,png,"Resolution", ...
                    double(cfg.execution.image_resolution_dpi));
                sixgr.csi.canonicalizeStudyPNG(png);
                print(fig,pdf,"-dpdf","-painters");
                sixgr.csi.canonicalizeStudyPDF(pdf);
                info=imfinfo(png); pixels=double(imread(png));
                nonblank=std(pixels,0,"all")>0;
                pngHash=sixgr.csi.studyFileSHA256(png);
                pdfHash=sixgr.csi.studyFileSHA256(pdf);
                pHash=localPerceptualHash(png);
                joinedSources=strjoin(sources,"|");
                joinedHashes=strjoin(hashes,"|");
                if ~isempty(prior) && all(ismember(["FigureId", ...
                        "SourceCsvHashes","PNGSha256"], ...
                        string(prior.Properties.VariableNames)))
                    matched=string(prior.FigureId)==id & ...
                        string(prior.SourceCsvHashes)==joinedHashes;
                    if nnz(matched)==1 && string(prior.PNGSha256(matched))~=pngHash
                        error("sixgr:csi:NondeterministicFigureReplay", ...
                            "Figure %s changed PNG hash with unchanged source CSVs.",id);
                    end
                end
                rows(k)=struct("FigureId",id, ...
                    "Title",string(spec.tdoc_caption), ...
                    "EvidenceClass",string(spec.evidence_class), ...
                    "ScenarioIds",localScenario(id), ...
                    "FigureContractSchema",contract.SchemaVersion, ...
                    "FigureContractSHA256",contract.SHA256, ...
                    "ResolvedConfigSHA256",string(context.ConfigHash), ...
                    "SourceCsv",sources(1),"SourceCsvSha256",hashes(1), ...
                    "SourceCsvs",joinedSources,"SourceCsvHashes",joinedHashes, ...
                    "PlotScript","sixgr.csi.CSITDocStudySemanticFigureRenderer."+ ...
                        string(spec.plotter), ...
                    "XColumns",string(spec.x_axis_label), ...
                    "YColumns",string(spec.y_axis_label), ...
                    "GroupColumns",string(spec.series_definition), ...
                    "FilterExpression",string(spec.filter_definition), ...
                    "Aggregation",string(spec.aggregation), ...
                    "IndependentTrials",double(render.IndependentTrials), ...
                    "ConfidenceMethod",string(spec.confidence_interval), ...
                    "RequiredAnnotations",string(spec.required_annotations), ...
                    "Units",string(spec.units), ...
                    "PNGPath",string(spec.png_path),"PNGSha256",pngHash, ...
                    "VectorPath",string(spec.pdf_path),"PDFSha256",pdfHash, ...
                    "PerceptualHash",pHash,"WidthPx",info.Width, ...
                    "HeightPx",info.Height,"NonBlankCheck",nonblank, ...
                    "DataReplayCheck",true,"SemanticAuditStatus","PASS", ...
                    "Status",localIf(nonblank,"PASS","FAIL"), ...
                    "Limitations",string(spec.limitations_text));
            end
            localPerceptualDuplicateGate(rows,runFolder);
            manifest=struct2table(rows,"AsArray",true);
            sixgr.csi.CSITDocStudyResultWriter.write(manifestPath,manifest,context);
            semantic=manifest(:,["FigureId","EvidenceClass", ...
                "PerceptualHash","IndependentTrials","DataReplayCheck", ...
                "SemanticAuditStatus","Status","Limitations"]);
            sixgr.csi.CSITDocStudyResultWriter.write(fullfile(runFolder,"manifests", ...
                "semantic_figure_audit.csv"),semantic,context);
        end
    end
end

function [tables,sources,hashes]=localLoadSources(runFolder,spec)
sources=string(spec.source_csvs(:));
tables=cell(numel(sources),1); hashes=strings(numel(sources),1);
for k=1:numel(sources)
    source=fullfile(runFolder,replace(sources(k),"/",filesep));
    if exist(source,"file")~=2
        error("sixgr:csi:MissingFigureSource", ...
            "Figure %s source CSV is missing: %s.", ...
            string(spec.figure_id),source);
    end
    tables{k}=readtable(source,"Delimiter",",", ...
        "VariableNamingRule","preserve");
    if isempty(tables{k})
        error("sixgr:csi:EmptyFigureSource", ...
            "Figure %s source CSV is empty: %s.",string(spec.figure_id),source);
    end
    hashes(k)=sixgr.csi.studyFileSHA256(source);
end
end

function localValidateRequiredColumns(spec,sources,tables)
requirements=string(spec.required_columns(:));
for k=1:numel(requirements)
    parts=split(requirements(k),"::");
    if numel(parts)~=2
        error("sixgr:csi:BadRequiredColumnContract", ...
            "Figure %s has malformed required_columns entry %s.", ...
            string(spec.figure_id),requirements(k));
    end
    sourceIndex=find(sources==parts(1),1);
    if isempty(sourceIndex)
        error("sixgr:csi:RequiredColumnSourceMissing", ...
            "Figure %s column contract references undeclared source %s.", ...
            string(spec.figure_id),parts(1));
    end
    required=split(parts(2),"|");
    missing=setdiff(required,string(tables{sourceIndex}.Properties.VariableNames));
    if ~isempty(missing)
        error("sixgr:csi:MissingFigureColumn", ...
            "Figure %s source %s is missing %s.",string(spec.figure_id), ...
            parts(1),strjoin(missing,"|"));
    end
end
end

function localPerceptualDuplicateGate(rows,runFolder)
ids=string({rows.FigureId}); paths=string({rows.PNGPath});
vectors=cell(numel(paths),1);
for k=1:numel(paths)
    vectors{k}=localPerceptualVector(fullfile(runFolder,paths(k)));
end
for a=1:numel(paths)-1
    vectorA=vectors{a};
    for b=a+1:numel(paths)
        vectorB=vectors{b};
        similarity=nnz(vectorA&vectorB)/max(nnz(vectorA|vectorB),1);
        if similarity>.995
            error("sixgr:csi:PerceptualDuplicateFigure", ...
                "Figures %s and %s are perceptually near-identical (correlation %.6f).", ...
                ids(a),ids(b),similarity);
        end
    end
end
end

function hash=localPerceptualHash(path)
image=double(imread(path));
if ndims(image)==3, image=mean(image,3); end
small=imresize(image,[32 32],"bilinear"); n=32;
k=(0:n-1).'; sample=0:n-1;
C=sqrt(2/n)*cos(pi*(2*sample+1).*k/(2*n)); C(1,:)=sqrt(1/n);
coeff=C*small*C.'; block=coeff(1:8,1:8); values=block(:);
bits=[false;values(2:end)>=median(values(2:end))];
digits=repmat('0',1,16);
for k=1:16
    value=0;
    for j=1:4, value=value+double(bits((k-1)*4+j))*2^(4-j); end
    digits(k)=upper(dec2hex(value,1));
end
hash=string(digits);
end

function vector=localPerceptualVector(path)
image=double(imread(path)); small=imresize(image,[304 512],"bilinear");
if ndims(small)==3
    chroma=max(small,[],3)-min(small,[],3); vector=chroma(:)>20;
else
    vector=small(:)<230;
end
end

function scenario=localScenario(id)
if id=="FIG-1-1", scenario="A-J"; return; end
tokens=split(id,".");
if numel(tokens)<2, scenario=""; return; end
section=tokens(2);
mapping=containers.Map({'2','3','4','5','6','7','8','9','10','11'}, ...
    {'A','B','C','D','E','F','G','H','I','J'});
if isKey(mapping,char(section)), scenario=string(mapping(char(section)));
else, scenario=""; end
end

function value=localIf(tf,yes,no)
if tf, value=yes; else, value=no; end
end

function row=localManifestRow()
row=struct("FigureId","","Title","","EvidenceClass","", ...
    "ScenarioIds","","FigureContractSchema","", ...
    "FigureContractSHA256","","ResolvedConfigSHA256","", ...
    "SourceCsv","","SourceCsvSha256","","SourceCsvs","", ...
    "SourceCsvHashes","","PlotScript","","XColumns","", ...
    "YColumns","","GroupColumns","","FilterExpression","", ...
    "Aggregation","","IndependentTrials",NaN,"ConfidenceMethod","", ...
    "RequiredAnnotations","","Units","","PNGPath","", ...
    "PNGSha256","","VectorPath","","PDFSha256","", ...
    "PerceptualHash","","WidthPx",NaN,"HeightPx",NaN, ...
    "NonBlankCheck",false,"DataReplayCheck",false, ...
    "SemanticAuditStatus","FAIL","Status","FAIL","Limitations","");
end
