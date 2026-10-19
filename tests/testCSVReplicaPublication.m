function ok=testCSVReplicaPublication()
% Serialization/byte-copy fixture only, not PHY or statistical measurements.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root=string(tempname); mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU> owned temporary fixture
oldFlag=getenv('SIXGR_PERSISTENCE_ENABLED');
restoreFlag=onCleanup(@()setenv('SIXGR_PERSISTENCE_ENABLED',oldFlag)); %#ok<NASGU>
setenv('SIXGR_PERSISTENCE_ENABLED','true');
n=20001; sample=(1:n)'; value=sin(sample)./sample;
value(1:6)=[0;eps;realmin;realmax;NaN;Inf];
label=repmat("CSV fixture, not radio evidence",n,1);
label(7)="quoted ""text"""+newline+"second line";
T=table(sample,value,single(cos(sample)),uint64(sample),label, ...
    [value -value],'VariableNames',{'Sample','Value','Single','Integer','Label','PerLayer'});
primary=fullfile(root,'primary.csv');
replicas=[fullfile(root,'replica1.csv'),fullfile(root,'subfolder','replica2.csv')];
reference=fullfile(root,'reference.csv');
for roundTrip=[false true]
    sixgr.util.csvWriteTable(reference,T,'PreserveSchema',true,'RoundTripNumericText',roundTrip);
    % Profile the actual writer: mirrors must not trigger another append or
    % a second table-to-text conversion. No elapsed-time pass threshold.
    profile clear; profile on;
    sixgr.util.csvWriteTable(primary,T,'PreserveSchema',true, ...
        'RoundTripNumericText',roundTrip,'MirrorPaths',replicas);
    profile off; evidence=profile('info');
    names=string({evidence.FunctionTable.FunctionName});
    append=contains(names,'CSVTableStream') & endsWith(names,'append');
    assert(nnz(append)==1 && evidence.FunctionTable(append).NumCalls==1, ...
        'test:RepeatedCSVSerialization','All destinations must share one append.');
    copy=endsWith(names,'copyFileVerified');
    assert(nnz(copy)==1 && evidence.FunctionTable(copy).NumCalls==2);
    expected=sixgr.util.sha256File(reference);
    for path=[primary,replicas]
        assert(sixgr.util.sha256File(path)==expected);
        restored=sixgr.util.csvReadTable(path,'TextType','string');
        assert(height(restored)==n && restored.Sample(end)==n && restored.Label(7)==label(7));
    end
end
source=fileread(which('sixgr.util.CSVTableStream'));
assert(contains(source,'obj.registerArtifact(destination)') && ...
    contains(source,"'source_path',char(destination)") && ...
    contains(source,"'store_file',char(destination),char(destination)"), ...
    'Each replica must keep its own logical path and identical table metadata.');

% Late conversion failure and invalid destination lists preserve every
% previous primary/mirror file; no partially serialized alias is published.
stable=sixgr.util.sha256File(primary);
bad=T; bad.Value(end)=1i;
localReject(@()sixgr.util.csvWriteTable(primary,bad,'PreserveSchema',true, ...
    'RoundTripNumericText',true,'MirrorPaths',replicas), ...
    'sixgr:util:csvWriteTable:ComplexRoundTrip');
for invalid={primary,[replicas(1) replicas(1)],"",root}
    id='sixgr:util:CSVTableStream:DuplicateDestination';
    if isequal(invalid{1},"") || isequal(invalid{1},root), id='sixgr:util:CSVTableStream:BadMirrorPaths'; end
    localReject(@()sixgr.util.csvWriteTable(primary,T,'MirrorPaths',invalid{1}),id);
end
for path=[primary,replicas], assert(sixgr.util.sha256File(path)==stable); end
localReject(@()sixgr.util.copyFileVerified(primary,replicas(1),string(repmat('0',1,64))), ...
    'sixgr:util:VerifiedCopy:HashMismatch');
assert(sixgr.util.sha256File(replicas(1))==stable);
assert(isempty(dir(fullfile(root,'*.copy'))));
localReject(@()sixgr.util.copyFileVerified(primary,primary,stable), ...
    'sixgr:util:VerifiedCopy:InvalidTarget');
localReject(@()sixgr.util.copyFileVerified(primary,root,stable), ...
    'sixgr:util:VerifiedCopy:InvalidTarget');
localReject(@()sixgr.util.copyFileVerified(fullfile(root,'absent.csv'),replicas(1),stable), ...
    'sixgr:util:VerifiedCopy:MissingSource');

% A real filesystem link is not a second publication destination.
link=fullfile(root,'source_link.csv');
java.nio.file.Files.createLink(java.io.File(char(link)).toPath(),java.io.File(char(primary)).toPath());
localReject(@()sixgr.util.copyFileVerified(primary,link,stable), ...
    'sixgr:util:VerifiedCopy:InvalidTarget');
assert(sixgr.util.sha256File(primary)==stable);

% Global persistence-off is still a complete no-op, including mirrors.
setenv('SIXGR_PERSISTENCE_ENABLED','false');
sixgr.util.csvWriteTable(primary,T(1:2,:),'MirrorPaths',replicas);
for path=[primary,replicas], assert(sixgr.util.sha256File(path)==stable); end
setenv('SIXGR_PERSISTENCE_ENABLED','true');
sixgr.util.csvWriteTable(primary,T([],:),'PreserveSchema',true,'MirrorPaths',replicas);
for path=[primary,replicas]
    assert(sixgr.util.sha256File(path)==sixgr.util.sha256File(primary));
    restored=sixgr.util.csvReadTable(path);
    assert(height(restored)==0 && width(restored)>0);
end
ok=true;
fprintf('CSV_REPLICA_PUBLICATION_PASS rows=%d destinations=3 single_serialization=1 live_mysql_qualification=0\n',n);
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedCSVReplicaRejection','Expected %s.',id);
end
