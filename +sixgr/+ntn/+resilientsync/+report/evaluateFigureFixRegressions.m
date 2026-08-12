function checks = evaluateFigureFixRegressions(runDirectory,scenario)
%EVALUATEFIGUREFIXREGRESSIONS Fail-closed checks for Figure 2-1--2-22.
arguments
    runDirectory (1,1) string
    scenario (1,1) struct
end
pub=fullfile(char(runDirectory),char(scenario.outputs.public_dir));
names=strings(15,1);passed=false(15,1);actual=strings(15,1);expected=strings(15,1);tol=strings(15,1);
index=0;

    function add(id,ok,a,e,t)
        index=index+1;names(index)=id;passed(index)=logical(ok);actual(index)=string(a);expected(index)=string(e);tol(index)=string(t);
    end

f3=localRead(pub,'fig_2_03_timing_bound_vs_age');r=f3(f3.PositionAge_s==60,:);
target=[.689,3.289,11.955,24.473];observed=localAt(r,'Speed_kmh',[3 30 120 250],'AbsoluteET_us');
add("A_holdover_cos30",max(abs(observed-target))<.03,mat2str(observed,6),mat2str(target,6),"0.03 us");

f4=localRead(pub,'fig_2_04_frequency_bound_vs_speed');two=f4(f4.CarrierId=="S_band",:);thirty=f4(f4.CarrierId=="Ka_generic",:);
o=[localAt(two,'Speed_kmh',[3 30 120 250],'GeometricFrequencyErrorBound_kHz'),localAt(thirty,'Speed_kmh',[3 30 120 250],'GeometricFrequencyErrorBound_kHz')];
t=[.005 .048 .193 .402 .077 .727 2.894 6.023];monotonic=all(diff(two.GeometricFrequencyErrorBound_kHz)>0)&&all(diff(thirty.GeometricFrequencyErrorBound_kHz)>0);
add("B_geometric_frequency",monotonic&&max(abs(o-t))<.01,mat2str(o,6),mat2str(t,6),"0.01 kHz + monotonic");

f5=localRead(pub,'fig_2_05_reference_area_timing_cdf');radii=unique(f5.Radius_km).';
add("C_four_timing_cdfs",isequal(radii,[5 12.5 25 50]),mat2str(radii),"[5 12.5 25 50]","exact groups");
add("D_figure_2_7_exists",isfile(fullfile(pub,'fig_2_07_timing_vs_elevation.png')),"file state","PNG present","exact");

f9=localRead(pub,'fig_2_09_acquisition_vs_ordinary_regions');valid9=all(~f9.EmpiricalContoursAvailable)&&all(ismember(unique(f9.Region),["initial acquisition conceptual bound";"ordinary UL conceptual bound"]));
add("E_acquisition_region_semantics",valid9,"conceptual="+string(valid9),"conceptual ellipses; no empirical claim","exact");

f10=localRead(pub,'fig_2_10_compensation_responsibility');f16=localRead(pub,'fig_2_16_compensation_state_matrix');validCategorical=height(f10)==3&&all(ismember({'ULRPLocation','UEResponsibility','FeederResponsibility','AssistanceImplication'},f10.Properties.VariableNames))&&all(ismember({'MatrixRow','MatrixColumn'},f16.Properties.VariableNames));
add("F_categorical_architecture",validCategorical,"architecture rows="+height(f10)+", state rows="+height(f16),"3 architectures and 2x2 categorical state","exact");

f12=localRead(pub,'fig_2_12_koffset_ta_timeline');
add("G_timeline_not_quantizer",height(f12)==8&&ismember('EventOrder',f12.Properties.VariableNames),"events="+height(f12),"8 ordered events","exact");

f14=localRead(pub,'fig_2_14_koffset_excess_delay_cdf');s14=localStats(f14,'Level','Mean_ms','P95_ms','Maximum_ms',["UE-specific","Beam-specific","Cell-specific"]);
t14=[.070 .122 .125;.193 .344 .439;5.834 9.121 9.122];
add("H_koffset_excess",max(abs(s14-t14),[],'all')<.18,mat2str(s14,5),mat2str(t14,5),"0.18 ms Monte-Carlo envelope");

f15=localRead(pub,'fig_2_15_koffset_update_timescale');valid15=numel(unique(f15.SCS_kHz))==3&&all(f15.TimeToOneSlot_s>0)&all(isfinite(f15.TimeToOneSlot_s));
add("I_rtt_update_timescale",valid15,"SCS="+mat2str(unique(f15.SCS_kHz).'),"[30 60 120] kHz, positive finite","exact domain");

f18=localRead(pub,'fig_2_18_estimator_observation_interval');cases=[2e9 .5 10;2e9 .2 10;30e9 .5 10;30e9 .2 20];o18=zeros(1,4);
for i=1:4,row=f18(f18.ULCarrier_Hz==cases(i,1)&f18.TimingSigma_us==cases(i,2)&f18.ObservationInterval_s==cases(i,3),:);o18(i)=row.ULResidualFrequencySigma_Hz(1);end
t18=[77 41 1150 500];add("J_estimator_examples",max(abs(o18-t18)./t18)<.03,mat2str(o18,6),mat2str(t18),"3% analytical rounding");

f19=localRead(pub,'fig_2_19_search_threshold_scaling');o19=localAt(f19,'Hypotheses',[4 196 1016 8128],'RelativeThresholdPenalty_dB');t19=[0 2.17 2.84 3.56];
add("K_search_penalty",max(abs(o19-t19))<.04,mat2str(o19,5),mat2str(t19),"0.04 dB");

f20=localRead(pub,'fig_2_20_timing_pipeline_cdf');s20=localStats(f20,'Level','MeanSlots','P95Slots','MaximumSlots',["UE-specific","Beam-specific","Cell-specific"]);t20=[66.9 112 113;67.9 113 113;113 113 113];
add("L_timing_pipeline",max(abs(s20-t20),[],'all')<1.5,mat2str(s20,5),mat2str(t20,5),"1.5 slots Monte-Carlo envelope");

f21=localRead(pub,'fig_2_21_ta_guard_and_collision');r21=f21(f21.SCS_kHz==120,:);order=["Beam-specific bound","1 ms report step","0.5 ms report step","0.1 ms report step"];o21=localAt(r21,'GuardSource',order,'RequiredGuardSlots');
add("M_ta_guard_slots",isequal(o21,[3 8 4 1]),mat2str(o21),"[3 8 4 1]","exact ceil");

f22=localRead(pub,'fig_2_22_residual_cfo_impact');r1=f22(abs(f22.AbsoluteNormalizedCFO-.1)<1e-12&f22.InputSNR_dB==10,:);r2=f22(abs(f22.AbsoluteNormalizedCFO-.2)<1e-12&f22.InputSNR_dB==10,:);
o22=[r1.ICISIR_dB(1),r1.EffectiveSNRLoss_dB(1),r2.EffectiveSNRLoss_dB(1)];t22=[14.7 1.36 4.10];
add("N_normalized_cfo",max(abs(o22-t22))<.08,mat2str(o22,5),mat2str(t22),"0.08 dB");

files=dir(fullfile(pub,'*.metadata.json'));honest=true;bad=strings(0,1);
for i=1:numel(files),m=jsondecode(fileread(fullfile(files(i).folder,files(i).name)));if logical(m.Measured)&&string(sixgr.util.structGet(m,'CalibrationStatus',''))~="ACCEPTED",honest=false;bad(end+1)=string(files(i).name);end,end %#ok<AGROW>
add("O_calibrated_claim_guard",honest,strjoin(bad,'|'),"no measured claim without ACCEPTED calibration","exact");

checks=table(names,passed,actual,expected,tol,repmat(string(scenario.ConfigSHA256),numel(names),1), ...
    'VariableNames',{'Check','Pass','Actual','Expected','Tolerance','ConfigSHA256'});
writetable(checks,fullfile(char(runDirectory),'acceptance','figure_fix_regression.csv'));
comparison=localComparison(f3,f4,f14,f20);writetable(comparison,fullfile(char(runDirectory),'before_after_metric_comparison.csv'));
localReport(runDirectory,checks,comparison);
end

function T=localRead(folder,name)
path=fullfile(folder,[name '.csv']);if ~isfile(path),error('sixgr:ntn:resilientsync:MissingFigureFixArtifact','Missing %s.',path);end
T=readtable(path,'TextType','string','VariableNamingRule','preserve');
end
function values=localAt(T,key,keys,value)
keys=keys(:);values=zeros(1,numel(keys));for i=1:numel(keys),if isstring(keys),mask=string(T.(key))==keys(i);else,mask=T.(key)==keys(i);end;row=T(mask,:);values(i)=row.(value)(1);end
end
function s=localStats(T,group,m,p,x,labels)
s=zeros(numel(labels),3);for i=1:numel(labels),row=T(string(T.(group))==labels(i),:);s(i,:)=[row.(m)(1),row.(p)(1),row.(x)(1)];end
end
function T=localComparison(f3,f4,f14,f20)
metric=["Figure 2-3, 250 km/h at 60 s";"Figure 2-4 public series";"Figure 2-14 cell max";"Figure 2-20 cell pipeline"];
before=["full speed projection (too high)";"signed/oscillator/stress mixture";"relative RTT, <0.4 ms";"constant reference near 41 slots"];
r=f3(f3.Speed_kmh==250&f3.PositionAge_s==60,:);r14=f14(f14.Level=="Cell-specific",:);r20=f20(f20.Level=="Cell-specific",:);
after=[compose('%.6g us, cos(30 deg)',r.AbsoluteET_us(1));strjoin(unique(f4.CarrierId),' + ')+", monotonic";compose('%.6g ms absolute RTT',r14.Maximum_ms(1));compose('%.6g slots absolute RTT',r20.MaximumSlots(1))];
definition=["LOS motion projection";"geometric uplink bound only";"global maximum absolute RTT";"absolute RTT plus processing delay"];
T=table(metric,before,after,definition,'VariableNames',{'Metric','BeforeDefect','AfterValue','CorrectedDefinition'});
end
function localReport(root,checks,comparison)
fid=fopen(fullfile(char(root),'figure_fix_report.md'),'w','n','UTF-8');if fid<0,error('sixgr:ntn:resilientsync:WriteFailed','Cannot write figure fix report.');end
cleanup=onCleanup(@() fclose(fid));if all(checks.Pass),overall="PASS";else,overall="FAIL";end
fprintf(fid,'# NTN public-figure repair report\n\nOverall: **%s** (%d/%d checks passed).\n\n',overall,sum(checks.Pass),height(checks));
fprintf(fid,'| Check | Pass | Actual | Expected | Tolerance |\n|---|---:|---|---|---|\n');for i=1:height(checks),fprintf(fid,'| %s | %d | %s | %s | %s |\n',checks.Check(i),checks.Pass(i),checks.Actual(i),checks.Expected(i),checks.Tolerance(i));end
fprintf(fid,'\n## Before/after definitions\n\n');for i=1:height(comparison),fprintf(fid,'- **%s:** %s -> %s (%s)\n',comparison.Metric(i),comparison.BeforeDefect(i),comparison.AfterValue(i),comparison.CorrectedDefinition(i));end
fprintf(fid,'\nEmpirical Figure 2-9 and measured overlays for Figures 2-18/2-19/2-22 remain fail-closed until their dedicated calibrated acceptance evidence is complete. Their public analytical/conceptual figures are not labeled measured.\n');
fprintf(fid,'\nExact rerun command: `matlab -batch "setup6GRSimToolkit(''Verbose'',false); sixgr.ntn.resilientsync.runAllCampaigns(''configs/ntn_resilient_sync/quick.yaml'',''RunId'',''%s_rerun'')"`\n',char(string(jsondecode(fileread(fullfile(char(root),'config','resolved_config.json'))).RunId)));
end
