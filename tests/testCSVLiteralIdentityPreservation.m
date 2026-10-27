function ok = testCSVLiteralIdentityPreservation()
% Received byte strings must survive the production publication readbacks.
root=string(tempname);
mkdir(fullfile(root,'control','csv'));
cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
path=fullfile(root,'control','csv','msg3_pusch_trials.csv');
payload=["0106000000000001310455452D31";"0106000000000002310455452D32";""];
identity=["000000000001";"000000000002";""];
msg4=["020000000000011234320001";"020000000000021235320001";""];
digest=[string(repmat('0',1,63))+"1";"0000000000000000000000000000000000000000000000000000000000000000E123";""];
bits=["00001101";string(repmat('01',1,128));""];
layers=["21";"20|22";""];
% The live producer decorates categories before CSV publication. Union-only
% BCH/CSI fields on a PRACH row and undecoded payloads have no literal bytes.
opaque=table(["";"0000E123"],["";"0011"],["";"000000000001"], ...
    'VariableNames',{'BCHTransportBlockHex','UCIDecodedBitVector','ReceivedIdentity'});
assert(isequaln(sixgr.truth.fillBlankCategoricalColumns(opaque,"prach"),opaque), ...
    'test:LiteralDisplayToken','Display decoration must preserve empty/available literal evidence.');
invalid=opaque; invalid.BCHTransportBlockHex(1)="not_valid_hex";
assert(isequaln(sixgr.truth.fillBlankCategoricalColumns(invalid,"prach"),invalid), ...
    'A decorator must not repair or erase malformed original evidence.');
T=table((1:3)',[4660;4661;4662],[3.25;4.5;NaN],payload,payload, ...
    identity,identity,msg4,digest,bits,layers, ...
    'VariableNames',{'UEId','RNTI','MeasuredSINR_dB','PayloadHex', ...
    'TransmittedPayloadHex','ContentionIdentity','ReceivedIdentity', ...
    'Msg4PayloadHex','ConfigHash','UCIDecodedBitVector','LayerSINRdB'});
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
literalNames=string(T.Properties.VariableNames(4:end));
for pass=0:2
    if pass>0
        sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',path);
        sixgr.report.annotateScenarioCSVArtifacts(root,'literal_fixture', ...
            'fixture_config_hash','waveform_bundle');
    end
    for args={{},{'TextType','string'}}
        callArgs=args{1};
        R=sixgr.util.csvReadTable(path,callArgs{:});
        for name=literalNames
            assert(isstring(R.(name)) && isequal( ...
                fillmissing(R.(name),'constant',""),T.(name)), ...
                'sixgr:test:CSVLiteralCorruption', ...
                'Publication changed literal receiver field %s.',name);
        end
        assert(isnumeric(R.RNTI) && isequal(R.RNTI,T.RNTI));
        assert(isnumeric(R.MeasuredSINR_dB) && ...
            isequaln(R.MeasuredSINR_dB,T.MeasuredSINR_dB));
    end
    if pass==1, first=fileread(path); end
    if pass==2, assert(strcmp(first,fileread(path)), ...
            'Repeated publication must be byte-idempotent.'); end
end
try
    sixgr.util.csvReadTable(path,'ColumnTypes',struct('PayloadHex','double'));
    error('test:ExpectedLiteralTypeRejection','Numeric payload schema was accepted.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:util:csvReadTable:LiteralTypeConflict'));
end
ok=true;
fprintf('CSV_LITERAL_IDENTITY_PRESERVATION_PASS\n');
end
