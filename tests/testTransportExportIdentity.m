function ok=testTransportExportIdentity()
T=table([41;42;43],'VariableNames',{'Slot'});
T=sixgr.link.bindTransportExportIdentity(T,["tb_epoch1";"tb_epoch1";"tb_epoch2"], ...
    ["grant41";"grant42";"grant43"],0,[1;1;2]);
assert(T.LogicalTBID(1)==T.LogicalTBID(2) && T.LogicalTBID(3)~=T.LogicalTBID(2));
assert(numel(unique(T.TransmissionAttemptID))==3 && all(T.HARQProcess==0));
symbols=sixgr.link.bindTransportExportIdentity(table((1:8).','VariableNames',{'Sample'}), ...
    T.TBId(2),T.TransmissionAttemptID(2),T.HARQProcess(2),T.NDIEpoch(2));
assert(all(symbols.TBId==T.TBId(2)) && all(symbols.TransmissionAttemptID=="grant42"));
missing=sixgr.link.bindTransportExportIdentity(T,"","",0,NaN);
assert(all(missing.TBId=="") && all(missing.TransmissionAttemptID==""));
ok=true;
end
