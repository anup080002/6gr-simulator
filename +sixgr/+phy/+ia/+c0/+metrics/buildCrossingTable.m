function crossings = buildCrossingTable(points,cfg)
%BUILDCROSSINGTABLE Build the four C0 required-SNR crossing rows.
metrics=["JointSSMDR" "JointSSMDR" "PBCHBLER" "PBCHBLER"];
targets=[double(cfg.statistics.mdr_targets(:)); ...
    double(cfg.statistics.pbch_bler_targets(:))];
labels=["gamma_SS_10" "gamma_SS_1" "gamma_PBCH_10" "gamma_PBCH_1"];
rows=cell(4,1);
for k=1:4
    row=sixgr.phy.ia.c0.metrics.findTargetCrossing( ...
        points,metrics(k),targets(k));
    row.Label=labels(k);
    rows{k}=row;
end
crossings=struct2table(vertcat(rows{:}),"AsArray",true);
end
