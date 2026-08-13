function crossings = buildCrossingTable(points,cfg)
%BUILDCROSSINGTABLE Build component and complete-SSB required-SNR rows.
metrics=["JointSSMDR" "JointSSMDR" "PBCHComponentBLER" "PBCHComponentBLER"];
targets=[double(cfg.statistics.mdr_targets(:)); ...
    double(cfg.statistics.pbch_bler_targets(:))];
labels=["gamma_SS_10" "gamma_SS_1" "gamma_PBCH_10" "gamma_PBCH_1"];
rows=cell(6,1);
for k=1:4
    row=sixgr.phy.ia.c0.metrics.findTargetCrossing( ...
        points,metrics(k),targets(k));
    row.Label=labels(k);
    rows{k}=row;
end
rows{5}=localComplete(rows{1},rows{3},"gamma_SSB_10",0.10);
rows{6}=localComplete(rows{2},rows{4},"gamma_SSB_1",0.01);
crossings=struct2table(vertcat(rows{:}),"AsArray",true);
end

function row=localComplete(ss,pbch,label,target)
row=ss;
row.Metric="max_gamma_SS_gamma_PBCH";
row.Target=target;
row.Label=label;
row.Bracketed=ss.Bracketed&&pbch.Bracketed;
row.LowerSNRDB=NaN; row.UpperSNRDB=NaN;
row.LowerValue=NaN; row.UpperValue=NaN;
row.LowerErrors=NaN; row.LowerTrials=NaN;
row.UpperErrors=NaN; row.UpperTrials=NaN;
row.Interpolation="maximum_of_qualified_component_crossings";
if row.Bracketed
    row.CrossingSNRDB=max(ss.CrossingSNRDB,pbch.CrossingSNRDB);
    row.CrossingCILowDB=max(ss.CrossingCILowDB,pbch.CrossingCILowDB);
    row.CrossingCIHighDB=max(ss.CrossingCIHighDB,pbch.CrossingCIHighDB);
    row.Status="QUALIFIED_COMPONENT_MAXIMUM";
else
    row.CrossingSNRDB=NaN; row.CrossingCILowDB=NaN; row.CrossingCIHighDB=NaN;
    row.Status="BLOCKED_COMPONENT_CROSSING";
end
end
