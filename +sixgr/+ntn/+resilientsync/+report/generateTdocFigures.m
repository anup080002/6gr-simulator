function records = generateTdocFigures(runDirectory)
%GENERATETDOCFIGURES Render the public TDoc contract from canonical data.
arguments
    runDirectory (1,1) string
end
scenario=jsondecode(fileread(fullfile(char(runDirectory),'config','resolved_config.json')));
outDir=string(scenario.outputs.public_dir);
spec={ ...
 'fig_2_01_resilient_ul_framework','Common evaluation and resilient UL framework'; ...
 'fig_2_02_delay_reference_convention','One-way delay versus ULRP arrival error'; ...
 'fig_2_03_timing_bound_vs_age','ULRP timing-error bound versus position age'; ...
 'fig_2_04_frequency_bound_vs_speed','Geometric frequency-error bound versus speed'; ...
 'fig_2_05_reference_area_timing_cdf','Reference-area ULRP timing-error CDF'; ...
 'fig_2_06_reference_area_cfo_cdf','Reference-area differential CFO CDF'; ...
 'fig_2_07_timing_vs_elevation','Timing uncertainty versus elevation'; ...
 'fig_2_08_cfo_vs_elevation','Differential CFO versus elevation'; ...
 'fig_2_09_acquisition_vs_ordinary_regions','Acquisition and ordinary-uplink regions'; ...
 'fig_2_10_compensation_responsibility','Architecture-dependent responsibility'; ...
 'fig_2_12_koffset_ta_timeline','k-offset, UE timing, and TA-report timeline'; ...
 'fig_2_13_beam_rtt_spread','Differential RTT inside a 50-km beam'; ...
 'fig_2_14_koffset_excess_delay_cdf','k-offset excess-delay CDF'; ...
 'fig_2_15_koffset_update_timescale','RTT update time scale'; ...
 'fig_2_16_compensation_state_matrix','Four-domain compensation state'; ...
 'fig_2_17_state_aware_chain','State-aware measurement and correction chain'; ...
 'fig_2_18_estimator_observation_interval','Estimator residual versus observation interval'; ...
 'fig_2_19_search_threshold_scaling','Independent-noise threshold scaling'; ...
 'fig_2_20_timing_pipeline_cdf','Timing-pipeline depth CDF'; ...
 'fig_2_21_ta_guard_and_collision','Analytical TA guard-slot requirement'; ...
 'fig_2_22_residual_cfo_impact','Analytical residual-CFO impact'};
records=table();
for index=1:size(spec,1)
    name=string(spec{index,1});titleText=string(spec{index,2});
    [data,meta]=sixgr.ntn.resilientsync.report.buildPublicFigureData(runDirectory,name,scenario);
    fig=figure('Visible','off','Color','w','Position',[100 100 1180 700]);
    cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
    localRender(fig,name,data,titleText,scenario);
    record=sixgr.ntn.resilientsync.report.saveFigureArtifact( ...
        fig,data,runDirectory,outDir,name,string(meta.EvidenceClass),scenario,titleText, ...
        Metadata=meta);
    records=[records;record]; %#ok<AGROW>
    clear cleanup
end
end

function localRender(fig,name,data,titleText,cfg)
switch name
    case "fig_2_01_resilient_ul_framework"
        localFramework(fig,data);
    case "fig_2_02_delay_reference_convention"
        ax=localAxes(fig);scatter(ax,data.DeltaTauSL_us,data.ULRPArrivalError_us,34,data.PositionAge_s,'filled');
        lim=[min(data.DeltaTauSL_us),max(data.DeltaTauSL_us)];plot(ax,lim,-2*lim,'k--','LineWidth',1.8,'DisplayName','e_T = -2\Delta\tau_{SL}');
        cb=colorbar(ax);cb.Label.String='Position age (s)';cb.Color='k';xlabel(ax,'\Delta\tau_{SL} (\mus)');ylabel(ax,'e_T at ULRP (\mus)');localLegend(ax,'best');
    case "fig_2_03_timing_bound_vs_age"
        ax=localAxes(fig);localLines(ax,data.PositionAge_s,data.AbsoluteET_us,string(data.Speed_kmh)+" km/h",true);
        xlabel(ax,'Position age (s)');ylabel(ax,'|e_T| bound (\mus)');
    case "fig_2_04_frequency_bound_vs_speed"
        ax=localAxes(fig);labels=replace(data.CarrierId,["S_band","Ka_generic"],["2 GHz","30 GHz"]);
        localLines(ax,data.Speed_kmh,data.GeometricFrequencyErrorBound_kHz,labels,true);
        xlabel(ax,'Speed (km/h)');ylabel(ax,'Geometric UL frequency-error bound (kHz)');
    case "fig_2_05_reference_area_timing_cdf"
        ax=localAxes(fig);localLines(ax,data.AbsoluteET_us,data.CDF,string(data.Radius_km)+" km radius",false);
        localP95(ax,data,"Radius_km","P95_us",'\mus');xlabel(ax,'|e_T| (\mus)');ylabel(ax,'Empirical CDF');
    case "fig_2_06_reference_area_cfo_cdf"
        ax=localAxes(fig);localLines(ax,data.AbsoluteDifferentialCFO_kHz,data.CDF,data.Carrier,false);
        localP95(ax,data,"Carrier","P95_kHz",' kHz');xlabel(ax,'|Differential CFO| (kHz)');ylabel(ax,'Empirical CDF');
    case "fig_2_07_timing_vs_elevation"
        ax=localAxes(fig);localLines(ax,data.Elevation_deg,data.P95_us,data.Metric,true);
        xlabel(ax,'Area-centre elevation (deg)');ylabel(ax,'95th percentile timing uncertainty (\mus)');
    case "fig_2_08_cfo_vs_elevation"
        ax=localAxes(fig);localLines(ax,data.Elevation_deg,data.P95_kHz,data.Carrier,true);
        xlabel(ax,'Area-centre elevation (deg)');ylabel(ax,'95th percentile differential CFO (kHz)');
    case "fig_2_09_acquisition_vs_ordinary_regions"
        ax=localAxes(fig);localLines(ax,data.ResidualCFO_kHz,data.ResidualTimingError_us,data.Region,false);
        xlabel(ax,'Residual CFO (kHz)');ylabel(ax,'Residual timing error e_T (\mus)');axis(ax,'equal');
        text(ax,.02,.03,'Conceptual bounds only — empirical PRACH/PUSCH contours blocked pending acceptance', ...
            'Units','normalized','FontAngle','italic','Color',[.35 .1 .1]);
    case "fig_2_10_compensation_responsibility"
        localArchitectureCards(fig,data);
    case "fig_2_12_koffset_ta_timeline"
        localTimeline(fig,data);
    case "fig_2_13_beam_rtt_spread"
        ax=localAxes(fig);plot(ax,data.Elevation_deg,data.DifferentialRTTSpread_ms,'-o','LineWidth',1.8,'MarkerFaceColor',[.05 .45 .65]);
        xlabel(ax,'Beam-centre elevation (deg)');ylabel(ax,'max RTT - min RTT (ms)');
    case "fig_2_14_koffset_excess_delay_cdf"
        ax=localAxes(fig);localLines(ax,data.ExcessDelay_ms,data.CDF,data.Level,false);xlim(ax,[0 10]);
        xlabel(ax,'k-offset excess delay (ms)');ylabel(ax,'Empirical CDF');localStats(ax,data,'Level','Mean_ms','P95_ms','Maximum_ms','ms');
    case "fig_2_15_koffset_update_timescale"
        ax=localAxes(fig);localLines(ax,data.Elevation_deg,data.TimeToOneSlot_s,string(data.SCS_kHz)+" kHz",true);set(ax,'YScale','log');
        xlabel(ax,'Elevation (deg)');ylabel(ax,'Time for RTT to change by one slot (s)');
    case "fig_2_16_compensation_state_matrix"
        localStateMatrix(fig,data);
    case "fig_2_17_state_aware_chain"
        localChain(fig,data);
    case "fig_2_18_estimator_observation_interval"
        ax=localAxes(fig);labels=string(data.ULCarrier_Hz/1e9)+" GHz, \sigma_t="+string(data.TimingSigma_us)+" \mus";
        localLines(ax,data.ObservationInterval_s,data.ULResidualFrequencySigma_Hz,labels,true);set(ax,'YScale','log');
        xlabel(ax,'Observation interval T (s)');ylabel(ax,'One-sigma UL residual frequency (Hz)');
    case "fig_2_19_search_threshold_scaling"
        ax=localAxes(fig);semilogx(ax,data.Hypotheses,data.RelativeThresholdPenalty_dB,'LineWidth',1.9);hold(ax,'on');
        targets=[4 196 1016 8128];for n=targets,idx=find(data.Hypotheses==n,1);if ~isempty(idx),plot(ax,n,data.RelativeThresholdPenalty_dB(idx),'o','MarkerFaceColor',[.05 .45 .65]);end,end
        xlabel(ax,'Independent hypotheses N');ylabel(ax,'Relative threshold penalty (dB), N_{ref}=4');
    case "fig_2_20_timing_pipeline_cdf"
        ax=localAxes(fig);localLines(ax,data.PipelineSlots,data.CDF,data.Level,false);
        xlabel(ax,'Pipeline depth (slots), T_{proc}=1 ms');ylabel(ax,'Empirical CDF');localStats(ax,data,'Level','MeanSlots','P95Slots','MaximumSlots','slots');
    case "fig_2_21_ta_guard_and_collision"
        ax=localAxes(fig);scs=unique(data.SCS_kHz,'stable');labels=unique(data.GuardSource,'stable');m=nan(numel(labels),numel(scs));
        for i=1:numel(labels),for j=1:numel(scs),row=data(data.GuardSource==labels(i)&data.SCS_kHz==scs(j),:);m(i,j)=row.RequiredGuardSlots(1);end,end
        bar(ax,categorical(labels,labels),m,'grouped');xlabel(ax,'Timing bound / report step');ylabel(ax,'Required guard slots');localLegend(ax,'northwest',string(scs)+" kHz");
    case "fig_2_22_residual_cfo_impact"
        ax=localAxes(fig);localLines(ax,data.AbsoluteNormalizedCFO,data.EffectiveSNRLoss_dB,string(data.InputSNR_dB)+" dB input SNR",true);
        xlabel(ax,'|Residual CFO| / SCS');ylabel(ax,'Effective-SNR loss (dB)');
end
sgtitle(fig,titleText,'Color','k','FontWeight','bold','Interpreter','none');
localSubtitle(fig,name,cfg);
end

function ax=localAxes(fig)
ax=axes(fig,'Position',[.09 .12 .82 .77]);hold(ax,'on');grid(ax,'on');box(ax,'on');
set(ax,'Color','w','XColor','k','YColor','k','FontName','Arial','FontSize',11,'LineWidth',.8);
end
function localLines(ax,x,y,group,markers)
group=string(group(:));u=unique(group,'stable');styles={'-','--','-.',':'};
for i=1:numel(u)
    mask=group==u(i);[xs,order]=sort(double(x(mask)));ys=double(y(mask));
    if markers,marker='o';else,marker='none';end
    plot(ax,xs,ys(order),'LineStyle',styles{1+mod(i-1,numel(styles))},'Marker',marker, ...
        'LineWidth',1.8,'DisplayName',u(i));
end
if numel(u)>1,localLegend(ax,'best');end
end
function localP95(ax,T,groupName,valueName,unit)
groups=unique(string(T.(groupName)),'stable');words=strings(numel(groups),1);
for i=1:numel(groups),row=T(string(T.(groupName))==groups(i),:);words(i)=groups(i)+": P95="+compose('%.3g',row.(valueName)(1))+unit;end
text(ax,.99,.03,strjoin(words,newline),'Units','normalized','HorizontalAlignment','right','VerticalAlignment','bottom','BackgroundColor','w','Color','k','Margin',5);
end
function localStats(ax,T,groupName,meanName,p95Name,maxName,unit)
groups=unique(string(T.(groupName)),'stable');words=strings(numel(groups),1);
for i=1:numel(groups),row=T(string(T.(groupName))==groups(i),:);words(i)=sprintf('%s: mean %.3g, P95 %.3g, max %.3g %s',groups(i),row.(meanName)(1),row.(p95Name)(1),row.(maxName)(1),unit);end
text(ax,.02,.97,strjoin(words,newline),'Units','normalized','VerticalAlignment','top','BackgroundColor','w','Color','k','Margin',5,'FontSize',9);
end
function localFramework(fig,T)
ax=axes(fig,'Position',[.02 .07 .96 .84]);axis(ax,[0 1 0 1]);axis(ax,'off');hold(ax,'on');
colors=[.86 .94 1;.93 .91 1;.88 .97 .91];ys=[.77 .55 .33];
for i=1:3,localBox(ax,.02,ys(i),.18,.12,T.Mode(i),colors(i,:));localBox(ax,.23,ys(i),.19,.12,T.PositionAuthority(i),[.97 .97 .97]);localArrow(ax,.20,ys(i)+.06,.23,ys(i)+.06);localArrow(ax,.42,ys(i)+.06,.48,.55);end
steps=["Coarse UL time/frequency pre-compensation","Initial uplink acquisition","Residual correction","Ordinary PUSCH/PUCCH/tracking"];
xs=[.48 .64 .78 .89];widths=[.14 .11 .09 .1];for i=1:4,localBox(ax,xs(i),.49,widths(i),.13,steps(i),[.82 .94 .92]);if i<4,localArrow(ax,xs(i)+widths(i),.555,xs(i+1),.555);end,end
plot(ax,[.94 .94 .72 .72],[.49 .18 .18 .48],'Color',[.45 .1 .1],'LineWidth',1.5);localArrow(ax,.72,.18,.72,.48);
text(ax,.83,.13,'ordinary-UL bound exceedance: correction / reacquisition / suspend','HorizontalAlignment','center','Color',[.45 .1 .1],'FontSize',9);
end
function localArchitectureCards(fig,T)
ax=axes(fig,'Position',[.03 .06 .94 .85]);axis(ax,[0 1 0 1]);axis(ax,'off');hold(ax,'on');
for i=1:height(T)
    x=.02+(i-1)*.325;rectangle(ax,'Position',[x .08 .30 .8],'Curvature',.03,'FaceColor',[.95 .98 .98],'EdgeColor',[.12 .42 .5],'LineWidth',1.4);
    heading=replace(T.Architecture(i)," / ",newline);
    text(ax,x+.15,.82,heading,'HorizontalAlignment','center','FontWeight','bold','Interpreter','none','FontSize',10,'Color','k');
    body="ULRP: "+T.ULRPLocation(i)+newline+newline+"UE: "+T.UEResponsibility(i)+newline+newline+"Feeder: "+T.FeederResponsibility(i)+newline+newline+"Assistance: "+T.AssistanceImplication(i);
    text(ax,x+.02,.72,body,'VerticalAlignment','top','Interpreter','none','FontSize',9,'Color','k');
end
end
function localTimeline(fig,T)
ax=axes(fig,'Position',[.04 .08 .92 .84]);axis(ax,[.5 height(T)+.5 0 1]);axis(ax,'off');hold(ax,'on');
lanes=unique(T.Lane,'stable');y=linspace(.82,.18,numel(lanes));
for i=1:numel(lanes),plot(ax,[.7 height(T)+.3],[y(i) y(i)],'Color',[.8 .8 .8]);text(ax,.6,y(i),lanes(i),'HorizontalAlignment','right','FontWeight','bold','Color','k');end
for i=1:height(T)
    j=find(lanes==T.Lane(i),1);plot(ax,i,y(j),'o','MarkerSize',10,'MarkerFaceColor',[.08 .5 .62]);
    if i==height(T),alignment='right';else,alignment='left';end
    text(ax,i,y(j)+.055,T.Event(i),'Rotation',25,'HorizontalAlignment',alignment,'Interpreter','none','FontSize',8,'Color','k');
    if i<height(T),k=find(lanes==T.Lane(i+1),1);localArrow(ax,i+.08,y(j),i+1-.08,y(k));end
end
end
function localStateMatrix(fig,T)
ax=axes(fig,'Position',[.03 .06 .94 .85]);axis(ax,[0 2 0 2]);axis(ax,'off');hold(ax,'on');
rows=["DL","UL"];cols=["Timing","Frequency"];
for i=1:2,for j=1:2
    x=j-1;y=2-i;rectangle(ax,'Position',[x+.03 y+.04 .94 .9],'FaceColor',[.95 .98 .98],'EdgeColor',[.15 .35 .42]);
    row=T(T.MatrixRow==rows(i)&T.MatrixColumn==cols(j),:);fields=setdiff(string(T.Properties.VariableNames),["ProfileId","Domain","MatrixRow","MatrixColumn"],'stable');lines=rows(i)+" / "+cols(j);
    for k=1:numel(fields),value=string(row.(fields(k))(1));lines=lines+newline+fields(k)+": "+value;end
    text(ax,x+.5,y+.49,lines,'HorizontalAlignment','center','VerticalAlignment','middle','Interpreter','none','FontSize',8.5,'Color','k');
end,end
end
function localChain(fig,T)
ax=axes(fig,'Position',[.02 .07 .96 .84]);axis(ax,[0 1 0 1]);axis(ax,'off');hold(ax,'on');
localBox(ax,.02,.69,.25,.12,T.Node(1),[.88 .94 1]);localBox(ax,.02,.40,.25,.12,T.Node(2),[.88 .94 1]);
xs=[.34 .53 .70 .86];widths=[.15 .12 .12 .12];for i=3:6,localBox(ax,xs(i-2),.49,widths(i-2),.15,T.Node(i),[.86 .96 .91]);end
localArrow(ax,.27,.75,.34,.59);localArrow(ax,.27,.46,.34,.56);for i=1:3,localArrow(ax,xs(i)+widths(i),.565,xs(i+1),.565);end
end
function localBox(ax,x,y,w,h,label,color)
maxChars=max(16,round(100*w));
rectangle(ax,'Position',[x y w h],'Curvature',.08,'FaceColor',color,'EdgeColor',[.15 .32 .38],'LineWidth',1.2);text(ax,x+w/2,y+h/2,localWrap(label,maxChars),'HorizontalAlignment','center','VerticalAlignment','middle','Interpreter','none','FontSize',8.5,'Color','k');
end
function localArrow(ax,x1,y1,x2,y2)
quiver(ax,x1,y1,x2-x1,y2-y1,0,'Color',[.15 .25 .28],'LineWidth',1.2,'MaxHeadSize',.18);
end
function localLegend(ax,location,labels)
if nargin<3,lgd=legend(ax,'Location',location,'Interpreter','none');else,lgd=legend(ax,labels,'Location',location,'Interpreter','none');end
set(lgd,'Color','w','TextColor','k','EdgeColor',[.35 .35 .35]);
end
function output=localWrap(input,maxChars)
words=split(string(input));lines=strings(0,1);current="";
for i=1:numel(words)
    candidate=strtrim(current+" "+words(i));
    if strlength(candidate)>maxChars&&strlength(current)>0,lines(end+1,1)=current;current=words(i);else,current=candidate;end %#ok<AGROW>
end
if strlength(current)>0,lines(end+1,1)=current;end
output=strjoin(lines,newline);
end
function localSubtitle(fig,name,cfg)
if any(name==["fig_2_05_reference_area_timing_cdf","fig_2_06_reference_area_cfo_cdf","fig_2_07_timing_vs_elevation","fig_2_08_cfo_vs_elevation"])
    annotation(fig,'textbox',[.2 .91 .6 .035],'String','LEO-600, exact spherical-Earth geometry, uniform-in-area sampling','LineStyle','none','HorizontalAlignment','center','Color',[.2 .2 .2]);
elseif name=="fig_2_13_beam_rtt_spread"
    annotation(fig,'textbox',[.2 .91 .6 .035],'String','50-km diameter circular beam, LEO-600, exact spherical-Earth geometry','LineStyle','none','HorizontalAlignment','center','Color',[.2 .2 .2]);
elseif name=="fig_2_19_search_threshold_scaling"
    annotation(fig,'textbox',[.2 .91 .6 .035],'String','Analytical independent-hypothesis noise threshold scaling; PFA_{total}=0.01','LineStyle','none','HorizontalAlignment','center','Color',[.2 .2 .2]);
elseif name=="fig_2_22_residual_cfo_impact"
    annotation(fig,'textbox',[.2 .91 .6 .035],'String','Analytical OFDM coherent-gain and ICI model; no calibrated BLER claim','LineStyle','none','HorizontalAlignment','center','Color',[.2 .2 .2]);
else
    annotation(fig,'textbox',[.2 .91 .6 .035],'String',"Run "+string(cfg.RunId),'LineStyle','none','HorizontalAlignment','center','Color',[.2 .2 .2],'Interpreter','none');
end
end
