function testCSIFigureContract()
%TESTCSIFIGURECONTRACT Validate semantic figure and short-run contracts.
[figures,metadata]=sixgr.csi.CSITDocStudyFigureContract.load();
assert(numel(figures)==20 && strlength(metadata.SHA256)==64);
ids=string({figures.figure_id}); assert(numel(unique(ids))==20);
for k=1:numel(figures)
    assert(~endsWith(string(figures(k).x_axis_label),"Index","IgnoreCase",true));
    assert(~contains(string(figures(k).y_axis_label),"Units","IgnoreCase",true));
    assert(strlength(string(figures(k).units))>0);
    assert(strlength(string(figures(k).limitations_text))>0);
    sixgr.csi.CSITDocStudyEvidenceClass.validateFigure(string(figures(k).evidence_class));
end
[cfg,~]=sixgr.csi.loadTDocStudyConfig( ...
    "simulator/configs/csi_tdoc/figure_fix_short.yaml");
assert(cfg.simulation.bounded_transport_blocks_per_point==1);
assert(cfg.interference_age.sanity_trials==128);
assert(cfg.event_csi.sanity_slots==128);
assert(cfg.multislot.monte_carlo_trials==128);
a=sixgr.csi.runTDocStudyAnalyticalScenarios(cfg);
p=sixgr.csi.runTDocStudyProcedureScenarios(cfg);
assert(all(isfinite(a.InterferenceAge.RMSECI95LowdB)) && ...
    all(isfinite(a.InterferenceAge.RMSECI95HighdB)));
assert(all(a.InterferenceAge.N==128) && all(isfinite(a.InterferenceAge.Seed)));
assert(all(isfinite(a.MultislotIID.GainCI95Low)) && ...
    all(isfinite(a.MultislotIID.GainCI95High)));
assert(all(p.EventPareto.N==128) && all(isfinite(p.EventPareto.Seed)));
assert(all(p.EventPareto.MAECI95Low<=p.EventPareto.MeanAbsoluteStateError));
assert(all(p.EventPareto.MAECI95High>=p.EventPareto.MeanAbsoluteStateError));
folder=string(tempname); mkdir(folder);
folderCleanup=onCleanup(@()rmdir(folder,"s")); %#ok<NASGU>
fig=figure("Visible","off","Color","white");
figureCleanup=onCleanup(@()close(fig)); %#ok<NASGU>
plot(1:3,[1 4 2],"o-");
first=fullfile(folder,"first.pdf"); second=fullfile(folder,"second.pdf");
print(fig,first,"-dpdf","-painters");
pause(1.1);
print(fig,second,"-dpdf","-painters");
sixgr.csi.canonicalizeStudyPDF(first); sixgr.csi.canonicalizeStudyPDF(second);
assert(sixgr.csi.studyFileSHA256(first)==sixgr.csi.studyFileSHA256(second), ...
    "Canonical vector PDF hashes must be independent of export time and trailer ID.");
fprintf("testCSIFigureContract: PASS (20 semantic figures, 128-sample short profile)\n");
end
