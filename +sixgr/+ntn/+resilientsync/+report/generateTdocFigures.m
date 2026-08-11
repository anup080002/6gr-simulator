function records = generateTdocFigures(runDirectory)
%GENERATETDOCFIGURES Generate all public figures from persisted evidence.

arguments
    runDirectory (1,1) string
end
scenario=jsondecode(fileread(fullfile(char(runDirectory),'config','resolved_config.json')));
outDir=string(scenario.outputs.public_dir);
spec={ ...
 'fig_2_01_resilient_ul_framework','Common evaluation and resilient UL framework','ARCHITECTURE_DIAGRAM'; ...
 'fig_2_02_delay_reference_convention','One-way delay versus ULRP arrival error','ANALYTICAL'; ...
 'fig_2_03_timing_bound_vs_age','ULRP timing error versus position age','ANALYTICAL'; ...
 'fig_2_04_frequency_bound_vs_speed','Geometric frequency error versus speed','ANALYTICAL'; ...
 'fig_2_05_reference_area_timing_cdf','Reference-area timing CDF','MONTE_CARLO_GEOMETRY'; ...
 'fig_2_06_reference_area_cfo_cdf','Reference-area differential CFO CDF','MONTE_CARLO_GEOMETRY'; ...
 'fig_2_07_timing_vs_elevation','Timing uncertainty versus elevation','MONTE_CARLO_GEOMETRY'; ...
 'fig_2_08_cfo_vs_elevation','Differential CFO versus elevation','MONTE_CARLO_GEOMETRY'; ...
 'fig_2_09_acquisition_vs_ordinary_regions','Acquisition and ordinary-uplink regions','CALIBRATED_LLS'; ...
 'fig_2_10_compensation_responsibility','Architecture-dependent responsibility','ARCHITECTURE_DIAGRAM'; ...
 'fig_2_12_koffset_ta_timeline','k_offset and TA report timeline','EVENT_PROCEDURE'; ...
 'fig_2_13_beam_rtt_spread','Differential RTT inside beam','MONTE_CARLO_GEOMETRY'; ...
 'fig_2_14_koffset_excess_delay_cdf','k_offset excess-delay CDF','SCHEDULER_SYSTEM'; ...
 'fig_2_15_koffset_update_timescale','RTT update time scale','ANALYTICAL'; ...
 'fig_2_16_compensation_state_matrix','Four-domain compensation state','ARCHITECTURE_DIAGRAM'; ...
 'fig_2_17_state_aware_chain','State-aware measurement and correction chain','ARCHITECTURE_DIAGRAM'; ...
 'fig_2_18_estimator_observation_interval','Estimator residual versus observation interval','CALIBRATED_LLS'; ...
 'fig_2_19_search_threshold_scaling','Search threshold versus hypotheses','CALIBRATED_LLS'; ...
 'fig_2_20_timing_pipeline_cdf','Timing-pipeline depth CDF','SCHEDULER_SYSTEM'; ...
 'fig_2_21_ta_guard_and_collision','TA guard and HD-FDD collision','EVENT_PROCEDURE'; ...
 'fig_2_22_residual_cfo_impact','Residual CFO impact','CALIBRATED_LLS'};
records=table();
for index=1:size(spec,1)
    basename=string(spec{index,1}); titleText=string(spec{index,2}); evidence=string(spec{index,3});
    [fig,data]=localBuildFigure(runDirectory,basename,titleText,scenario);
    cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
    record=sixgr.ntn.resilientsync.report.saveFigureArtifact( ...
        fig,data,runDirectory,outDir,basename,evidence,scenario,titleText);
    records=[records;record]; %#ok<AGROW>
    clear cleanup
end
end

function [fig,data]=localBuildFigure(root,name,titleText,cfg)
fig=figure('Visible','off','Color','w','Position',[100 100 1000 620]);
ax=axes(fig);grid(ax,'on');box(ax,'on');hold(ax,'on');
switch name
    case "fig_2_01_resilient_ul_framework"
        data=localRead(root,'compensation_state_matrix');
        localArchitecture(ax,["GNSS valid/degraded/free","State profile + version", ...
            "DL timing/CFO measurement","State-aware WLS","UL correction", ...
            "PRACH acquisition","PUSCH/PUCCH tracking"]);
    case "fig_2_02_delay_reference_convention"
        h=localRead(root,'gnss_degraded_holdover');data=unique(h(:,{'DeltaTauSL_s','ULRPArrivalError_s','PositionAge_s'}));
        scatter(ax,data.DeltaTauSL_s*1e6,data.ULRPArrivalError_s*1e6,18,data.PositionAge_s,'filled');
        xlabel(ax,'One-way error \Delta\tau_{SL} (\mus)');ylabel(ax,'ULRP arrival error e_T (\mus)');colorbar(ax);
    case "fig_2_03_timing_bound_vs_age"
        h=localRead(root,'gnss_degraded_holdover');data=h(h.CarrierId=="S_band" & h.Oscillator_ppm==min(h.Oscillator_ppm),:);
        localLines(ax,data.PositionAge_s,abs(data.ULRPArrivalError_s)*1e6,string(data.Speed_m_s*3.6));
        xlabel(ax,'Position age (s)');ylabel(ax,'|e_T| bound (\mus)');
    case "fig_2_04_frequency_bound_vs_speed"
        h=localRead(root,'gnss_degraded_holdover');data=h(h.PositionAge_s==max(h.PositionAge_s) & h.Oscillator_ppm==min(h.Oscillator_ppm),:);
        localLines(ax,data.Speed_m_s*3.6,data.AbsoluteULFrequencyError_Hz/1e3,data.CarrierId);
        xlabel(ax,'Speed (km/h)');ylabel(ax,'|e_F| bound (kHz)');
    case "fig_2_05_reference_area_timing_cdf"
        raw=localRawReference(root,25,30);data=localCDF(abs(raw.ULRPArrivalError_s)*1e6,'TimingError_us');
        plot(ax,data.TimingError_us,data.CDF,'LineWidth',1.8);xlabel(ax,'|e_T| (\mus)');ylabel(ax,'Empirical CDF');
    case "fig_2_06_reference_area_cfo_cdf"
        raw=localRawReference(root,25,30);a=localCDF(abs(raw.DifferentialCFO_SBand_Hz)/1e3,'CFO_kHz');a.Series=repmat("S band",height(a),1);
        b=localCDF(abs(raw.DifferentialCFO_Ka_Hz)/1e3,'CFO_kHz');b.Series=repmat("Ka",height(b),1);data=[a;b];
        localLines(ax,data.CFO_kHz,data.CDF,data.Series);xlabel(ax,'|Differential CFO| (kHz)');ylabel(ax,'Empirical CDF');
    case "fig_2_07_timing_vs_elevation"
        data=localRead(root,'reference_area_summary');
        localLines(ax,data.Elevation_deg,data.P95AbsoluteULRPArrivalError_s*1e6,string(data.ReferenceAreaRadius_m/1e3));
        xlabel(ax,'Elevation (deg)');ylabel(ax,'95th percentile |e_T| (\mus)');
    case "fig_2_08_cfo_vs_elevation"
        data=localRead(root,'reference_area_summary');data=data(data.ReferenceAreaRadius_m==25e3,:);
        plot(ax,data.Elevation_deg,data.P95AbsoluteDifferentialCFO_SBand_Hz/1e3,'-o','LineWidth',1.6);
        plot(ax,data.Elevation_deg,data.P95AbsoluteDifferentialCFO_Ka_Hz/1e3,'-s','LineWidth',1.6);legend(ax,'S band','Ka','Location','best');
        xlabel(ax,'Elevation (deg)');ylabel(ax,'95th percentile |CFO| (kHz)');
    case "fig_2_09_acquisition_vs_ordinary_regions"
        p=localRead(root,'prach_frequency_offset_sweep');u=localRead(root,'pusch_residual_summary');
        a=table(p.InjectedFrequencyOffsetHz/1e3,p.DetectionProbability,repmat("PRACH",height(p),1), ...
            'VariableNames',{'FrequencyError_kHz','SuccessProbability','Region'});
        b=table(u.ResidualFrequencyError_Hz/1e3,1-u.BLER,repmat("PUSCH",height(u),1), ...
            'VariableNames',{'FrequencyError_kHz','SuccessProbability','Region'});data=[a;b];
        localLines(ax,data.FrequencyError_kHz,data.SuccessProbability,data.Region);xlabel(ax,'Residual CFO (kHz)');ylabel(ax,'Measured success probability');
    case {"fig_2_10_compensation_responsibility","fig_2_16_compensation_state_matrix"}
        data=localRead(root,'compensation_state_matrix');localStateMatrix(ax,data);
    case "fig_2_12_koffset_ta_timeline"
        data=localRead(root,'ta_report_events');data=data(1:min(200,height(data)),:);
        plot(ax,data.RawTA_ms,data.ReportedTA_ms,'LineWidth',1.5);plot(ax,data.RawTA_ms,data.RawTA_ms,'--');
        xlabel(ax,'Raw arrival adjustment (ms)');ylabel(ax,'Reported TA (ms)');legend(ax,'reported','ideal');
    case "fig_2_13_beam_rtt_spread"
        k=localRead(root,'k_offset_samples');data=groupsummary(k,'Elevation_deg',{'max','mean'},'RequiredDelay_s');
        plot(ax,data.Elevation_deg,data.max_RequiredDelay_s*1e3,'-o','LineWidth',1.6);xlabel(ax,'Elevation (deg)');ylabel(ax,'Differential RTT spread (ms)');
    case "fig_2_14_koffset_excess_delay_cdf"
        k=localRead(root,'k_offset_samples');k=k(k.SCS_kHz==120,:);
        a=localCDF(k.UEExcessDelay_s*1e6,'Excess_us');a.Level=repmat("UE",height(a),1);
        b=localCDF(k.BeamExcessDelay_s*1e6,'Excess_us');b.Level=repmat("Beam",height(b),1);
        c=localCDF(k.CellExcessDelay_s*1e6,'Excess_us');c.Level=repmat("Cell",height(c),1);data=[a;b;c];
        localLines(ax,data.Excess_us,data.CDF,data.Level);xlabel(ax,'Excess delay (\mus)');ylabel(ax,'Empirical CDF');
    case "fig_2_15_koffset_update_timescale"
        f=localRead(root,'feeder_polynomial_summary');data=f(f.DerivativeOrder==1,:);
        localLines(ax,data.Validity_s,data.MaximumAbsoluteError_s*1e6,string(data.Elevation_deg));xlabel(ax,'Update interval (s)');ylabel(ax,'Maximum timing error (\mus)');
    case "fig_2_17_state_aware_chain"
        data=localRead(root,'trs_coverage');localArchitecture(ax,["TRS waveform","Timing/CFO detector", ...
            "H(S), g(S,t)","Stable WLS","Mismatch/stateVersion","UL rule","Waveform validation"]);
    case "fig_2_18_estimator_observation_interval"
        e=localRead(root,'estimator_reference');m=groupsummary(e,'ObservationInterval_s','mean','EpsilonRMSE_fractional');
        f=localRead(root,'trs_frequency_offset_sweep');
        measured=abs(f.FrequencyError_Hz);measured=measured(isfinite(measured));
        measuredValue=mean(measured,'omitnan');
        data=table(m.ObservationInterval_s,m.mean_EpsilonRMSE_fractional, ...
            repmat(measuredValue,height(m),1), ...
            'VariableNames',{'ObservationInterval_s','AnalyticalFractionalRMSE','MeasuredTRSError_Hz'});
        yyaxis(ax,'left');plot(ax,data.ObservationInterval_s,data.AnalyticalFractionalRMSE,'-o');ylabel(ax,'Analytical fractional RMSE');
        yyaxis(ax,'right');plot(ax,data.ObservationInterval_s,data.MeasuredTRSError_Hz,'-s');ylabel(ax,'Measured TRS error (Hz)');xlabel(ax,'Observation interval (s)');
    case "fig_2_19_search_threshold_scaling"
        c=localRead(root,'prach_false_alarm_calibration');n=unique(round(logspace(0,6,80))).';p=double(c.TargetGlobalPFA(1));eta=-log(1-(1-p).^(1./n));
        data=table(n,eta,repmat(double(c.CalibratedThreshold(1)),numel(n),1), ...
            'VariableNames',{'Hypotheses','AnalyticalEta','CalibratedReceiverThreshold'});
        semilogx(ax,data.Hypotheses,data.AnalyticalEta,'LineWidth',1.5);yline(ax,c.CalibratedThreshold(1),'--');xlabel(ax,'Hypotheses');ylabel(ax,'Threshold statistic');
    case "fig_2_20_timing_pipeline_cdf"
        p=localRead(root,'timing_pipeline');p=p(p.SCS_kHz==120,:);data=localCDF(p.PipelineSlots,'PipelineSlots');
        stairs(ax,data.PipelineSlots,data.CDF,'LineWidth',1.8);xlabel(ax,'Pipeline occupancy (slots)');ylabel(ax,'Empirical CDF');
    case "fig_2_21_ta_guard_and_collision"
        data=localRead(root,'ta_report_summary');
        bar(ax,categorical(data.DuplexMode+"/"+string(data.ReportStep_ms)),data.mean_PredictedCollision);ylabel(ax,'Predicted collision rate');xlabel(ax,'Mode / TA step (ms)');
    case "fig_2_22_residual_cfo_impact"
        u=localRead(root,'pusch_residual_summary');u=u(u.ResidualTimingError_s==0,:);
        analytical=sixgr.ntn.resilientsync.uplink.computeAnalyticalCfoSensitivity( ...
            unique(u.ResidualFrequencyError_Hz),double(cfg.physical_layer.residual_scs_khz)*1e3,unique(u.SNRdB));
        analytical=renamevars(analytical,{'FrequencyError_Hz','SNR_dB'}, ...
            {'ResidualFrequencyError_Hz','SNRdB'});
        data=outerjoin(u(:,{'ResidualFrequencyError_Hz','SNRdB','BLER'}), ...
            analytical(:,{'ResidualFrequencyError_Hz','SNRdB','EffectiveSNR_dB'}), ...
            'Keys',{'ResidualFrequencyError_Hz','SNRdB'},'MergeKeys',true);
        yyaxis(ax,'left');localLines(ax,data.ResidualFrequencyError_Hz/1e3,data.BLER,string(data.SNRdB));ylabel(ax,'Measured PUSCH BLER');
        yyaxis(ax,'right');localLines(ax,data.ResidualFrequencyError_Hz/1e3,data.EffectiveSNR_dB,string(data.SNRdB));ylabel(ax,'Analytical effective SNR (dB)');xlabel(ax,'Residual CFO (kHz)');
end
title(ax,titleText,'Interpreter','none');
end

function T=localRead(root,name)
path=fullfile(char(root),'tables',char(name + ".csv"));
if exist(path,'file')~=2,error("sixgr:ntn:resilientsync:MissingFigureSource", ...
        "Required figure source is missing: %s",path);end
T=readtable(path,'TextType','string');
end
function raw=localRawReference(root,radiusKm,elevationDeg)
path=fullfile(char(root),'raw','campaign_a_reference_area', ...
    sprintf('reference_area_r%gkm_e%gdeg.mat',radiusKm,elevationDeg));
s=load(path,'raw');raw=s.raw;
end
function T=localCDF(values,name)
values=sort(double(values(isfinite(values))));
if isempty(values),error("sixgr:ntn:resilientsync:EmptyCDF","CDF has no finite source values.");end
n=min(2000,numel(values));idx=unique(round(linspace(1,numel(values),n))).';
T=table(values(idx),idx./numel(values),'VariableNames',{name,'CDF'});
T.Properties.VariableUnits={'','1'};
end
function localLines(ax,x,y,group)
group=string(group(:));u=unique(group,'stable');
for i=1:numel(u),m=group==u(i);[xs,o]=sort(double(x(m)));ys=double(y(m));plot(ax,xs,ys(o),'-o','DisplayName',u(i),'LineWidth',1.3);end
if numel(u)>1,legend(ax,'Location','best');end
end
function localArchitecture(ax,labels)
axis(ax,[0 1 0 1]);axis(ax,'off');n=numel(labels);
for i=1:n
    x=0.05+(i-1)*0.9/max(n-1,1);
    rectangle(ax,'Position',[x-0.055,0.43,0.11,0.14],'Curvature',0.12,'FaceColor',[0.85 0.95 0.93]);
    text(ax,x,0.5,labels(i),'HorizontalAlignment','center','FontSize',8,'Interpreter','none');
    if i<n,annotation(ax.Parent,'arrow',[x+0.06,0.05+i*0.9/max(n-1,1)-0.06],[0.5,0.5]);end
end
end
function localStateMatrix(ax,T)
profiles=unique(T.ProfileId,'stable');domains=unique(T.Domain,'stable');matrix=zeros(numel(profiles),numel(domains));
for i=1:numel(profiles),for j=1:numel(domains),row=T(T.ProfileId==profiles(i)&T.Domain==domains(j),:);matrix(i,j)=double(categorical(row.ResponsibleEntity));end,end
imagesc(ax,matrix);xticks(ax,1:numel(domains));xticklabels(ax,domains);yticks(ax,1:numel(profiles));yticklabels(ax,profiles);colorbar(ax);
end
