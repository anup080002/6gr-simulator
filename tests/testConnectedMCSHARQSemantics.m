function ok=testConnectedMCSHARQSemantics()
% Independent modulation-only rows in 38.214 Tables 5.1.3.1-1/-2/-3.
tables=["qam64_table1","qam256_table2","qam64LowSE_table3"];
for name=tables
    root=struct('mcsTable',name,'transformPrecoding',false);
    first=29; qm=[2 4 6];
    if name=="qam256_table2", first=28; qm=[2 4 6 8]; end
    for index=0:31
        p=sixgr.phy.pdcch.resolveConnectedMCS(root,index);
        if index<first
            assert(p.Valid && ~p.RequiresHARQHistory && isfinite(p.TargetCodeRate));
        else
            assert(~p.Valid && p.RequiresHARQHistory && isnan(p.TargetCodeRate) && ...
                p.Qm==qm(index-first+1) && strlength(p.Modulation)>0);
        end
    end
end
root.transformPrecoding=true;
try
    sixgr.phy.pdcch.resolveConnectedMCS(root,31);
    error('test:MissingRejection','Transform-precoded table must not borrow CP table.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:phy:pdcch:ConnectedTransformMCSUnqualified'));
end
ok=true;
end
