function records = generateConfidentialFigures(runDirectory)
%GENERATECONFIDENTIALFIGURES Generate separated state/procedure validation.

arguments
    runDirectory (1,1) string
end
scenario=jsondecode(fileread(fullfile(char(runDirectory),'config','resolved_config.json')));
outDir=string(scenario.outputs.confidential_dir);
spec={ ...
 'pat_fig_01_ambiguity','Correct-state and wrong-state ambiguity','CALIBRATED_LLS'; ...
 'pat_fig_02_state_matrix','PreCompensationStateMatrix','ARCHITECTURE_DIAGRAM'; ...
 'pat_fig_03_state_aware_estimator','State-aware estimator and UL rule','EVENT_PROCEDURE'; ...
 'pat_fig_04_mismatch_adaptation','Mismatch and network adaptation','EVENT_PROCEDURE'; ...
 'pat_fig_05_ue_flow','UE operational state flow','ARCHITECTURE_DIAGRAM'; ...
 'pat_fig_06_sequence','State-versioned message sequence','EVENT_PROCEDURE'; ...
 'pat_fig_07_architecture','Executable module architecture','ARCHITECTURE_DIAGRAM'; ...
 'val_01_correct_vs_wrong_state_residual_cfo_cdf','Correct versus wrong-state residual CFO CDF','CALIBRATED_LLS'; ...
 'val_02_step_boundary_estimator_bias','Step-boundary estimator bias','CALIBRATED_LLS'; ...
 'val_03_state_version_stale_report_rejection','Stale state report rejection','EVENT_PROCEDURE'; ...
 'val_04_mismatch_classifier_roc','Mismatch classifier ROC','EVENT_PROCEDURE'; ...
 'val_05_mismatch_class_confusion','Mismatch class confusion','EVENT_PROCEDURE'; ...
 'val_06_network_action_outcomes','Network action outcomes','EVENT_PROCEDURE'; ...
 'val_07_post_correction_prach_pusch_success','Post-correction PRACH/PUSCH success','CALIBRATED_LLS'; ...
 'val_08_fdd_rule_scaling_residual','FDD coefficient-rule scaling residual','EVENT_PROCEDURE'};
records=table();
for index=1:size(spec,1)
    name=string(spec{index,1});titleText=string(spec{index,2});evidence=string(spec{index,3});
    [fig,data]=localFigure(runDirectory,name,titleText);
    cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
    rec=sixgr.ntn.resilientsync.report.saveFigureArtifact( ...
        fig,data,runDirectory,outDir,name,evidence,scenario,titleText);
    records=[records;rec]; %#ok<AGROW>
    clear cleanup
end
end

function [fig,data]=localFigure(root,name,titleText)
fig=figure('Visible','off','Color','w','Position',[120 120 1000 620]);
ax=axes(fig);hold(ax,'on');grid(ax,'on');box(ax,'on');
switch name
    case {"pat_fig_01_ambiguity","val_01_correct_vs_wrong_state_residual_cfo_cdf"}
        data=localRead(root,'state_aware_measured_residual');
        localLines(ax,(1:height(data)).',abs(data.PostStateResidual_Hz),data.ProfileId+"/"+data.AppliedState);
        ylabel(ax,'Absolute measured residual CFO (Hz)');xlabel(ax,'Physical observation row');
    case "pat_fig_02_state_matrix"
        data=localRead(root,'compensation_state_matrix');localMatrix(ax,data);
    case {"pat_fig_03_state_aware_estimator"}
        data=localRead(root,'estimator_reference');
        localLines(ax,data.ObservationInterval_s,data.EpsilonRMSE_fractional,data.ProfileId);xlabel(ax,'Observation interval (s)');ylabel(ax,'Oscillator RMSE');
    case "pat_fig_04_mismatch_adaptation"
        data=localRead(root,'network_action_outcomes');bar(ax,categorical(data.NetworkAction),data.Count);ylabel(ax,'Decisions');
    case {"pat_fig_05_ue_flow","pat_fig_06_sequence"}
        data=localRead(root,'transition_events');
        plot(ax,data.EventId,data.OldStateVersion,'-o');plot(ax,data.EventId,data.NewStateVersion,'-s');
        xticks(ax,data.EventId);xticklabels(ax,data.EventType);xtickangle(ax,25);ylabel(ax,'stateVersion');legend(ax,'old','new');
    case "pat_fig_07_architecture"
        data=localRead(root,'compensation_state_matrix');axis(ax,[0 1 0 1]);axis(ax,'off');
        labels=["YAML state","TRS/PRACH measurement","Stable WLS","Mismatch policy","UL correction","PUSCH/PUCCH CRC"];
        for i=1:numel(labels),x=.08+(i-1)*.84/(numel(labels)-1);rectangle(ax,'Position',[x-.06,.43,.12,.14],'Curvature',.1,'FaceColor',[.9 .94 1]);text(ax,x,.5,labels(i),'HorizontalAlignment','center','FontSize',8);end
    case "val_02_step_boundary_estimator_bias"
        data=localRead(root,'step_boundary_validation');
        bar(ax,categorical(data.Window),[abs(data.HandledResidual_Hz),abs(data.UnhandledResidual_Hz)]);ylabel(ax,'Absolute residual CFO (Hz)');legend(ax,'handled','unhandled');
    case "val_03_state_version_stale_report_rejection"
        data=localRead(root,'stale_state_validation');bar(ax,data.ReportedStateVersion,double(data.Accepted));ylim(ax,[0 1.1]);xlabel(ax,'Reported stateVersion');ylabel(ax,'Accepted');
    case "val_04_mismatch_classifier_roc"
        m=localRead(root,'mismatch_classifier');threshold=linspace(0,8,101).';positive=m.TruthClass>0;
        tpr=zeros(size(threshold));fpr=zeros(size(threshold));
        for i=1:numel(threshold),pred=m.AbsoluteNormalizedMismatch>=threshold(i);tpr(i)=sum(pred&positive)/sum(positive);fpr(i)=sum(pred&~positive)/sum(~positive);end
        data=table(threshold,tpr,fpr,'VariableNames',{'ThresholdSigma','TPR','FPR'});plot(ax,data.FPR,data.TPR,'LineWidth',1.8);plot(ax,[0 1],[0 1],'--');xlabel(ax,'False-positive rate');ylabel(ax,'True-positive rate');
    case "val_05_mismatch_class_confusion"
        m=localRead(root,'mismatch_classifier');matrix=confusionmat(m.TruthClass,m.PredictedClass,'Order',[0 1 2]);
        [truth,pred]=ndgrid(0:2,0:2);data=table(truth(:),pred(:),matrix(:),'VariableNames',{'TruthClass','PredictedClass','Count'});
        imagesc(ax,matrix);colorbar(ax);xlabel(ax,'Predicted class');ylabel(ax,'Truth class');
    case "val_06_network_action_outcomes"
        data=localRead(root,'network_action_outcomes');bar(ax,categorical(data.NetworkAction),data.SuccessRate);ylim(ax,[0 1]);ylabel(ax,'Correct-action rate');
    case "val_07_post_correction_prach_pusch_success"
        p=localRead(root,'prach_frequency_offset_sweep');u=localRead(root,'pusch_residual_summary');
        a=table(p.InjectedFrequencyOffsetHz/1e3,p.DetectionProbability,repmat("PRACH",height(p),1), ...
            'VariableNames',{'ResidualCFO_kHz','Success','Link'});
        b=table(u.ResidualFrequencyError_Hz/1e3,1-u.BLER,repmat("PUSCH",height(u),1), ...
            'VariableNames',{'ResidualCFO_kHz','Success','Link'});data=[a;b];localLines(ax,data.ResidualCFO_kHz,data.Success,data.Link);xlabel(ax,'Residual CFO (kHz)');ylabel(ax,'Success probability');
    case "val_08_fdd_rule_scaling_residual"
        data=localRead(root,'fdd_scaling_validation');bar(ax,categorical(data.ProfileId),data.Residual_Hz);ylabel(ax,'Correction residual (Hz)');
end
title(ax,titleText,'Interpreter','none');
end

function T=localRead(root,name)
path=fullfile(char(root),'tables',char(name+".csv"));
if exist(path,'file')~=2,error("sixgr:ntn:resilientsync:MissingFigureSource", ...
        "Required confidential figure source is missing: %s",path);end
T=readtable(path,'TextType','string');
end
function localLines(ax,x,y,g)
g=string(g(:));u=unique(g,'stable');for i=1:numel(u),m=g==u(i);[xs,o]=sort(double(x(m)));yy=double(y(m));plot(ax,xs,yy(o),'-o','DisplayName',u(i));end
if numel(u)>1,legend(ax,'Location','best');end
end
function localMatrix(ax,T)
p=unique(T.ProfileId,'stable');d=unique(T.Domain,'stable');M=zeros(numel(p),numel(d));
entities=unique(T.ResponsibleEntity,'stable');
for i=1:numel(p),for j=1:numel(d),r=T(T.ProfileId==p(i)&T.Domain==d(j),:);M(i,j)=find(entities==r.ResponsibleEntity(1),1);end,end
imagesc(ax,M);xticks(ax,1:numel(d));xticklabels(ax,d);yticks(ax,1:numel(p));yticklabels(ax,p);colorbar(ax);
end
