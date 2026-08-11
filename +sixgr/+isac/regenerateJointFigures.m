function lineage = regenerateJointFigures(runFolder)
%REGENERATEJOINTFIGURES Regenerate all PNGs only from saved study data.

arguments
    runFolder (1,1) string
end
dataPath = fullfile(runFolder,"aggregate","joint_study_data.mat");
if exist(dataPath,"file") ~= 2
    error("sixgr:isac:MissingSavedStudyData", ...
        "Saved joint study data not found: %s",dataPath);
end
saved = load(dataPath,"cfg","tables","diagnostics","studies","aggregate");
cfg = saved.cfg;
contract = [sixgr.isac.figureContract();sixgr.isac.exampleFigureContract()];
names = strings(height(contract),1); paths = strings(height(contract),1);
sources = strings(height(contract),1); sourceHashes = strings(height(contract),1);
imageHashes = strings(height(contract),1); widths = zeros(height(contract),1);
heights = zeros(height(contract),1); statuses = strings(height(contract),1);
for i = 1:height(contract)
    stem = contract.FigureStem(i);
    folder = fullfile(runFolder,"figures",contract.Folder(i));
    if exist(folder,"dir") ~= 7, mkdir(folder); end
    path = fullfile(folder,stem+".png");
    fig = figure("Visible","off","Color","white", ...
        "Position",[80 80 double(cfg.output.imageSizePixels(:).')]);
    cleanup = onCleanup(@() localClose(fig)); %#ok<NASGU>
    localRender(fig,stem,saved);
    exportgraphics(fig,path,"Resolution",double(cfg.output.imageResolutionDPI));
    close(fig); clear cleanup;
    sourcePath = localSourcePath(runFolder,stem);
    if exist(sourcePath,"file") ~= 2
        error("sixgr:isac:MissingFigureSource", ...
            "Figure %s source table is missing: %s",stem,sourcePath);
    end
    info = imfinfo(path);
    names(i) = stem+".png";
    paths(i) = string(path);
    sources(i) = string(sourcePath);
    sourceHashes(i) = localFileHash(sourcePath);
    imageHashes(i) = localFileHash(path);
    widths(i) = info.Width; heights(i) = info.Height;
    statuses(i) = "pass";
end
lineage = table(names,paths,sources,sourceHashes,imageHashes,widths,heights,statuses, ...
    'VariableNames',{'FigureName','ImagePath','SourceCSV','SourceCSV_SHA256', ...
    'ImageSHA256','WidthPixels','HeightPixels','Status'});
writetable(lineage,fullfile(runFolder,"aggregate","figure_lineage.csv"));
end

function localRender(fig,stem,saved)
tables = saved.tables; diagnostics = saved.diagnostics;
studies = saved.studies; aggregate = saved.aggregate;
name = lower(stem);
if contains(name,"tr38901_scenario")
    localTR38901Scene(diagnostics.TR38901Geometry);
elseif contains(name,"tr38901_power_delay")
    localTR38901PDP(diagnostics.TR38901Paths);
elseif contains(name,"range_doppler_maps")
    localRangeDoppler(diagnostics.RangeDopplerMaps);
elseif contains(name,"geometry")
    localGeometry(tables.Table02_geometry);
elseif contains(name,"integration_chain") || contains(name,"transmitter_receiver_chains") || ...
        contains(name,"system_architecture") || contains(name,"sequence_flow") || ...
        contains(name,"selection_flowchart") || contains(name,"effective_pattern_collision_flow") || ...
        contains(name,"report_content")
    localFlowDiagram(stem,saved.cfg);
elseif contains(name,"beam_scope")
    localBeamScope(saved.cfg);
elseif contains(name,"best_beam")
    plot(studies.BeamManagement.InformationAgeMs, ...
        studies.BeamManagement.Top1NeighborhoodInclusion,"-o","LineWidth",2);
    ylabel("Top-1 neighborhood inclusion"); xlabel("Information age (ms)"); grid on;
elseif contains(name,"gain_gap")
    plot(studies.BeamManagement.InformationAgeMs,studies.BeamManagement.P90AngleGapDeg, ...
        "-o","LineWidth",2); ylabel("90th-percentile angle gap (deg)");
    xlabel("Information age (ms)"); grid on;
elseif contains(name,"measurement_cost_fallback")
    yyaxis left; plot(studies.BeamManagement.InformationAgeMs, ...
        studies.BeamManagement.MeanCommunicationMeasurements,"-o","LineWidth",2);
    ylabel("Communication measurements"); yyaxis right;
    plot(studies.BeamManagement.InformationAgeMs,studies.BeamManagement.FallbackRate, ...
        "-s","LineWidth",2); ylabel("Fallback rate"); xlabel("Information age (ms)"); grid on;
elseif contains(name,"tdd_delay_ambiguity")
    localTDDDelay(studies.TDD);
elseif contains(name,"tdd") || contains(name,"doppler_ambiguity")
    localTDD(studies.TDD,contains(name,"mask_doppler") || contains(name,"ambiguity"));
elseif contains(name,"periodic_phase_doppler_lines")
    localPeriodicSpectrum(studies.PeriodicPhase.Spectrum);
elseif contains(name,"periodic_phase_ghost_level")
    localPeriodicGhost(studies.PeriodicPhase.Summary);
elseif contains(name,"timing_update_models")
    localTimingUpdate(studies.TimingUpdate);
elseif contains(name,"velocity_rmse_event_classes")
    localCFOEvent(studies.CFOUpdate);
elseif contains(name,"angle_rmse_event_classes")
    localPortEvent(studies.PortPhase);
elseif contains(name,"event_models")
    localEventSummary(studies.EventSummary);
elseif contains(name,"single_phase")
    localEvent(studies.EventPhase,name);
elseif contains(name,"coherent_segments") || contains(name,"configured_effective") || ...
        contains(name,"puncture_vs_relocation") || contains(name,"effective_pattern_derivation") || ...
        contains(name,"action_classification") || contains(name,"segment_relation")
    localPatterns(studies.EffectivePatterns);
elseif contains(name,"coherency_budget") || contains(name,"budget_selected") || ...
        contains(name,"separate_vs_coupled")
    localBudget(studies.BudgetEvaluation);
elseif contains(name,"assistance_window")
    plot(studies.Assistance.DopplerHalfWidthCyclesPerSlot, ...
        studies.Assistance.ObservedWrongPeakRate,"-o","LineWidth",2);
    xlabel("Doppler assistance half-width (cycles/slot)"); ylabel("Observed wrong-peak rate"); grid on;
elseif contains(name,"frame_anchored_q") || contains(name,"boundary_continuity") || ...
        contains(name,"puncture_robustness")
    localW3(diagnostics.W3State,name);
elseif contains(name,"papr")
    localPAPRCCDF(diagnostics.PAPRCCDF);
elseif contains(name,"psd")
    localSpectrum(diagnostics.Spectrum);
elseif contains(name,"aperiodic")
    localACF(diagnostics.Autocorrelation);
elseif contains(name,"cross_ambiguity")
    bar(categorical(diagnostics.CrossAmbiguity.WaveformA+"/"+ ...
        diagnostics.CrossAmbiguity.WaveformB), ...
        diagnostics.CrossAmbiguity.MaximumNormalizedCrossCorrelation);
    ylabel("Maximum normalized cross-correlation"); grid on;
elseif contains(name,"isi_ici")
    localISIICI(studies.ISIICI);
elseif contains(name,"shared_resource_evm")
    localSharedCommunication(aggregate.Communication);
elseif contains(name,"self_and_intercell_interference")
    localInterference(studies.Interference);
elseif contains(name,"complexity")
    [group,profile] = findgroups(aggregate.Complexity.WaveformProfile);
    operations = splitapply(@mean,aggregate.Complexity.ReceiverOperationEstimate,group);
    bar(categorical(profile),operations);
    ylabel("Receiver operation estimate"); grid on;
elseif contains(name,"evm") || contains(name,"interference")
    localCommunication(aggregate.ProfileMetrics);
elseif contains(name,"pareto")
    scatter(aggregate.ProfileMetrics.MeanCommunicationEVMRMS, ...
        aggregate.ProfileMetrics.RangeRMSEM,55,aggregate.ProfileMetrics.CollisionRatioPercent,"filled");
    xlabel("Communication EVM RMS"); ylabel("Range RMSE (m)"); colorbar; grid on;
elseif contains(name,"heatmap")
    localPatternHeatmap(studies.EffectivePatterns);
elseif contains(name,"decision_summary") || contains(name,"scope_and_baselines")
    localWaveformSummary(diagnostics.WaveformSummary);
else
    localTrialMetric(aggregate.ProfileMetrics,name);
end
if ~any(contains(name,["range_doppler_maps","shared_resource_evm", ...
        "self_and_intercell_interference"]))
    title(strrep(stem,"_"," "),"Interpreter","none");
end
localStyle(gca,fig);
end

function localTR38901Scene(t)
if isempty(t), error("sixgr:isac:EmptyTR38901Geometry","TR 38.901 geometry is empty."); end
symbols=["^";"s";"o"];
colors=[.05 .35 .75;.1 .65 .42;.85 .3 .15];
hold on;
for i=1:height(t)
    plot3(t.X_m(i),t.Y_m(i),t.Z_m(i),symbols(min(i,3)), ...
        "MarkerSize",13,"LineWidth",2,"Color",colors(min(i,3),:), ...
        "DisplayName",t.Node(i));
    text(t.X_m(i),t.Y_m(i),t.Z_m(i)+1.2,"  "+t.Node(i));
end
target=find(t.Node=="Target",1); tx=find(t.Node=="STX",1); rx=find(t.Node=="SRX",1);
if ~isempty(target)&&~isempty(tx)
    plot3(t.X_m([tx target]),t.Y_m([tx target]),t.Z_m([tx target]),"--", ...
        "Color",[.05 .35 .75],"HandleVisibility","off");
end
if ~isempty(target)&&~isempty(rx)
    plot3(t.X_m([target rx]),t.Y_m([target rx]),t.Z_m([target rx]),"--", ...
        "Color",[.85 .3 .15],"HandleVisibility","off");
end
xlabel("x (m)"); ylabel("y (m)"); zlabel("z (m)"); axis equal; grid on;
view(38,24); legend("Location","best");
end

function localTR38901PDP(t)
if isempty(t), error("sixgr:isac:EmptyTR38901Paths","TR 38.901 path table is empty."); end
components=unique(t.Component,"stable"); hold on;
for i=1:numel(components)
    rows=t.Component==components(i);
    scatter(t.DelaySeconds(rows)*1e9,t.MeanPathPowerDb(rows),34,"filled", ...
        "DisplayName",components(i));
end
xlabel("Path delay (ns)"); ylabel("Mean path power (dB)"); grid on;
legend("Location","best");
end

function localRangeDoppler(t)
classes=["below_cp","at_cp","above_cp"];
layout=tiledlayout(gcf,1,3,"TileSpacing","compact","Padding","compact");
for i=1:numel(classes)
    nexttile(layout); rows=t.DelayClass==classes(i);
    ranges=unique(t.RangeM(rows)); doppler=unique(t.DopplerHz(rows));
    power=reshape(t.PowerRelativeDb(rows),numel(ranges),numel(doppler));
    imagesc(doppler,ranges,power); axis xy; clim([-45 0]);
    hold on; plot(t.ExpectedDopplerHz(find(rows,1)), ...
        t.ExpectedRangeM(find(rows,1)),"wx","MarkerSize",10,"LineWidth",2);
    title(strrep(classes(i),"_"," ")); xlabel("Doppler (Hz)");
    if i==1, ylabel("Range (m)"); end
end
colorbar;
layoutTitle=title(layout,"Measured W0 range-Doppler response: below, at, and above CP", ...
    "Interpreter","none");
layoutTitle.Color=[.08 .08 .08];
end

function localGeometry(t)
if isempty(t), error("sixgr:isac:EmptyGeometryEvidence","Geometry table is empty."); end
plot3(t.TxX_m,t.TxY_m,t.TxZ_m,"^","MarkerSize",12,"LineWidth",2,"DisplayName","STX"); hold on;
plot3(t.RxX_m,t.RxY_m,t.RxZ_m,"s","MarkerSize",12,"LineWidth",2,"DisplayName","SRX");
plot3(t.TargetX_m,t.TargetY_m,t.TargetZ_m,"o","MarkerSize",10,"LineWidth",2,"DisplayName","Target");
for i=1:height(t)
    plot3([t.TxX_m(i),t.TargetX_m(i)],[t.TxY_m(i),t.TargetY_m(i)], ...
        [t.TxZ_m(i),t.TargetZ_m(i)],"--","Color",[.2 .45 .8],"HandleVisibility","off");
    plot3([t.TargetX_m(i),t.RxX_m(i)],[t.TargetY_m(i),t.RxY_m(i)], ...
        [t.TargetZ_m(i),t.RxZ_m(i)],"--","Color",[.8 .35 .2],"HandleVisibility","off");
end
xlabel("x (m)"); ylabel("y (m)"); zlabel("z (m)"); axis equal; grid on; view(35,25); legend;
end

function localFlowDiagram(stem,cfg)
axis off; hold on;
labels = ["YAML resource + events","W0-W3 grid","CP-OFDM Tx", ...
    "common channel/target","shared Rx samples","measurement + report"];
x = linspace(.08,.82,numel(labels));
for i=1:numel(labels)
    rectangle("Position",[x(i),.42,.13,.18],"Curvature",.08, ...
        "FaceColor",[.88 .95 .94],"EdgeColor",[.05 .35 .32],"LineWidth",1.5);
    text(x(i)+.065,.51,labels(i),"HorizontalAlignment","center","FontSize",9);
    if i<numel(labels)
        annotation(gcf,"arrow",[x(i)+.13,x(i+1)],[.51,.51],"LineWidth",1.5);
    end
end
text(.5,.75,string(cfg.study.id),"HorizontalAlignment","center","FontWeight","bold");
text(.5,.25,"One transmitted waveform and one receiver observation feed both 10.8.2 and 10.8.3", ...
    "HorizontalAlignment","center");
end

function localBeamScope(cfg)
narrow = linspace(cfg.beamManagement.narrowAngleRangeDeg(1), ...
    cfg.beamManagement.narrowAngleRangeDeg(2),cfg.beamManagement.narrowBeamCount);
wide = linspace(cfg.beamManagement.narrowAngleRangeDeg(1), ...
    cfg.beamManagement.narrowAngleRangeDeg(2),cfg.beamManagement.wideBeamCount);
stem(wide,ones(size(wide)),"filled","DisplayName","wide"); hold on;
stem(narrow,.55*ones(size(narrow)),".","DisplayName","narrow");
xlabel("Beam boresight (deg)"); ylabel("Relative scope"); legend; grid on;
end

function localTDD(t,responsePlot)
patterns = unique(t.TDDPattern,"stable"); hold on;
for i=1:numel(patterns)
    rows=t.TDDPattern==patterns(i);
    if responsePlot
        responseDb=max(-60,10*log10(max(t.MaskDFTPowerNormalized(rows),realmin)));
        plot(t.NormalizedDopplerBin(rows),responseDb, ...
            "LineWidth",1.5,"DisplayName",patterns(i));
        xlabel("Normalized Doppler bin"); ylabel("Mask response (dB)");
    else
        stairs(t.SlotIndex(rows),t.DLSensingAvailable(rows)+i-1,"LineWidth",1.5,"DisplayName",patterns(i));
        xlabel("Slot index"); ylabel("DL sensing mask + offset");
    end
end
legend("Location","best"); grid on;
end

function localTDDDelay(t)
patterns=unique(t.TDDPattern,"stable"); hold on;
for i=1:numel(patterns)
    mask=t.DLSensingAvailable(t.TDDPattern==patterns(i));
    acf=xcorr(mask,"normalized"); lags=(-(numel(mask)-1):(numel(mask)-1)).';
    plot(lags,acf,"LineWidth",1.4,"DisplayName",patterns(i));
end
xlabel("Slot lag"); ylabel("Normalized mask autocorrelation");
legend("Location","best"); grid on;
end

function localEvent(t,name)
hold on; positions=unique(t.FractionBeforeEvent);
for i=1:numel(positions)
    rows=t.FractionBeforeEvent==positions(i);
    y=t.CoherentGainDb(rows);
    if contains(name,"rmse"), y=abs(t.MeasuredDopplerBiasHz(rows)); end
    if contains(name,"wrong_peak"), y=double(t.WrongPeak(rows)); end
    plot(t.PhaseStepDeg(rows),y,"-o","DisplayName",sprintf("event %.0f%%",100*positions(i)));
end
xlabel("Common phase step (deg)"); ylabel("Measured event response"); legend; grid on;
end

function localPeriodicSpectrum(t)
rows=t.PhaseStepDeg==max(t.PhaseStepDeg); periods=unique(t.HalfPeriodOccasions); hold on;
for i=1:numel(periods)
    selected=rows&t.HalfPeriodOccasions==periods(i);
    plot(t.NormalizedDopplerOffset(selected),max(-60,t.PowerDb(selected)), ...
        "LineWidth",1.4,"DisplayName","P="+string(periods(i)));
end
xlabel("Normalized Doppler offset"); ylabel("Matched-observation spectrum (dB)");
legend; grid on;
end

function localPeriodicGhost(t)
labels=categorical("P"+string(t.HalfPeriodOccasions)+" "+string(t.PhaseStepDeg)+"deg");
bar(labels,t.GhostPowerNormalized); ylabel("Strongest nonzero-bin power / peak");
xtickangle(45); grid on;
end

function localTimingUpdate(t)
models=unique(t.TimingModel,"stable"); hold on;
for i=1:numel(models)
    rows=t.TimingModel==models(i);
    plot(t.OffsetNativeBins(rows),t.CoherentGainDb(rows),"-o", ...
        "LineWidth",1.5,"DisplayName",models(i));
end
xlabel("Timing update (native delay bins)"); ylabel("Measured coherent gain (dB)");
legend; grid on;
end

function localCFOEvent(t)
plot(t.ResidualFrequencyHz,t.EquivalentMonostaticVelocityBiasMps,"-o","LineWidth",1.7);
xlabel("Residual frequency update (Hz)"); ylabel("Equivalent velocity bias (m/s)"); grid on;
end

function localPortEvent(t)
plot(t.PortPhaseSlopeDeg,abs(t.AzimuthErrorDeg),"-o","LineWidth",1.7);
xlabel("Port phase slope (deg/port)"); ylabel("Measured angle error (deg)"); grid on;
end

function localEventSummary(t)
types=unique(t.EventType,"stable"); values=zeros(numel(types),1);
for i=1:numel(types), values(i)=median(abs(t.MeasuredBias(t.EventType==types(i))),"omitnan"); end
bar(categorical(types),values); ylabel("Median absolute measured event bias"); xtickangle(25); grid on;
end

function localPatterns(t)
labels = categorical(t.Response+"/"+string(t.CollisionRatioPercent)+"%");
bar(labels,t.RetainedObservations); ylabel("Retained observations"); grid on;
end

function localBudget(t)
measurements=unique(t.Measurement,"stable"); hold on;
for i=1:numel(measurements)
    rows=t.Measurement==measurements(i);
    scatter(t.Cost(rows),t.MinimumSegmentLength(rows),70,t.Feasible(rows),"filled", ...
        "DisplayName",measurements(i));
end
xlabel("Transparent study cost"); ylabel("Minimum segment length"); legend; grid on;
end

function localW3(t,name)
yyaxis left; stairs(t.AbsoluteSymbolIndex,t.CumulativeCPStateQ,"-o","LineWidth",1.8);
ylabel("q(l) samples"); yyaxis right;
stem(t.AbsoluteSymbolIndex,t.ConfiguredSensingRE,"filled"); ylabel("Configured sensing RE");
xlabel("Absolute symbol index"); grid on;
if contains(name,"continuity"), xline(6.5,"--","puncture does not reset q"); end
end

function localSpectrum(t)
profiles=unique(t.WaveformProfile,"stable"); hold on;
for i=1:numel(profiles)
    rows=t.WaveformProfile==profiles(i);
    plot(t.FrequencyHz(rows)/1e6,t.PowerRelativeDb(rows),"DisplayName",profiles(i));
end
xlabel("Frequency (MHz)"); ylabel("Relative PSD (dB)"); ylim([-100 5]); legend; grid on;
end

function localACF(t)
profiles=unique(t.WaveformProfile,"stable"); types=unique(t.ACFType,"stable"); hold on;
for i=1:numel(profiles)
    for j=1:numel(types)
        rows=t.WaveformProfile==profiles(i)&t.ACFType==types(j);
        plot(t.LagSamples(rows),t.PowerRelativeDb(rows), ...
            "DisplayName",profiles(i)+" "+types(j));
    end
end
xlabel("Lag (samples)"); ylabel("ACF (dB)"); ylim([-100 5]); legend; grid on;
end

function localPAPRCCDF(t)
profiles=unique(t.WaveformProfile,"stable"); hold on;
for i=1:numel(profiles)
    rows=t.WaveformProfile==profiles(i);
    semilogy(t.PAPRThresholdDb(rows),max(t.EmpiricalCCDF(rows),1e-4), ...
        "LineWidth",1.5,"DisplayName",profiles(i));
end
xlabel("PAPR threshold (dB)"); ylabel("Empirical CCDF"); ylim([1e-4 1]); legend; grid on;
end

function localCommunication(t)
profiles=unique(t.WaveformProfile,"stable"); values=zeros(numel(profiles),1);
for i=1:numel(profiles), values(i)=mean(t.MeanCommunicationEVMRMS(t.WaveformProfile==profiles(i))); end
bar(categorical(profiles),values); ylabel("Mean communication EVM RMS"); grid on;
end

function localSharedCommunication(t)
layout=tiledlayout(gcf,1,3,"TileSpacing","compact","Padding","compact");
nexttile(layout); bar(categorical(t.WaveformProfile),t.MeanCommunicationEVMRMS);
ylabel("EVM RMS"); title("EVM"); grid on;
nexttile(layout); bar(categorical(t.WaveformProfile),t.MeanUncodedSymbolErrorRate);
ylabel("Uncoded SER"); title("Uncoded data errors"); grid on;
nexttile(layout); bar(categorical(t.WaveformProfile),t.MeanUncodedGoodputBps/1e6);
ylabel("Goodput (Mbit/s)"); title("Uncoded goodput"); grid on;
layoutTitle=title(layout,"Shared-resource communication measurements","Interpreter","none");
layoutTitle.Color=[.08 .08 .08];
end

function localInterference(t)
layout=tiledlayout(gcf,1,2,"TileSpacing","compact","Padding","compact");
nexttile(layout); rows=t.InterferenceType=="intercell_async";
scatter(t.RelativePowerDb(rows),t.CommunicationEVMRMS(rows),55, ...
    t.FrequencyOffsetHz(rows),"filled"); xlabel("Inter-cell relative power (dB)");
ylabel("Communication EVM RMS"); colorbar; grid on; title("Asynchronous inter-cell");
nexttile(layout); rows=t.InterferenceType=="monostatic_self";
semilogy(t.RelativePowerDb(rows),t.InterferencePowerRatio(rows),"-o","LineWidth",1.5);
xlabel("Residual self-interference (dB)"); ylabel("Residual / echo power");
grid on; title("Monostatic residual self-interference");
layoutTitle=title(layout,"Executed self- and inter-cell interference studies","Interpreter","none");
layoutTitle.Color=[.08 .08 .08];
end

function localISIICI(t)
profiles=unique(t.WaveformProfile,"stable"); dopplers=unique(t.NormalizedDoppler); hold on;
for i=1:numel(profiles)
    for j=1:numel(dopplers)
        rows=t.WaveformProfile==profiles(i)&t.NormalizedDoppler==dopplers(j);
        plot(t.DelayOverCP(rows),t.ResidualEVMRMS(rows),"-o", ...
            "DisplayName",profiles(i)+" nu="+string(dopplers(j)));
    end
end
xlabel("Echo delay / CP"); ylabel("Residual EVM after diagonal equalization");
legend("Location","bestoutside"); grid on;
end

function localPatternHeatmap(t)
responses=unique(t.Response,"stable"); ratios=unique(t.CollisionRatioPercent);
z=nan(numel(ratios),numel(responses));
for i=1:numel(ratios), for j=1:numel(responses)
    rows=t.CollisionRatioPercent==ratios(i)&t.Response==responses(j);
    if any(rows)
        z(i,j)=mean(t.RetainedObservations(rows)./t.ConfiguredObservations(rows));
    end
end, end
imagesc(1:numel(responses),ratios,z,[0 1]);
set(gca,"XTick",1:numel(responses),"XTickLabel",responses,"XTickLabelRotation",30);
xlabel("Collision response"); ylabel("Collision ratio (%)");
cb=colorbar; cb.Label.String="Retained sensing-observation fraction";
end

function localWaveformSummary(t)
bar(categorical(t.WaveformProfile),[t.PAPRDb,t.ConfiguredSensingRE]);
ylabel("Measured value"); legend("PAPR dB","Sensing RE"); grid on;
end

function localTrialMetric(t,name)
hold on; profiles=unique(t.WaveformProfile,"stable");
for i=1:numel(profiles)
    rows=t.WaveformProfile==profiles(i)&t.CollisionRatioPercent==0;
    [x,order]=sort(t.DelayOverCP(rows));
    if contains(name,"wrong") || contains(name,"sidelobe")
        y=t.WrongPeakProbability(rows);
    elseif contains(name,"pd_pfa")
        y=t.DetectionProbability(rows);
    elseif contains(name,"velocity") || contains(name,"doppler")
        y=t.DopplerRMSEHz(rows);
    elseif contains(name,"angle")
        y=t.AngleRMSEDeg(rows);
    else
        y=t.RangeRMSEM(rows);
    end
    y=y(order);
    finite=isfinite(x)&isfinite(y);
    if any(finite), plot(x(finite),y(finite),"-o","DisplayName",profiles(i)); end
end
xlabel("Delay / CP"); ylabel("Measured metric"); legend; grid on;
end

function path = localSourcePath(runFolder,stem)
name=lower(stem); tableStem="Table04_profile_metrics";
if contains(name,"tr38901_scenario"), path=fullfile(runFolder,"aggregate","tr38901_example_geometry.csv"); return;
elseif contains(name,"tr38901_power_delay"), path=fullfile(runFolder,"aggregate","tr38901_example_paths.csv"); return;
elseif contains(name,"range_doppler_maps"), path=fullfile(runFolder,"aggregate","range_doppler_maps.csv"); return;
elseif contains(name,"papr"), path=fullfile(runFolder,"aggregate","papr_ccdf.csv"); return;
elseif contains(name,"psd"), path=fullfile(runFolder,"aggregate","waveform_spectrum.csv"); return;
elseif contains(name,"aperiodic"), path=fullfile(runFolder,"aggregate","waveform_autocorrelation.csv"); return;
elseif contains(name,"cross_ambiguity"), path=fullfile(runFolder,"aggregate","cross_ambiguity.csv"); return;
elseif contains(name,"periodic_phase_ghost"), path=fullfile(runFolder,"aggregate","periodic_phase_summary.csv"); return;
elseif contains(name,"periodic_phase"), path=fullfile(runFolder,"aggregate","periodic_phase_spectrum.csv"); return;
elseif contains(name,"timing_update"), path=fullfile(runFolder,"aggregate","timing_update_events.csv"); return;
elseif contains(name,"velocity_rmse_event"), path=fullfile(runFolder,"aggregate","residual_frequency_events.csv"); return;
elseif contains(name,"angle_rmse_event"), path=fullfile(runFolder,"aggregate","port_phase_events.csv"); return;
elseif contains(name,"isi_ici"), path=fullfile(runFolder,"aggregate","isi_ici_study.csv"); return;
elseif contains(name,"self_and_intercell_interference"), path=fullfile(runFolder,"aggregate","interference_study.csv"); return;
elseif contains(name,"scope_and_baselines"), tableStem="Table12_waveform_summary";
elseif contains(name,"geometry"), tableStem="Table02_geometry";
elseif contains(name,"chain")||contains(name,"architecture")||contains(name,"scope"), tableStem="Table01_assumptions";
elseif contains(name,"event")||contains(name,"phase")||contains(name,"timing_update"), tableStem="Table05_coherency_events";
elseif contains(name,"pattern")||contains(name,"puncture")||contains(name,"collision_flow")||contains(name,"segment_relation")||contains(name,"action_classification"), tableStem="Table06_effective_patterns";
elseif contains(name,"budget")||contains(name,"selection"), tableStem="Table07_coherency_budget";
elseif contains(name,"tdd")||contains(name,"ambiguity"), tableStem="Table08_tdd_patterns";
elseif contains(name,"heatmap"), tableStem="Table06_effective_patterns";
elseif contains(name,"beam")||contains(name,"gain_gap")||contains(name,"fallback_vs_age"), tableStem="Table09_beam_management";
elseif contains(name,"assistance"), tableStem="Table10_assistance";
elseif contains(name,"papr")||contains(name,"decision_summary"), tableStem="Table12_waveform_summary";
elseif contains(name,"evm")||contains(name,"interference"), tableStem="Table13_communication_metrics";
elseif contains(name,"complexity"), tableStem="Table14_complexity";
elseif contains(name,"frame_anchored")||contains(name,"boundary_continuity"), tableStem="Table15_w3_absolute_state";
end
path=fullfile(runFolder,"tables",tableStem+".csv");
end

function localStyle(ax,fig)
axesObjects=findall(fig,"Type","axes");
for i=1:numel(axesObjects)
    axisObject=axesObjects(i);
    set(axisObject,"FontSize",11,"LineWidth",1,"Color","white", ...
        "XColor",[.1 .1 .1],"YColor",[.1 .1 .1],"ZColor",[.1 .1 .1]);
    axisObject.Title.Color=[.08 .08 .08];
    axisObject.XLabel.Color=[.08 .08 .08];
    axisObject.YLabel.Color=[.08 .08 .08];
    axisObject.ZLabel.Color=[.08 .08 .08];
end
legends=findall(fig,"Type","legend");
for i=1:numel(legends)
    set(legends(i),"Color","white","TextColor",[.08 .08 .08], ...
        "EdgeColor",[.65 .65 .65]);
end
colorbars=findall(fig,"Type","colorbar");
for i=1:numel(colorbars), colorbars(i).Color=[.08 .08 .08]; end
set(fig,"InvertHardcopy","off");
end

function localClose(fig)
if isgraphics(fig), close(fig); end
end

function hash = localFileHash(path)
fid=fopen(path,"rb");
if fid<0, error("sixgr:isac:FileHashReadFailed","Cannot read %s.",path); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end
