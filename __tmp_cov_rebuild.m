snap=readtable('C:/Anup/6gsimulation/sixgr_foundation_v2/results/__debug_coupled_cov/lls/lls_coupled_truth_smoke/smoke/reports/csv/live_coverage_snapshot.csv','VariableNamingRule','preserve');
perf=readtable('C:/Anup/6gsimulation/sixgr_foundation_v2/results/__debug_coupled_cov/lls/lls_coupled_truth_smoke/smoke/reports/csv/live_user_performance_snapshot.csv','VariableNamingRule','preserve');
T=snap;
T.UserThroughput_Mbps=nan(height(T),1);
T.HARQFailureRate=nan(height(T),1);
T.CellThroughput_Mbps=nan(height(T),1);
for i=1:height(T)
    ueIdx=double(T.UEID(i));
    mask=abs(double(perf.UEIndex)-ueIdx)<1e-9;
    if any(mask)
        idx=find(mask,1,'last');
        T.UserThroughput_Mbps(i)=double(perf.UserThroughput_Mbps(idx));
        T.HARQFailureRate(i)=double(perf.HARQFailureRate(idx));
    end
end
cells=unique(double(T.ServingCell),'stable');
for i=1:numel(cells)
    mask=abs(double(T.ServingCell)-cells(i))<1e-9;
    T.CellThroughput_Mbps(mask)=sum(double(T.UserThroughput_Mbps(mask)),'omitnan');
end
disp(height(T));
disp(T(:,{'UEID','UserThroughput_Mbps','HARQFailureRate','CellThroughput_Mbps'}));
