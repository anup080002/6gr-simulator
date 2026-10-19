function ok=testCSVBoundedRoundTrip()
% Chunk boundaries must not change bytes, precision, schema or atomicity.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root=string(tempname); mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
n=16401;
index=(1:n)';
values=sin(index)./index;
values(1:6)=[0;eps;realmin;realmax;NaN;Inf];
labels=repmat("literal,quoted ""text""",n,1);
labels(7)="line"+newline+"two";
T=table(index,values,single(cos(index)),uint64(index),mod(index,2)==0, ...
    labels,[values,-values],'VariableNames', ...
    {'SampleIndex','Value','SingleValue','Integer','Flag','Label','PerLayer'});
for roundTrip=[false true]
    path=fullfile(root,"bounded_"+roundTrip+".csv");
    expected=fullfile(root,"reference_"+roundTrip+".csv");
    wire=T;
    if roundTrip
        for name=string(T.Properties.VariableNames)
            if isfloat(T.(name)), wire.(name)=compose('%.17g',double(T.(name))); end
        end
    end
    writetable(wire,expected,'Delimiter',',','QuoteStrings',true);
    writer=sixgr.util.CSVTableStream(path,roundTrip);
    writer.append(T(1:8193,:)); writer.append(T(8194:end,:)); writer.finish();
    assert(writer.RowsWritten==n && writer.MaxSerializedRows<=8192, ...
        'sixgr:test:UnboundedCSVSerialization','No wire chunk may contain the entire population.');
    delete(writer);
    assert(sixgr.util.sha256File(path)==sixgr.util.sha256File(expected), ...
        'sixgr:test:CSVChunkChangedBytes','Chunked and original serialization must be byte-identical.');
    sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'RoundTripNumericText',roundTrip);
    assert(sixgr.util.sha256File(path)==sixgr.util.sha256File(expected));
end
stableHash=sixgr.util.sha256File(path);
writer=sixgr.util.CSVTableStream(path,true);
writer.append(T(1:10,:));
wrong=T(11:20,:); wrong.Properties.VariableNames{1}='WrongColumn';
localReject(@()writer.append(wrong),'sixgr:util:CSVTableStream:SchemaChanged');
delete(writer);
assert(sixgr.util.sha256File(path)==stableHash,'A partial write must not replace completed evidence.');
bad=T; bad.Value(end)=1i;
localReject(@()sixgr.util.csvWriteTable(path,bad,'PreserveSchema',true, ...
    'RoundTripNumericText',true),'sixgr:util:csvWriteTable:ComplexRoundTrip');
assert(sixgr.util.sha256File(path)==stableHash, ...
    'Late invalid evidence must not publish even after earlier chunks were written.');
files=dir(fullfile(root,'*.csv'));
assert(numel(files)==4,'Failed writes must remove only their private temporary CSV.');
ok=true;
fprintf('CSV_BOUNDED_ROUNDTRIP_PASS rows=%d maximum_wire_rows=8192\n',n);
end
function localReject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s',id,cause.identifier);
    return;
end
error('sixgr:test:ExpectedCSVRejection','Expected %s',id);
end
