function ok = testUCIBitVectorCSVPreservation()
% Literal receiver bit evidence survives readback and repeated recovery.
setup6GRSimToolkit('Verbose',false);
root=string(tempname);
mkdir(fullfile(root,'air_interface','csv'));
cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
path=fullfile(root,'air_interface','csv','pucch_trials.csv');
expected=["0000111011";string(repmat('01',1,128));"";"0000000000"];
decoded=["0000111010";string(repmat('01',1,128));"";"0000000000"];
errors=["0000000001";string(repmat('0',1,256));"";"0000000000"];
T=table([34;39;44;49],expected,decoded,errors,[10;256;NaN;10],[3.25;4.5;NaN;-2], ...
    'VariableNames',{'Slot','UCIExpectedBitVector','UCIDecodedBitVector', ...
    'UCIBitErrorVector','UCIBitCount','MeasuredSINR_dB'});
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
for pass=0:2
    if pass>0
        sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',path);
    end
    for args={{},{'TextType','string'}}
        callArgs=args{1};
        readback=sixgr.util.csvReadTable(path,callArgs{:});
        assert(isequal(fillmissing(string(readback.UCIExpectedBitVector),'constant',""),expected), ...
            'CSV read/recovery changed expected UCI bits or their leading zeroes.');
        assert(isequal(fillmissing(string(readback.UCIDecodedBitVector),'constant',""),decoded));
        assert(isequal(fillmissing(string(readback.UCIBitErrorVector),'constant',""),errors));
        assert(isnumeric(readback.MeasuredSINR_dB) && ...
            isequaln(readback.MeasuredSINR_dB,T.MeasuredSINR_dB), ...
            'Preserving bit strings must not change numeric measurement semantics.');
    end
    if pass==1, first=fileread(path); end
    if pass==2
        assert(strcmp(first,fileread(path)), ...
            'Repeated canonical CSV finalization must be byte-idempotent.');
    end
end
ok=true;
fprintf('PASS testUCIBitVectorCSVPreservation: leading zeroes, long vectors, missing and numeric cells.\n');
end
