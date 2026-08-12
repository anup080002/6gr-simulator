function lineage = renderC0Figures(runFolder,cfg,calibration,validation,raw,points,crossings)
%RENDERC0FIGURES Render C0_F01-C0_F15 from persisted IA measurements.
figDir = fullfile(runFolder,"figures");
if ~isfolder(figDir), mkdir(figDir); end
metadata = sprintf('%s | %.3g GHz | %g kHz | %s | %g km/h | %s | practical blind receiver', ...
    string(cfg.meta.scenario_id),cfg.carrier.frequency_hz/1e9,cfg.carrier.scs_khz, ...
    string(cfg.channel.model),cfg.channel.velocity_kmh,string(cfg.waveform.normalization));
rows = cell(15,1);

rows{1}=localPlot("C0_F01_global_noise_statistic_cdf","Global noise-only maximum search statistic", ...
    @()localNoiseCDF(calibration),"false_alarm_calibration.csv");
rows{2}=localPlot("C0_F02_achieved_global_false_alarm","Achieved global false alarm and 95% CI", ...
    @()localFalseAlarm(validation),"false_alarm_validation.csv");
rows{3}=localPlot("C0_F03_joint_pss_sss_mdr","Joint PSS/SSS MDR", ...
    @()localProbability(points,"JointSSMDR","JointSSCILow", ...
    "JointSSCIHigh","Joint SS MDR"),"points.csv");
rows{4}=localPlot("C0_F04_pss_miss_probability","PSS miss probability", ...
    @()localProbability(points,"PSSMissProbability","PSSMissCILow", ...
    "PSSMissCIHigh","PSS miss probability"),"points.csv");
rows{5}=localPlot("C0_F05_conditional_sss_error","Conditional SSS error after PSS", ...
    @()localProbability(points,"ConditionalSSSError","ConditionalSSSCILow", ...
    "ConditionalSSSCIHigh","Conditional SSS error"),"points.csv");
rows{6}=localPlot("C0_F06_wrong_pci_probability","Wrong PCI probability", ...
    @()localProbability(points,"WrongPCIProbability","WrongPCICILow", ...
    "WrongPCICIHigh","Wrong PCI probability"),"points.csv");
rows{7}=localPlot("C0_F07_pbch_bler","PBCH BLER", ...
    @()localProbability(points,"PBCHBLER","PBCHCILow", ...
    "PBCHCIHigh","PBCH BLER"),"points.csv");
rows{8}=localPlot("C0_F08_gamma_components","Required-SNR component crossings", ...
    @()localCrossings(crossings),"target_crossings.csv");
rows{9}=localPlot("C0_F09_timing_error_cdf","Timing-estimation error CDF", ...
    @()localErrorCDF(raw.TimingErrorSamples,"Timing error (samples)"),"raw_trials.csv");
rows{10}=localPlot("C0_F10_timing_rmse","Timing RMSE", ...
    @()localMetric(points,"TimingRMSESamples","Timing RMSE (samples)"),"points.csv");
rows{11}=localPlot("C0_F11_cfo_error_cdf","CFO-estimation error CDF", ...
    @()localErrorCDF(raw.CFOErrorHz,"CFO error (Hz)"),"raw_trials.csv");
rows{12}=localPlot("C0_F12_cfo_rmse","CFO RMSE", ...
    @()localMetric(points,"CFORMSEHz","CFO RMSE (Hz)"),"points.csv");
rows{13}=localPlot("C0_F13_pbch_channel_nmse","PBCH channel-estimation NMSE", ...
    @()localMetric(points,"ChannelEstimateNMSE","Channel-estimation NMSE"),"points.csv");
rows{14}=localPlot("C0_F14_receiver_operation_counts","Measured receiver operation counts", ...
    @()localOperations(points),"points.csv");
rows{15}=localPlot("C0_F15_complete_ssb_success","Complete SSB success probability", ...
    @()localProbability(points,"CompleteSSBSuccessProbability", ...
    "CompleteSSBSuccessCILow","CompleteSSBSuccessCIHigh", ...
    "Complete SSB success"),"points.csv");
lineage = vertcat(rows{:});

    function row = localPlot(name,titleText,plotter,source,logScale)
        if nargin < 5, logScale=false; end
        f=figure("Visible","off","Color","w","Position",[100 100 1100 720]);
        cleanup=onCleanup(@()close(f)); %#ok<NASGU>
        plotter();
        ax=gca;
        grid(ax,"on");
        ax.Color="white";
        ax.XColor="black";
        ax.YColor="black";
        ax.GridColor=[0.75 0.75 0.75];
        ax.MinorGridColor=[0.85 0.85 0.85];
        if logScale, set(gca,"YScale","log"); end
        title({titleText;metadata},"Interpreter","none","Color","black");
        xlabel(ax,ax.XLabel.String,"Color","black");
        ylabel(ax,ax.YLabel.String,"Color","black");
        legends=findobj(f,"Type","legend");
        set(legends,"TextColor","black","Color","white");
        path=fullfile(figDir,name+".png");
        exportgraphics(f,path,"Resolution",150);
        row=table(string(name),string(path),string(source), ...
            string(sixgr.util.sha256Hex(fileread(fullfile(runFolder,source)))), ...
            sixgr.phy.waveform.WaveformArtifactExporter.fileSHA256(path), ...
            "SIMULATED","runtime_measurement", ...
            'VariableNames',{'FigureID','Path','SourceCSV','SourceSHA256','ImageSHA256','ClaimClass','EvidenceClass'});
    end
end

function localNoiseCDF(cal)
x=sort(cal.Metrics); y=(1:numel(x))'/numel(x);
plot(x,y,"-","LineWidth",1.2); hold on; xline(cal.Threshold,"--","Threshold");
xlabel("Maximum normalized search statistic"); ylabel("Empirical CDF");
end
function localFalseAlarm(v)
errorbar(1,v.EmpiricalPFA,v.EmpiricalPFA-v.CILow,v.CIHigh-v.EmpiricalPFA,"o","LineWidth",1.5); hold on;
yline(v.TargetPFA,"--","Target"); xlim([0.5 1.5]); xticks(1); xticklabels("global search"); ylabel("False-alarm probability");
end
function localProbability(T,name,lowName,highName,label)
y=double(T.(name)); low=double(T.(lowName)); high=double(T.(highName));
errorbar(T.SNRDB,y,max(0,y-low),max(0,high-y), ...
    "o-","LineWidth",1.2,"CapSize",8);
xlabel("Input SNR (dB)"); ylabel(label); ylim([0 1]);
end
function localMetric(T,name,label)
plot(T.SNRDB,T.(name),"o-","LineWidth",1.2); xlabel("Input SNR (dB)"); ylabel(label);
end
function localErrorCDF(values,label)
values=double(values); values=values(isfinite(values));
if isempty(values), values=NaN; end
x=sort(values); y=(1:numel(x))'/numel(x); plot(x,y,"-","LineWidth",1.2); xlabel(label); ylabel("Empirical CDF");
end
function localCrossings(T)
valid=T.Bracketed;
if any(valid)
    bar(categorical(T.Label(valid)),T.CrossingSNRDB(valid)); ylabel("Required SNR (dB)");
else
    axis off; text(0.5,0.5,"No simulated target crossing is bracketed in this run mode", ...
        "HorizontalAlignment","center","Units","normalized");
end
end
function localOperations(T)
plot(T.SNRDB,T.MeanSearchHypotheses,"o-","DisplayName","PSS hypotheses"); hold on;
plot(T.SNRDB,T.MeanDMRSHypotheses,"s-","DisplayName","DMRS hypotheses");
plot(T.SNRDB,T.MeanPolarDecodes,"^-","DisplayName","Polar decodes");
xlabel("Input SNR (dB)"); ylabel("Measured count per trial"); legend("Location","best");
end
