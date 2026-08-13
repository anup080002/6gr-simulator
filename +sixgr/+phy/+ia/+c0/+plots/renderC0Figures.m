function lineage = renderC0Figures(runFolder,cfg,calibration,validation,raw,points,crossings,varargin)
%RENDERC0FIGURES Render the versioned 20-figure C0 package from CSV truth.
p=inputParser;
p.addParameter("CompletionState","COMPLETE",@(x)ischar(x)||isstring(x));
p.parse(varargin{:});
completionState=upper(string(p.Results.CompletionState));
mode=lower(string(cfg.run.mode));
isTDoc=any(mode==["tdoc" "exhaustive"]);
developerOverride=logical(cfg.run.developer_allow_non_tdoc_tdoc_figures);
if ~isTDoc && ~developerOverride
    error("sixgr:phy:ia:c0:plots:NonTDocRenderForbidden", ...
        "C0 TDoc figures require run.mode=tdoc; set the explicit developer override only for clearly labelled engineering plots.");
end
claim="TDOC_SIMULATION_PENDING_GATES";
if ~isTDoc, claim="ENGINEERING_"+upper(mode)+"_NOT_TDOC"; end
if completionState~="COMPLETE"
    claim="PARTIAL_ENGINEERING_NOT_TDOC";
end
figDir=fullfile(runFolder,"figures");
if ~isfolder(figDir), mkdir(figDir); end
metadata=[ ...
    "Scenario: "+string(cfg.meta.scenario_id)+" | runMode="+upper(mode)+ ...
    " | completion="+completionState+" | claim="+claim; ...
    compose("C0 A20RB4 | %.3g GHz | %g kHz | %s, %.0f ns, %g km/h | practical blind receiver", ...
    cfg.carrier.frequency_hz/1e9,cfg.carrier.scs_khz,string(cfg.channel.model), ...
    1e9*cfg.channel.delay_spread_s,cfg.channel.velocity_kmh)];
selectedSNR=localSelectedSNR(points,crossings);
rows=cell(20,1);
rows{1}=localPlot("C0_F01_global_noise_statistic_cdf", ...
    "Complete-declaration noise statistic CDF",@()localNoiseCDF(calibration), ...
    "false_alarm_calibration.csv");
rows{2}=localPlot("C0_F02_achieved_global_false_alarm", ...
    "Achieved global cell-with-PCI false alarm",@()localFalseAlarm(validation), ...
    "C0_false_alarm.csv");
rows{3}=localPlot("C0_F03_joint_pss_sss_mdr","Joint PSS/SSS MDR", ...
    @()localProbability(points,"JointSSMDR","JointSSCILow","JointSSCIHigh", ...
    "Joint SS MDR"),"C0_points.csv");
rows{4}=localPlot("C0_F04_pss_miss_probability","PSS miss probability", ...
    @()localProbability(points,"PSSMissProbability","PSSMissCILow", ...
    "PSSMissCIHigh","PSS miss/error probability"),"C0_points.csv");
rows{5}=localPlot("C0_F05_conditional_sss_error", ...
    "Conditional SSS error after eligible PSS", ...
    @()localProbability(points,"ConditionalSSSError","ConditionalSSSCILow", ...
    "ConditionalSSSCIHigh","Conditional SSS error"),"C0_points.csv");
rows{6}=localPlot("C0_F06_wrong_pci_probability", ...
    "Unconditional wrong-PCI declaration probability", ...
    @()localProbability(points,"WrongPCIProbability","WrongPCICILow", ...
    "WrongPCICIHigh","P(wrong PCI declaration)"),"C0_points.csv");
rows{7}=localPlot("C0_F06b_wrong_pci_given_declaration", ...
    "Wrong PCI conditioned on a cell declaration", ...
    @()localProbability(points,"WrongPCIGivenDeclaration", ...
    "WrongPCIGivenDeclarationCILow","WrongPCIGivenDeclarationCIHigh", ...
    "P(wrong PCI | declaration)"),"C0_points.csv");
rows{8}=localPlot("C0_F07a_pbch_component_bler", ...
    "PBCH-A component BLER (all channel realizations)", ...
    @()localProbability(points,"PBCHComponentBLER","PBCHComponentCILow", ...
    "PBCHComponentCIHigh","PBCH component BLER"),"C0_points.csv");
rows{9}=localPlot("C0_F07b_pbch_conditional_bler", ...
    "PBCH-B conditional practical BLER", ...
    @()localProbability(points,"PBCHConditionalBLER","PBCHConditionalCILow", ...
    "PBCHConditionalCIHigh","P(PBCH error | correct joint SS)"),"C0_points.csv");
rows{10}=localPlot("C0_F08_gamma_components_and_complete_ssb", ...
    "Qualified component and complete-SSB gamma", ...
    @()localCrossings(crossings),"C0_gamma.csv");
rows{11}=localPlot("C0_F09_timing_error_cdf_selected_snr", ...
    "Fine timing-error CDF by selected SNR", ...
    @()localSelectedCDF(raw,selectedSNR,"FineTimingErrorSamples", ...
    "TimingValidPopulation","Timing error (samples)","correct joint SS and occurrence"), ...
    "C0_timing.csv");
rows{12}=localPlot("C0_F10_timing_rmse","Timing RMSE given correct joint SS", ...
    @()localMetric(points,"TimingRMSESamples","RMSE (samples)"),"C0_points.csv");
rows{13}=localPlot("C0_F10b_gross_timing_failure", ...
    "Gross timing-occurrence error probability", ...
    @()localMetric(points,"GrossTimingOccurrenceProbability","Probability"), ...
    "C0_points.csv");
rows{14}=localPlot("C0_F11_cfo_error_cdf_selected_snr", ...
    "Residual-CFO CDF entering PBCH by selected SNR", ...
    @()localSelectedCDF(raw,selectedSNR,"ConditionalResidualCFOHz", ...
    "CFOValidPopulation","Residual CFO (Hz)","correct joint SS"),"C0_cfo.csv");
rows{15}=localPlot("C0_F12_cfo_rmse","Residual CFO RMSE given correct joint SS", ...
    @()localMetric(points,"CFORMSEHz","RMSE (Hz)"),"C0_points.csv");
rows{16}=localPlot("C0_F12b_residual_cfo_at_pbch", ...
    "Residual CFO entering PBCH", ...
    @()localRawMean(raw,"ResidualCFOBeforePBCH_Hz","Mean residual CFO (Hz)"), ...
    "C0_cfo.csv");
rows{17}=localPlot("C0_F13_pbch_channel_nmse_db", ...
    "PBCH effective-channel NMSE", ...
    @()localMetric(points,"ChannelEstimateNMSEDB","NMSE (dB)"), ...
    "C0_channel_estimation.csv");
rows{18}=localPlot("C0_F14_receiver_operation_counts", ...
    "Executed receiver operations",@()localOperations(readtable( ...
    fullfile(runFolder,"C0_complexity.csv"),"TextType","string")),"C0_complexity.csv");
rows{19}=localPlot("C0_F15_complete_ssb_success", ...
    "PBCH-C complete SSB success probability", ...
    @()localLinearProbability(points,"CompleteSSBSuccessProbability", ...
    "CompleteSSBSuccessCILow","CompleteSSBSuccessCIHigh", ...
    "Complete SSB success"),"C0_points.csv");
rows{20}=localPlot("C0_F16_failure_stage_breakdown", ...
    "Failure-stage breakdown",@()localFailureBreakdown(readtable( ...
    fullfile(runFolder,"C0_failure_breakdown.csv"),"TextType","string")), ...
    "C0_failure_breakdown.csv");
lineage=vertcat(rows{:});

    function row=localPlot(name,titleText,plotter,source)
        sourcePath=fullfile(runFolder,source);
        if exist(sourcePath,"file")~=2
            error("sixgr:phy:ia:c0:plots:MissingSource", ...
                "Figure %s requires persisted source %s.",name,sourcePath);
        end
        f=figure("Visible","off","Color","w","Position",[100 100 1100 720]);
        cleanup=onCleanup(@()close(f));
        plotter(); ax=gca; grid(ax,"on"); ax.Color="white";
        ax.XColor="black"; ax.YColor="black";
        title([string(titleText);metadata],"Interpreter","none","Color","black");
        legends=findobj(f,"Type","legend");
        set(legends,"TextColor","black","Color","white","Interpreter","none");
        path=fullfile(figDir,name+".png");
        exportgraphics(f,path,"Resolution",150);
        row=table(string(name),string(path),string(source), ...
            string(sixgr.util.sha256Hex(fileread(sourcePath))), ...
            sixgr.phy.waveform.WaveformArtifactExporter.fileSHA256(path), ...
            upper(mode),claim,"runtime_measurement", ...
            'VariableNames',{'FigureID','Path','SourceCSV','SourceSHA256', ...
            'ImageSHA256','RunMode','ClaimClass','EvidenceClass'});
    end
end

function localNoiseCDF(cal)
x=sort(cal.Metrics(isfinite(cal.Metrics)));
nRejected=nnz(~isfinite(cal.Metrics));
y=(nRejected+(1:numel(x)))'/numel(cal.Metrics);
plot(x,y,"-","LineWidth",1.2); hold on;
xline(cal.Threshold,"--","Global threshold");
xlabel("Final joint declaration statistic"); ylabel("Empirical CDF");
end

function localFalseAlarm(v)
errorbar(1,v.EmpiricalPFA,v.EmpiricalPFA-v.CILow,v.CIHigh-v.EmpiricalPFA, ...
    "o","LineWidth",1.5); hold on; yline(v.TargetPFA,"--","Target");
xlim([0.5 1.5]); xticks(1); xticklabels("complete declaration");
ylabel("False-alarm probability");
text(1,v.CIHigh,sprintf('  %d/%d, rel. half-width %.3f', ...
    v.FalseAlarms,v.TrialCount,v.RelativeCIHalfWidth));
end

function localProbability(T,name,lowName,highName,label)
y=double(T.(name)); low=double(T.(lowName)); high=double(T.(highName));
positive=isfinite(y)&y>0;
h=gobjects(0,1); labels=strings(0,1);
if any(positive)
    h(end+1)=semilogy(T.SNRDB(positive),y(positive),"o-","LineWidth",1.2); %#ok<AGROW>
    labels(end+1)="Monte Carlo estimate"; %#ok<AGROW>
end
hold on;
zero=isfinite(y)&y==0&isfinite(high)&high>0;
if any(zero)
    h(end+1)=semilogy(T.SNRDB(zero),high(zero),"v","LineWidth",1.2, ...
        "MarkerFaceColor","w"); %#ok<AGROW>
    labels(end+1)="zero errors: 95% upper limit"; %#ok<AGROW>
end
valid=(positive|zero)&isfinite(high);
for k=find(valid(:).')
    line([T.SNRDB(k) T.SNRDB(k)],[max(low(k),realmin) high(k)], ...
        "Color",[0 0.447 0.741],"HandleVisibility","off");
end
yline(0.1,"--","10%","HandleVisibility","off");
yline(0.01,"--","1%","HandleVisibility","off");
xlabel("Input SNR (dB)"); ylabel(label); ylim([1e-5 1]);
if ~isempty(h), legend(h,labels,"Location","best"); end
end

function localLinearProbability(T,name,lowName,highName,label)
y=double(T.(name)); low=double(T.(lowName)); high=double(T.(highName));
errorbar(T.SNRDB,y,max(0,y-low),max(0,high-y),"o-","LineWidth",1.2);
xlabel("Input SNR (dB)"); ylabel(label); ylim([0 1]);
end

function localMetric(T,name,label)
plot(T.SNRDB,T.(name),"o-","LineWidth",1.2);
xlabel("Input SNR (dB)"); ylabel(label);
end

function localCrossings(T)
valid=T.Bracketed&isfinite(T.CrossingSNRDB);
if any(valid)
    bar(categorical(T.Label(valid)),T.CrossingSNRDB(valid)); ylabel("Required SNR (dB)");
else
    axis off; text(0.5,0.5,"No statistically qualified target crossing", ...
        "HorizontalAlignment","center","Units","normalized");
end
end

function selected=localSelectedSNR(points,crossings)
selected=[];
for label=["gamma_SS_10" "gamma_SS_1"]
    row=crossings(crossings.Label==label,:);
    if height(row)==1&&row.Bracketed&&isfinite(row.CrossingSNRDB)
        [~,idx]=min(abs(points.SNRDB-row.CrossingSNRDB)); selected(end+1)=points.SNRDB(idx); %#ok<AGROW>
    end
end
if isempty(selected)
    for target=[0.1 0.01]
        [~,idx]=min(abs(points.JointSSMDR-target),[],"omitnan");
        if ~isempty(idx), selected(end+1)=points.SNRDB(idx); end %#ok<AGROW>
    end
end
selected=unique([selected max(points.SNRDB)],"stable");
end

function localSelectedCDF(raw,snrs,valueName,conditionName,xLabelText,conditionText)
hold on; plotted=false;
for snr=snrs
    mask=raw.SNRDB==snr&logical(raw.(conditionName));
    values=double(raw.(valueName)(mask)); values=values(isfinite(values));
    if isempty(values), continue; end
    x=sort(values); y=(1:numel(x))'/numel(x);
    plot(x,y,"LineWidth",1.2,"DisplayName",sprintf('%+.2f dB | n=%d | %s',snr,numel(x),conditionText));
    plotted=true;
end
if ~plotted, axis off; text(0.5,0.5,"No samples satisfy the stated conditioning event", ...
        "HorizontalAlignment","center","Units","normalized"); return; end
xlabel(xLabelText); ylabel("Empirical CDF"); legend("Location","best");
end

function localRawMean(raw,name,label)
snrs=unique(raw.SNRDB,"sorted"); values=nan(size(snrs));
for k=1:numel(snrs)
    values(k)=mean(raw.(name)(raw.SNRDB==snrs(k)&raw.CFOValidPopulation),"omitnan");
end
plot(snrs,values,"o-","LineWidth",1.2); yline(0,"--");
xlabel("Input SNR (dB)"); ylabel(label);
end

function localOperations(summary)
snrs=unique(summary.SNRDB,"sorted");
names=["PSSComplexMultiplications" "SSSComplexMultiplications" ...
    "ChannelEstimationOperations" "PolarDecodes"];
for j=1:numel(names)
    y=nan(size(snrs));
    for k=1:numel(snrs)
        row=summary(summary.SNRDB==snrs(k)&summary.Metric==names(j),:);
        if height(row)==1, y(k)=row.Mean; end
    end
    semilogy(snrs,max(y,realmin),"o-","LineWidth",1.2,"DisplayName",names(j)); hold on;
end
xlabel("Input SNR (dB)"); ylabel("Mean executed count per trial"); legend("Location","best");
end

function localFailureBreakdown(summary)
snrs=unique(summary.SNRDB,"sorted"); categories=unique(summary.FailureStage,"stable");
categories=categories(categories~="SUCCESS"); counts=zeros(numel(snrs),numel(categories));
for i=1:numel(snrs)
    for j=1:numel(categories)
        row=summary(summary.SNRDB==snrs(i)&summary.FailureStage==categories(j),:);
        if height(row)==1, counts(i,j)=row.Trials; end
    end
end
bar(snrs,counts,"stacked"); xlabel("Input SNR (dB)"); ylabel("Failed trials");
if ~isempty(categories), legend(categories,"Location","best"); end
end
