function records=generateFigureBackups(runDirectory,scenario)
%GENERATEFIGUREBACKUPS Keep validation plots separate from public claims.
arguments
    runDirectory (1,1) string
    scenario (1,1) struct
end
relative="figures/backup_validation";records=table();
events=readtable(fullfile(char(runDirectory),'tables','ta_report_events.csv'),'TextType','string');
data=events(events.DuplexMode=="HD_FDD",:);
fig=figure('Visible','off','Color','w','Position',[100 100 1050 640]);cleanup=onCleanup(@() close(fig));
ax=axes(fig);hold(ax,'on');grid(ax,'on');box(ax,'on');
steps=unique(data.ReportStep_ms,'stable');for i=1:numel(steps),row=data(data.ReportStep_ms==steps(i),:);plot(ax,row.RawTA_ms,row.ReportedTA_ms,'LineWidth',1.5,'DisplayName',string(steps(i))+" ms step");end
plot(ax,[min(data.RawTA_ms) max(data.RawTA_ms)],[min(data.RawTA_ms) max(data.RawTA_ms)],'k--','DisplayName','ideal');
xlabel(ax,'Raw timing adjustment (ms)');ylabel(ax,'Reported timing adjustment (ms)');title(ax,'Backup validation: TA report quantizer transfer');legend(ax,'Location','best');
meta=struct('CalibrationStatus','NOT_APPLICABLE','ClaimStatus','BACKUP_EVENT_VALIDATION', ...
    'Provenance','campaign_f_ta_report_events','Assumptions',struct('ReportSteps_ms',steps.','DuplexMode','HD_FDD'));
records=[records;sixgr.ntn.resilientsync.report.saveFigureArtifact(fig,data,runDirectory,relative, ...
    "backup_ta_report_quantizer","EVENT_PROCEDURE",scenario,"TA report quantizer transfer",Metadata=meta)];clear cleanup

summary=readtable(fullfile(char(runDirectory),'tables','ta_report_summary.csv'),'TextType','string');data=summary(summary.DuplexMode=="HD_FDD",:);
fig=figure('Visible','off','Color','w','Position',[100 100 900 600]);cleanup=onCleanup(@() close(fig));ax=axes(fig);grid(ax,'on');box(ax,'on');
bar(ax,categorical(string(data.ReportStep_ms)+" ms"),data.mean_PredictedCollision);xlabel(ax,'HD-FDD TA report policy');ylabel(ax,'Predicted collision fraction');title(ax,'Backup validation: HD-FDD collision policy (fixed-step cases)');
meta=struct('CalibrationStatus','NOT_APPLICABLE','ClaimStatus','BACKUP_EVENT_VALIDATION', ...
    'Provenance','campaign_f_scheduler_policy','Assumptions',struct('FDFDD','N/A_for_half_duplex_collision','AvailablePolicies','fixed_report_steps'));
records=[records;sixgr.ntn.resilientsync.report.saveFigureArtifact(fig,data,runDirectory,relative, ...
    "backup_hd_fdd_collision_policy","EVENT_PROCEDURE",scenario,"HD-FDD collision policy",Metadata=meta)];clear cleanup

figureNumber=["2-9";"2-18";"2-19";"2-22"];
status=repmat("BLOCKED",4,1);reason=["joint PRACH timing/CFO and PUSCH BLER surfaces have not passed full calibrated acceptance"; ...
    "TRS estimator overlay is not accepted in the same residual-Hz metric"; ...
    "detector calibration is not an analytical threshold-penalty replacement"; ...
    "PUSCH BLER confidence-qualified normalized-CFO campaign is not accepted"];
calibratedStatus=table(figureNumber,status,reason,repmat(false,4,1), ...
    'VariableNames',{'PublicFigure','CalibrationStatus','Reason','MeasuredOverlayPublished'});
records=[records;sixgr.ntn.resilientsync.report.saveResultArtifact(runDirectory,relative+"/calibrated_overlay_status", ...
    calibratedStatus,"ARCHITECTURE_DIAGRAM",struct('ClaimStatus','FAIL_CLOSED_STATUS_ONLY'))];
end
