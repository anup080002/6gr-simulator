function lineage = plotIAResults(runFolder)
%PLOTIARESULTS Recreate C0 PNGs from saved measurements.
runFolder=char(string(runFolder));
cfg=sixgr.lls6g.config.readConfigFile(fullfile(runFolder,"config_resolved.yaml"));
raw=readtable(fullfile(runFolder,"raw_trials.csv"),"TextType","string");
points=readtable(fullfile(runFolder,"points.csv"),"TextType","string");
crossings=sixgr.phy.ia.c0.metrics.buildCrossingTable(points,cfg);
writetable(crossings,fullfile(runFolder,"target_crossings.csv"));
saved=load(fullfile(runFolder,"raw.mat"),"calibration","faValidation");
lineage=sixgr.phy.ia.c0.plots.renderC0Figures( ...
    runFolder,cfg,saved.calibration, ...
    saved.faValidation,raw,points,crossings);
writetable(lineage,fullfile(runFolder,"figure_lineage.csv"));
verification=sixgr.phy.ia.c0.util.verifyFigureLineage(runFolder,lineage);
writetable(verification,fullfile(runFolder,"artifact_verification.csv"));
if ~all(verification.Pass)
    error("sixgr:phy:ia:c0:validation:FigureVerificationFailed", ...
        "One or more regenerated C0 figures failed source/hash verification.");
end
gates=readtable(fullfile(runFolder,"truth_contract.csv"), ...
    "Delimiter",",","TextType","string", ...
    "VariableNamingRule","preserve");
applicable=logical(double(gates.Applicable));
gatePass=logical(double(gates.Pass));
summary=struct( ...
    "SmokeOrEngineeringPass",all(gatePass(applicable)), ...
    "TDocPass",false);
sixgr.phy.ia.c0.util.writeC0Report( ...
    runFolder,cfg,summary,saved.faValidation,points,crossings);
end
