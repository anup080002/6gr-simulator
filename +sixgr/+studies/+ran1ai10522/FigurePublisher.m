classdef FigurePublisher
    %FIGUREPUBLISHER Source-CSV-only raster figure replay and manifest.

    methods (Static)
        function manifest = replay(runFolder, cfg, context, includeResults)
            if nargin<4, includeResults=true; end
            runFolder=string(runFolder); specs=localSpecs(logical(includeResults));
            rows=repmat(localManifestRow(),numel(specs),1);
            for k=1:numel(specs)
                spec=specs(k); source=fullfile(runFolder,replace(spec.SourceCsv,"/",filesep));
                if exist(source,"file")~=2
                    error("sixgr:ran1ai10522:MissingFigureSource", ...
                        "Figure %s source is missing: %s.",spec.FigureId,source);
                end
                T=readtable(source,"Delimiter",",","VariableNamingRule","preserve");
                if height(T)==0
                    error("sixgr:ran1ai10522:EmptyFigureSource", ...
                        "Figure %s source contains no rows.",spec.FigureId);
                end
                fig=figure("Visible","off","Color","white","Units","pixels", ...
                    "Position",[20 20 double(cfg.study.execution.image_width_px) ...
                    double(cfg.study.execution.image_height_px)]);
                cleanup=onCleanup(@()close(fig));
                localRender(fig,spec,T);
                out=fullfile(runFolder,replace(spec.PNGPath,"/",filesep));
                parent=fileparts(out); if ~isfolder(parent),mkdir(parent);end
                sixgr.util.exportFigureArtifact(fig,out,"Resolution", ...
                    double(cfg.study.execution.image_resolution_dpi));
                sixgr.csi.canonicalizeStudyPNG(out);
                info=imfinfo(out); pixels=double(imread(out)); nonblank=std(pixels,0,"all")>0;
                if info.Width<800 || info.Height<450 || ~nonblank
                    error("sixgr:ran1ai10522:InvalidRasterFigure", ...
                        "Figure %s failed dimension/nonblank audit.",spec.FigureId);
                end
                rows(k)=struct("FigureId",spec.FigureId,"Title",spec.Title, ...
                    "EvidenceClass",spec.EvidenceClass,"ScenarioIds",spec.ScenarioIds, ...
                    "SourceCsv",spec.SourceCsv,"SourceCsvSHA256",sixgr.csi.studyFileSHA256(source), ...
                    "Plotter","sixgr.studies.ran1ai10522.FigurePublisher", ...
                    "PNGPath",spec.PNGPath,"PNGSHA256",sixgr.csi.studyFileSHA256(out), ...
                    "WidthPx",info.Width,"HeightPx",info.Height,"NonBlank",nonblank, ...
                    "RasterOnly",true,"DataReplayCheck",true,"TDocReady",false, ...
                    "Status","PASS","Limitation",spec.Limitation);
            end
            manifest=struct2table(rows,"AsArray",true);
            sixgr.studies.ran1ai10522.ResultWriter.write( ...
                fullfile(runFolder,"manifests","figure_manifest.csv"),manifest,context);
        end
    end
end

function specs=localSpecs(includeResults)
S={ ...
"FIG-1-1","Scope and evidence design principle","CONCEPTUAL_DIAGRAM","A-Q","manifests/scenario_matrix.csv","figures/conceptual/tdoc_fig_1_1_scope_design_principle.png","Conceptual status map; not measured performance"; ...
"FIG-3-1","Container-agnostic profile","CONCEPTUAL_DIAGRAM","A","csv/deterministic/tdoc_table_3_1_container_alternatives.csv","figures/conceptual/tdoc_fig_3_1_container_agnostic_profile.png","Deterministic container semantics"; ...
"FIG-3-2","Implicit L and floor/remainder placement","ANALYTICAL_DERIVATION","A","csv/deterministic/dmrs_time_profile.csv","figures/conceptual/tdoc_fig_3_2_implicit_L_and_placement.png","Exact derivation, not BLER evidence"; ...
"FIG-3-3","Nested group-start family","ANALYTICAL_DERIVATION","C","csv/deterministic/nested_family.csv","figures/conceptual/tdoc_fig_3_3_nested_group_start_family.png","Exact nested-set derivation"; ...
"FIG-3-4","Target UE potential DMRS set","ANALYTICAL_DERIVATION","C","csv/deterministic/nested_family.csv","figures/conceptual/tdoc_fig_3_4_target_ue_potential_dmrs_set.png","Potential set is maximum family minus own set"; ...
"FIG-3-5","Cross-slot profile options","CONCEPTUAL_DIAGRAM","D","manifests/scenario_matrix.csv","figures/conceptual/tdoc_fig_3_5_cross_slot_profile_options.png","Cross-slot waveform evidence remains blocked"; ...
"FIG-4-1","FD-DMRS down-selection criteria","ANALYTICAL_DERIVATION","E-F","csv/deterministic/fd_occ_cdm_validity.csv","figures/conceptual/tdoc_fig_4_1_fd_dmrs_downselection_criteria.png","Structural containment only"; ...
"FIG-4-2","Continuous sequence indexing","ANALYTICAL_DERIVATION","G","csv/deterministic/dmrs_sequence_metrics.csv","figures/conceptual/tdoc_fig_4_2_continuous_sequence_indexing.png","Sequence index mapping, not correlation performance"; ...
"FIG-5-1","RF processing-region abstraction","CONCEPTUAL_DIAGRAM","I","csv/deterministic/bundle_map.csv","figures/conceptual/tdoc_fig_5_1_rf_processing_region_abstraction.png","Configured zero-based PRB regions"; ...
"FIG-5-2","Region bundle restart","ANALYTICAL_DERIVATION","I","csv/deterministic/bundle_map.csv","figures/conceptual/tdoc_fig_5_2_region_bundle_restart.png","Exact anchored bundle construction"; ...
"FIG-5-3","TB versus region partition","CONCEPTUAL_DIAGRAM","M","csv/deterministic/tb_mapping_metrics.csv","figures/conceptual/tdoc_fig_5_3_tb_vs_region_processing_partition.png","Candidate multi-TB waveform is blocked"; ...
"FIG-5-4","Bundle-preserving interleaving","ANALYTICAL_DERIVATION","J","csv/deterministic/interleaver_map.csv","figures/conceptual/tdoc_fig_5_4_bundle_preserving_interleaving.png","Complete-bundle permutation"; ...
"FIG-5-5","Common versus region PT-RS","ANALYTICAL_DERIVATION","L","csv/deterministic/ptrs_phase_metrics.csv","figures/conceptual/tdoc_fig_5_5_common_vs_region_ptrs.png","Analytical phase model only"; ...
"FIG-7-1","Evidence gates","CONCEPTUAL_DIAGRAM","A-Q","manifests/proposal_evidence_matrix.csv","figures/conceptual/tdoc_fig_7_1_evidence_gates.png","Unsupported proposals remain visibly gated"};
if includeResults
S=[S;{ ...
"RFIG-BL-1","Canonical PDSCH BLER anchor","CONTROLLED_LLS","B","csv/controlled/bler_points.csv","figures/diagnostic/baseline_pdsch_bler_vs_snr.png","Bounded low-count NR baseline; statistically incomplete"; ...
"RFIG-GP-1","Canonical PDSCH goodput anchor","CONTROLLED_LLS","B","csv/controlled/goodput_points.csv","figures/diagnostic/baseline_pdsch_goodput_vs_snr.png","Bounded low-count NR baseline; statistically incomplete"; ...
"RFIG-CE-1","Canonical receiver CE NMSE anchor","CONTROLLED_LLS","B","csv/controlled/ce_nmse_points.csv","figures/diagnostic/baseline_pdsch_ce_nmse_vs_snr.png","Receiver-measured bounded baseline"; ...
"RFIG-SINR-1","Canonical receiver post-equalization SINR","CONTROLLED_LLS","B","csv/controlled/posteq_sinr_points.csv","figures/diagnostic/baseline_pdsch_posteq_sinr.png","Receiver-derived bounded baseline"; ...
"RFIG-RT-1","Canonical point runtime","CONTROLLED_LLS","B","csv/controlled/runtime_metrics.csv","figures/diagnostic/baseline_pdsch_runtime.png","Runtime for bounded local execution"}];
end
specs=repmat(struct("FigureId","","Title","","EvidenceClass","", ...
    "ScenarioIds","","SourceCsv","","PNGPath","","Limitation",""),size(S,1),1);
for k=1:size(S,1)
    specs(k)=struct("FigureId",string(S{k,1}),"Title",string(S{k,2}), ...
        "EvidenceClass",string(S{k,3}),"ScenarioIds",string(S{k,4}), ...
        "SourceCsv",string(S{k,5}),"PNGPath",string(S{k,6}), ...
        "Limitation",string(S{k,7}));
end
end

function localRender(fig,spec,T)
ax=axes(fig); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
id=spec.FigureId;
switch id
    case "FIG-1-1"
        values=double(string(T.ExecutionStatus)=="PASS"); bar(ax,values,'FaceColor',[.12 .45 .55]);
        xticks(ax,1:height(T)); xticklabels(ax,string(T.Family)); ylabel(ax,"Exact gate pass (1/0)");
    case "FIG-3-1"
        bar(ax,ones(height(T),1),'FaceColor',[.25 .55 .35]); xticks(ax,1:height(T)); xticklabels(ax,string(T.Container)); ylabel(ax,"Equivalent profile mapping");
    case "FIG-3-2"
        q=T(T.Valid & T.NSym==14 & T.X==1 & T.FirstOffset==0,:);
        scatter(ax,q.G,q.DerivedL,30,q.DerivedL,'filled'); xlabel(ax,"Maximum start spacing G (symbols)"); ylabel(ax,"Derived L (groups)");
    case "FIG-3-3"
        for k=1:height(T), v=localPipeNumbers(T.GroupStartSymbols(k)); scatter(ax,v,repmat(T.L(k),size(v)),45,'filled'); end
        xlabel(ax,"Group-start symbol"); ylabel(ax,"Family member L");
    case "FIG-3-4"
        count=arrayfun(@(k)numel(localPipeNumbers(T.PotentialSet(k))),1:height(T));
        stairs(ax,T.L,count,'-o','LineWidth',1.8); xlabel(ax,"Own L"); ylabel(ax,"Potential co-scheduled-only starts");
    case "FIG-3-5"
        q=T(string(T.Family)=="D",:); bar(ax,double(string(q.ExecutionStatus)=="PASS"),'FaceColor',[.75 .35 .25]); ylim(ax,[0 1.2]); ylabel(ax,"Executed gate"); xticklabels(ax,"cross-slot");
    case "FIG-4-1"
        scatter(ax,T.FDOCCLength,T.BundleSizePRB,60,T.OrphanRE,'filled'); colorbar(ax); xlabel(ax,"FD-OCC length (RE)"); ylabel(ax,"Bundle size (PRB)");
    case "FIG-4-2"
        q=T(T.AllocationPRB==24 & T.BundleSizePRB==4,:); modes=unique(string(q.Mode),"stable");
        for m=1:numel(modes), z=q(string(q.Mode)==modes(m),:); plot(ax,z.ElementIndex,z.SequenceIndex,'LineWidth',1.5,'DisplayName',modes(m)); end
        legend(ax,"Location","best"); xlabel(ax,"Nominal PRB index"); ylabel(ax,"Sequence index");
    case "FIG-5-1"
        q=T(T.BundleSizePRB==4,:); for k=1:height(q), plot(ax,[q.StartPRB(k) q.EndPRB(k)],[q.RegionId(k) q.RegionId(k)],'-','LineWidth',5); end
        xlabel(ax,"PRB index"); ylabel(ax,"Processing region");
    case "FIG-5-2"
        q=T(T.BundleSizePRB==4,:); scatter(ax,q.StartPRB,q.BundleId,45,q.RegionId,'filled'); xlabel(ax,"Region-anchored bundle start (PRB)"); ylabel(ax,"Global bundle ID");
    case "FIG-5-3"
        bar(ax,T.TransportBlockCount,'FaceColor',[.35 .42 .68]); xticks(ax,1:height(T)); xticklabels(ax,string(T.Mode)); ylabel(ax,"Independent TB count");
    case "FIG-5-4"
        modes=unique(string(T.Mode),"stable"); for m=1:numel(modes),q=T(string(T.Mode)==modes(m),:); plot(ax,q.InputBundleId,q.OutputBundleId,'-o','DisplayName',modes(m));end
        legend(ax,"Location","best"); xlabel(ax,"Input bundle ID"); ylabel(ax,"Output bundle ID");
    case "FIG-5-5"
        plot(ax,T.DeltaF_Hz,T.ResidualPhase_deg,'-s','LineWidth',1.8); xlabel(ax,"Residual frequency offset (Hz)"); ylabel(ax,"Residual phase (degrees)");
    case "FIG-7-1"
        bar(ax,double(T.ClaimSupported),'FaceColor',[.55 .3 .55]); xticks(ax,1:height(T)); xlabel(ax,"Proposal number"); ylabel(ax,"Claim supported (1/0)"); ylim(ax,[0 1.2]);
    case "RFIG-BL-1"
        errorbar(ax,T.SNR_dB,T.BLER,T.BLER-T.BLER_CI_Low,T.BLER_CI_High-T.BLER,'-o','LineWidth',1.6); xlabel(ax,"Configured Es/N0 (dB)"); ylabel(ax,"Transport-block error rate"); ylim(ax,[0 1]);
    case "RFIG-GP-1"
        plot(ax,T.SNR_dB,T.Goodput_Mbps,'-s','LineWidth',1.8); xlabel(ax,"Configured Es/N0 (dB)"); ylabel(ax,"Goodput (Mbit/s)");
    case "RFIG-CE-1"
        plot(ax,T.SNR_dB,T.CENMSE_dB,'-^','LineWidth',1.8); xlabel(ax,"Configured Es/N0 (dB)"); ylabel(ax,"Channel-estimate NMSE (dB)");
    case "RFIG-SINR-1"
        plot(ax,T.SNR_dB,T.PostEqSINR_dB,'-d','LineWidth',1.8); plot(ax,T.SNR_dB,T.SNR_dB,'--','Color',[.3 .3 .3]); xlabel(ax,"Configured Es/N0 (dB)"); ylabel(ax,"Receiver post-EQ SINR (dB)"); legend(ax,["Measured","y=x"],"Location","best");
    case "RFIG-RT-1"
        bar(ax,T.SNR_dB,T.Runtime_s,'FaceColor',[.25 .55 .55]); xlabel(ax,"Configured Es/N0 (dB)"); ylabel(ax,"Runtime (s)");
    otherwise
        error("sixgr:ran1ai10522:UnknownFigure","No renderer for %s.",id);
end
title(ax,spec.Title,"Interpreter","none");
subtitle(ax,spec.EvidenceClass+" | "+spec.ScenarioIds,"Interpreter","none");
set(ax,"FontName","Arial","FontSize",11); hold(ax,"off");
end

function v=localPipeNumbers(value)
value=string(value); if strlength(value)==0,v=zeros(1,0);else,v=str2double(split(value,"|")).';end
end

function row=localManifestRow()
row=struct("FigureId","","Title","","EvidenceClass","","ScenarioIds","", ...
    "SourceCsv","","SourceCsvSHA256","","Plotter","","PNGPath","", ...
    "PNGSHA256","","WidthPx",NaN,"HeightPx",NaN,"NonBlank",false, ...
    "RasterOnly",true,"DataReplayCheck",false,"TDocReady",false, ...
    "Status","FAIL","Limitation","");
end
