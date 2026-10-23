function ok=testCSVWriteReuse()
root=tempname; mkdir(root); path=fullfile(root,'live.csv'); mirror=fullfile(root,'mirror.csv');
scope=sixgr.util.CSVWriteReuse.scope(root); %#ok<NASGU>
T=table([NaN;Inf;-Inf;pi],["quoted,""value";"x"+newline+"y";"";missing], ...
    'VariableNames',{'Measured','Source'});
before=sixgr.util.CSVWriteReuse.statistics();
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'MirrorPaths',string(mirror));
hash=sixgr.util.sha256File(path);
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'MirrorPaths',string(mirror));
after=sixgr.util.CSVWriteReuse.statistics();
assert(after.ReusedWrites==before.ReusedWrites+1 && after.PublishedWrites==before.PublishedWrites+1);
assert(sixgr.util.sha256File(path)==hash && sixgr.util.sha256File(mirror)==hash);
% External modification or a deleted mirror is not proof of identical bytes.
sixgr.util.writeTextFile(path,'tampered');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'MirrorPaths',string(mirror));
assert(sixgr.util.sha256File(path)==hash);
delete(mirror);
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'MirrorPaths',string(mirror));
assert(isfile(mirror) && sixgr.util.sha256File(mirror)==hash);
T.Measured(4)=nextafterLocal(pi);
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'RoundTripNumericText',true);
assert(sixgr.util.sha256File(path)~=hash,'Changed precise values must be published.');
sixgr.util.csvWriteTable(path,T([],:),'PreserveSchema',true);
assert(height(readtable(path))==0,'Empty typed artifacts must not retain previous rows.');
ok=true; disp('CSV_WRITE_REUSE_PASS');
end
function x=nextafterLocal(x)
x=x+eps(x);
end
