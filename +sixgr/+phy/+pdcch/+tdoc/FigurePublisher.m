classdef FigurePublisher
    %FIGUREPUBLISHER Publish PNG-only, source-bound PDCCH TDoc figures.

    methods (Static)
        function row = publish(runRoot, name, source, evidenceClass, configHash, varargin)
            p=inputParser;p.addParameter("ScenarioID",name);p.addParameter("Title",name);
            p.addParameter("Render","auto");p.addParameter("XField","");p.addParameter("YField","");
            p.addParameter("GroupField","");p.addParameter("DPI",300);p.addParameter("TDocFigureNumber","");
            p.parse(varargin{:});opt=p.Results;
            if ~istable(source)||isempty(source)
                error("sixgr:phy:pdcch:tdoc:EmptyFigureSource","Figure %s has no source rows.",name);
            end
            evidenceClass=sixgr.phy.pdcch.tdoc.EvidenceClass.require(evidenceClass);
            sixgr.phy.pdcch.tdoc.EvidenceClass.assertPrimaryTruth(source);
            csvDir=fullfile(runRoot,"tables");matDir=fullfile(runRoot,"raw");figDir=fullfile(runRoot,"figures");
            sixgr.util.ensureFolder(csvDir);sixgr.util.ensureFolder(matDir);sixgr.util.ensureFolder(figDir);
            csvPath=fullfile(csvDir,name+".csv");matPath=fullfile(matDir,name+".mat");pngPath=fullfile(figDir,name+".png");
            sixgr.util.csvWriteTable(csvPath,source);sourceTable=source;save(matPath,"sourceTable","-v7");
            fig=figure("Visible","off","Color","w","Position",[100 100 1800 1080],"InvertHardcopy","off");clean=onCleanup(@()localClose(fig));
            localRender(fig,source,string(opt.Render),string(opt.XField),string(opt.YField),string(opt.GroupField),string(opt.Title));
            sixgr.visual.exportRasterAtomic(fig,string(pngPath),double(opt.DPI));close(fig);clear clean;
            info=imfinfo(pngPath);sourceHash=localHash(csvPath);imageHash=localHash(pngPath);
            metadata=struct("figure_file",localRelative(pngPath,runRoot),"scenario_id",string(opt.ScenarioID), ...
                "evidence_class",evidenceClass,"source_csv",localRelative(csvPath,runRoot), ...
                "source_mat",localRelative(matPath,runRoot),"source_sha256",sourceHash,"image_sha256",imageHash, ...
                "width_px",info.Width,"height_px",info.Height,"dpi",double(opt.DPI),"config_hash",configHash, ...
                "tdoc_figure_number",string(opt.TDocFigureNumber),"status","PASS");
            metaPath=fullfile(figDir,name+".json");sixgr.util.jsonWrite(metaPath,metadata);
            row=table(name,string(opt.ScenarioID),evidenceClass,string(opt.TDocFigureNumber),"PASS", ...
                string(localRelative(pngPath,runRoot)),string(localRelative(csvPath,runRoot)), ...
                string(localRelative(matPath,runRoot)),string(localRelative(metaPath,runRoot)), ...
                info.Width,info.Height,double(opt.DPI),imageHash,sourceHash,false, ...
                'VariableNames',{'FigureFile','ScenarioID','EvidenceClass','TDocFigureNumber','AuditStatus', ...
                'ImagePath','SourceCSV','SourceMAT','MetadataPath','WidthPx','HeightPx','DPI', ...
                'ImageSHA256','SourceSHA256','TDocGradeEligible'});
        end
    end
end

function localRender(fig,T,render,xField,yField,groupField,titleText)
ink=[.06 .08 .12];ax=axes(fig);hold(ax,"on");set(ax,"Color","w","FontSize",11,"GridColor",[.70 .73 .78], ...
    "XColor",ink,"YColor",ink,"LineWidth",1);
names=string(T.Properties.VariableNames);
if render=="auto"
    if all(ismember(["X","Y","Label"],names)),render="flow";
    elseif any(ismember(["StartRB","StartMHz","StartCCE"],names)),render="regions";
    else,render="line";end
end
switch render
    case "flow"
        x=double(T.X);flowY=.32*ones(size(x));
        set(ax,"Position",[.04 .18 .92 .68]);
        plot(ax,x,flowY,"-","LineWidth",2.5,"Color",[.12 .36 .65]);
        scatter(ax,x,flowY,170,[.05 .55 .45],"filled");
        for i=1:height(T)
            text(ax,x(i),.58,string(T.Label(i)),"HorizontalAlignment","center", ...
                "Interpreter","none","Color",ink,"FontWeight","bold","FontSize",11);
        end
        xlim(ax,[min(x)-.45 max(x)+.45]);ylim(ax,[0 1]);axis(ax,"manual");axis(ax,"off");
    case "regions"
        startName=names(find(startsWith(names,"Start"),1));widthName=names(find(startsWith(names,["Size","Width"]),1));
        if ismember("Lane",names),lane=double(T.Lane);else,lane=(1:height(T))';end
        for i=1:height(T),rectangle(ax,"Position",[double(T.(startName)(i)),lane(i)-.35,double(T.(widthName)(i)),.7], ...
                "FaceColor",[.15 .58 .78 .45],"EdgeColor",[.03 .23 .43]);end
        yticks(ax,unique(lane));grid(ax,"on");
    otherwise
        [xField,yField]=localFields(T,xField,yField);x=double(T.(xField));y=double(T.(yField));
        if strlength(groupField)>0&&ismember(groupField,names)
            groups=string(T.(groupField));
            for group=unique(groups,"stable").',[sx,order]=sort(x(groups==group));sy=y(groups==group);sy=sy(order);plot(ax,sx,sy,"-o","LineWidth",1.5,"DisplayName",group);end
            legend(ax,"Location","bestoutside","Interpreter","none");
        elseif render=="bar",bar(ax,x,y,"FaceColor",[.12 .55 .78]);
        elseif render=="scatter",scatter(ax,x,y,55,[.12 .55 .78],"filled");
        else,[x,order]=sort(x);plot(ax,x,y(order),"-o","LineWidth",1.7,"MarkerFaceColor",[.12 .55 .78]);end
        xlabel(ax,xField,"Interpreter","none");ylabel(ax,yField,"Interpreter","none");grid(ax,"on");
        if contains(lower(yField),"bler")
            if all(isfinite(y))&&all(y>0)
                set(ax,"YScale","log");
            else
                set(ax,"YScale","linear");ylim(ax,[0 1]);
            end
        end
end
title(ax,titleText,"Interpreter","none","FontWeight","bold","Color",ink);
set(get(ax,"XLabel"),"Color",ink);set(get(ax,"YLabel"),"Color",ink);
end

function [x,y]=localFields(T,x,y)
names=string(T.Properties.VariableNames);numeric=false(size(names));
for i=1:numel(names),numeric(i)=isnumeric(T.(names(i)))||islogical(T.(names(i)));end
available=names(numeric);
if strlength(x)==0,x=available(1);end
if strlength(y)==0,y=available(min(2,numel(available)));end
end
function localClose(fig),if isgraphics(fig),close(fig);end,end
function hash=localHash(path),fid=fopen(path,"r");clean=onCleanup(@()fclose(fid));hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));end
function out=localRelative(path,root),path=string(path);root=string(root);prefix=root+filesep;if startsWith(path,prefix,"IgnoreCase",ispc),out=extractAfter(path,strlength(prefix));else,out=path;end;out=replace(out,"\","/");end
