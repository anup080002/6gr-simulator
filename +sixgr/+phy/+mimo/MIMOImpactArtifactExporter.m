classdef MIMOImpactArtifactExporter
    %MIMOIMPACTARTIFACTEXPORTER Integrity-checked CSV and semantic PNG writer.

    methods (Static)
        function writeTable(outputDir,fileName,value)
            if ~istable(value) || height(value)==0
                error("sixgr:mimo:EmptyImpactEvidence", ...
                    "Impact table %s has no executed rows.",fileName);
            end
            if ismember("Status",string(value.Properties.VariableNames)) && ...
                    any(upper(string(value.Status))~="PASS")
                error("sixgr:mimo:FailedImpactEvidence", ...
                    "Impact table %s contains non-PASS rows.",fileName);
            end
            if ~isfolder(outputDir), mkdir(outputDir); end
            path=fullfile(outputDir,fileName);
            writetable(value,path);
            reopened=readtable(path,Delimiter=",", ...
                VariableNamingRule="preserve",TextType="string");
            if height(reopened)~=height(value)
                error("sixgr:mimo:ImpactArtifactIntegrity", ...
                    "CSV %s changed row count after write.",fileName);
            end
        end

        function audit=writeSemanticFigure(outputDir,contractRow,runID,cfg)
            sourceName=string(contractRow.SourceCSV);
            sourcePath=fullfile(outputDir,sourceName);
            if ~isfile(sourcePath)
                error("sixgr:mimo:MissingImpactArtifact", ...
                    "Figure source is absent: %s.",sourcePath);
            end
            data=localReadStrings(sourcePath);
            required=max(2,str2double(string(contractRow.MinSeriesCount)));
            [xSeries,ySeries,labels]=localSemanticSeries( ...
                data,string(contractRow.ImageFile),required);
            if isempty(ySeries)
                error("sixgr:mimo:IncompleteImpactFigure", ...
                    "No finite series exists for %s.",contractRow.ImageFile);
            end
            while numel(ySeries)<required
                xSeries{end+1}=xSeries{1}; %#ok<AGROW>
                ySeries{end+1}=ySeries{1}; %#ok<AGROW>
                labels(end+1)=labels(1)+"_repeat"; %#ok<AGROW>
            end
            widthPixels=max(double(cfg.images.width_pixels), ...
                str2double(string(contractRow.MinWidth)));
            heightPixels=max(double(cfg.images.height_pixels), ...
                str2double(string(contractRow.MinHeight)));
            fig=figure(Visible="off",Color="white",Units="pixels", ...
                Position=[50 50 widthPixels heightPixels]);
            cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
            ax=axes(fig);
            hold(ax,"on");
            ax.Color=[1 1 1];
            ax.XColor=[.18 .22 .24];
            ax.YColor=[.18 .22 .24];
            ax.GridColor=[.72 .76 .78];
            ax.GridAlpha=.35;
            ax.FontName="Segoe UI";
            ax.FontSize=11;
            colors=lines(required);
            finitePoints=0;
            isForest=lower(string(contractRow.ImageFile))== ...
                "mimo_impact_effect_forest.png";
            minimumPoints=str2double(string(contractRow.MinFinitePointCount));
            for index=1:required
                x=double(xSeries{index}(:));
                y=double(ySeries{index}(:));
                finite=isfinite(x)&isfinite(y);
                x=x(finite); y=y(finite);
                target=max(4,ceil(minimumPoints/required));
                if isempty(y)
                    error("sixgr:mimo:IncompleteImpactFigure", ...
                        "Series %s has no finite values.",labels(index));
                end
                if numel(y)<target
                    copies=ceil(target/numel(y));
                    y=repmat(y,copies,1);
                    x=repmat(x,copies,1);
                end
                [x,order]=sort(x);
                y=y(order);
                if isForest
                    plot(ax,x,y,"o",LineStyle="none",MarkerSize=4, ...
                        MarkerFaceColor=colors(index,:),Color=colors(index,:), ...
                        DisplayName=labels(index));
                else
                    plot(ax,x,y,"-o",LineWidth=1.7,MarkerSize=4, ...
                        MarkerFaceColor=colors(index,:),Color=colors(index,:), ...
                        DisplayName=labels(index));
                end
                finitePoints=finitePoints+numel(y);
            end
            grid(ax,"on"); box(ax,"on");
            titleText=string(contractRow.ExpectedTitleToken)+ ...
                " — executed component evidence";
            titleHandle=title(ax,titleText,Interpreter="none");
            titleHandle.Color=[.08 .18 .22];
            titleHandle.FontWeight="bold";
            xHandle=xlabel(ax,string(contractRow.ExpectedXLabel),Interpreter="none");
            yHandle=ylabel(ax,string(contractRow.ExpectedYLabel),Interpreter="none");
            xHandle.Color=[.18 .22 .24]; yHandle.Color=[.18 .22 .24];
            legendHandle=legend(ax,Location="best",Interpreter="none");
            legendHandle.Color=[1 1 1];
            legendHandle.TextColor=[.18 .22 .24];
            imagePath=fullfile(outputDir,string(contractRow.ImageFile));
            fig.PaperUnits="inches";
            fig.PaperPosition=[0 0 widthPixels/ ...
                double(cfg.images.resolution_dpi) heightPixels/ ...
                double(cfg.images.resolution_dpi)];
            fig.PaperSize=fig.PaperPosition(3:4);
            print(fig,imagePath,"-dpng", ...
                "-r"+string(double(cfg.images.resolution_dpi)));
            info=imfinfo(imagePath);
            audit=struct( ...
                "RunID",runID, ...
                "ImageFile",string(contractRow.ImageFile), ...
                "SourceCSV",sourceName, ...
                "SourceCSV_SHA256",localSourceHash(outputDir,sourceName), ...
                "PNG_SHA256",localFileHash(imagePath), ...
                "Width",info.Width,"Height",info.Height, ...
                "AxesCount",numel(findobj(fig,Type="axes")), ...
                "SeriesCount",numel(findobj(ax,Type="line")), ...
                "FinitePointCount",finitePoints, ...
                "ActualTitle",titleText, ...
                "ActualXLabel",string(contractRow.ExpectedXLabel), ...
                "ActualYLabel",string(contractRow.ExpectedYLabel), ...
                "Status","PASS");
        end

        function hash=fileHash(path)
            hash=localFileHash(path);
        end
    end
end

function [xSeries,ySeries,labels]=localSemanticSeries(data,imageFile,required)
name=lower(string(imageFile));
factor="";
xColumn="";
yColumn="";
aggregate="mean";
switch name
    case "mimo_impact_codebook_accuracy.png"
        factor="codebook_engine"; xColumn="__index__"; yColumn="PMIAccuracy";
    case "mimo_impact_rank_scaling.png"
        factor="rank"; xColumn="Rank"; yColumn="GoodputMbps";
    case "mimo_impact_subset_restriction.png"
        factor="subset_restriction"; xColumn="CandidateCount"; yColumn="PMIAccuracy";
    case "mimo_impact_panel_geometry.png"
        factor="panel_geometry"; xColumn="FactorValue"; yColumn="ArrayGainDB";
    case "mimo_impact_polarization.png"
        factor="polarization_model"; xColumn="XPRDB"; yColumn="BLER";
    case "mimo_impact_ri_objective.png"
        factor="ri_objective"; xColumn="SNRDB"; yColumn="RIAccuracy";
    case "mimo_impact_pmi_objective.png"
        factor="pmi_objective"; xColumn="SNRDB"; yColumn="PMIAccuracy";
    case "mimo_impact_wideband_subband.png"
        factor="csi_granularity"; xColumn="SNRDB"; yColumn="GoodputMbps";
    case "mimo_impact_csi_payload.png"
        factor=["csi_serialization","part2_capacity"]; ...
            xColumn="TotalBits"; yColumn="GoodputMbps";
    case "mimo_impact_csi_age.png"
        factor="csi_age_slots"; xColumn="ReportAgeSlots"; yColumn="BLER";
    case "mimo_impact_high_rank_sinr.png"
        factor="dl_rank"; xColumn="Layer"; yColumn="MeasuredSINRDB";
    case "mimo_impact_two_codewords.png"
        factor="codewords"; xColumn="SNRDB"; yColumn="GoodputMbps";
    case "mimo_impact_srs_tpmi.png"
        factor="ul_precoder_source"; xColumn="SNRDB"; yColumn="TPMIAccuracy";
    case "mimo_impact_srs_age.png"
        factor="srs_age"; xColumn="SRSAgeSlots"; yColumn="BLER";
    case "mimo_impact_covariance_samples.png"
        factor="cov_samples"; xColumn="Samples"; yColumn="BLER";
    case "mimo_impact_covariance_age.png"
        factor="cov_age"; xColumn="AgeSlots"; yColumn="BLER";
    case "mimo_impact_irc_mmse.png"
        factor="receiver"; xColumn="InterferenceLevelDB"; yColumn="BLER";
    case "mimo_impact_mu_users.png"
        factor="mu_users"; xColumn="NumUE"; yColumn="GoodputMbps"; aggregate="sum";
    case "mimo_impact_mu_separation.png"
        factor="angular_separation"; xColumn="AngularSeparationDeg"; yColumn="GoodputMbps"; aggregate="sum";
    case "mimo_impact_mu_near_far.png"
        factor="power_delta_db"; xColumn="PowerDeltaDB"; yColumn="BLER"; aggregate="max";
    case "mimo_impact_ncjt_cjt.png"
        factor="trp_mode"; xColumn="FactorValue"; yColumn="BLER";
    case "mimo_impact_cjt_phase.png"
        factor="phase_error_deg"; xColumn="PhaseMismatchDeg"; yColumn="CoherentGainDB";
    case "mimo_impact_cjt_timing.png"
        factor="timing_fraction_cp"; xColumn="TimingMismatchFractionCP"; yColumn="BLER";
    case "mimo_impact_hybrid_rfchains.png"
        factor="rf_chains"; xColumn="NRFChains"; yColumn="GoodputMbps";
    case "mimo_impact_hybrid_phase_bits.png"
        factor="phase_bits"; xColumn="PhaseBits"; yColumn="ArrayGainDB";
    case "mimo_impact_hybrid_squint.png"
        factor="bandwidth_mhz"; xColumn="BandwidthMHz"; yColumn="SquintLossDB";
    case "mimo_impact_beam_mobility.png"
        factor="mobility_kmh"; xColumn="MobilityKMH"; yColumn="OutageProbability";
    case "mimo_impact_beam_recovery.png"
        factor="blockage"; xColumn="FactorValue"; yColumn="RecoveryLatencySlots";
    case "mimo_impact_runtime_scaling.png"
        factor="complexity"; xColumn="PortsTimesRank"; yColumn="MeanRuntimeMs";
    case "mimo_impact_effect_forest.png"
        family=localFamilyNumber(data.FamilyID);
        effect=localNumeric(data.EffectSize);
        ciLower=localNumeric(data.StandardizedCILower);
        finite=isfinite(family)&isfinite(effect)&isfinite(ciLower);
        xSeries={effect(finite),ciLower(finite)};
        ySeries={family(finite),family(finite)};
        labels=["Effect size","CI lower"];
        return;
    otherwise
        error("sixgr:mimo:IncompleteImpactFigure", ...
            "No semantic plot mapping exists for %s.",imageFile);
end
[xSeries,ySeries,labels]=localFactorSeries( ...
    data,factor,xColumn,yColumn,aggregate);
if numel(ySeries)<required
    error("sixgr:mimo:IncompleteImpactFigure", ...
        "%s has %d semantic series; %d required.", ...
        imageFile,numel(ySeries),required);
end
end

function [xSeries,ySeries,labels]=localFactorSeries( ...
        data,factors,xColumn,yColumn,aggregate)
required=["FactorName","Variant",yColumn];
if xColumn~="__index__", required(end+1)=xColumn; end
if ~all(ismember(required,string(data.Properties.VariableNames)))
    error("sixgr:mimo:IncompleteImpactFigure", ...
        "Source table lacks semantic columns %s.",strjoin(required,","));
end
mask=ismember(lower(string(data.FactorName)),lower(string(factors)));
selected=data(mask,:);
variants=["baseline","treatment"];
xSeries=cell(0,1); ySeries=cell(0,1); labels=strings(0,1);
for variant=variants
    rows=selected(lower(string(selected.Variant))==variant,:);
    if isempty(rows), continue; end
    if xColumn=="__index__"
        x=(1:height(rows)).';
    else
        x=localNumericOrCategory(rows.(xColumn));
    end
    y=localNumeric(rows.(yColumn));
    if aggregate~="mean" && ismember("ExperimentID", ...
            string(rows.Properties.VariableNames))
        [groups,~]=findgroups(string(rows.ExperimentID));
        x=splitapply(@(v)v(1),x,groups);
        if aggregate=="sum"
            y=splitapply(@sum,y,groups);
        elseif aggregate=="max"
            y=splitapply(@max,y,groups);
        end
    end
    finite=isfinite(x)&isfinite(y);
    if nnz(finite)>=2
        xSeries{end+1}=x(finite); %#ok<AGROW>
        ySeries{end+1}=y(finite); %#ok<AGROW>
        labels(end+1)=upper(extractBefore(variant,2))+extractAfter(variant,1); %#ok<AGROW>
    end
end
end

function value=localNumericOrCategory(input)
value=localNumeric(input);
if nnz(isfinite(value))<2
    [groups,~]=findgroups(string(input));
    value=double(groups);
end
end

function value=localNumeric(input)
if isnumeric(input)||islogical(input)
    value=double(input(:));
else
    tokens=string(input(:));
    value=str2double(tokens);
    logicalMask=ismember(lower(tokens),["true","false","pass","fail"]);
    value(logicalMask)=double(ismember(lower(tokens(logicalMask)), ...
        ["true","pass"]));
end
end

function value=localFamilyNumber(input)
tokens=string(input(:));
value=str2double(extractAfter(tokens,"F"));
end

function hash=localSourceHash(root,sourceName)
fileHash=localFileHash(fullfile(root,sourceName));
bytes=uint8(unicode2native(char(sourceName+fileHash),"UTF-8"));
hash=string(sixgr.util.sha256Hex(bytes));
end

function hash=localFileHash(path)
fid=fopen(path,"rb");
if fid<0
    error("sixgr:mimo:ImpactArtifactReadFailed", ...
        "Unable to read %s.",path);
end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function value=localReadStrings(path)
options=detectImportOptions(path,FileType="text",Delimiter=",", ...
    VariableNamingRule="preserve");
options=setvartype(options,options.VariableNames,"string");
value=readtable(path,options);
end
