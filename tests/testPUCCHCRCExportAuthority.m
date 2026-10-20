function ok=testPUCCHCRCExportAuthority()
% Execute the literal production reduction blocks. These are declared
% report-contract inputs, not new physical outcomes or statistical trials.
setup6GRSimToolkit('Verbose',false);
bundle=fileread(which('sixgr.truth.runWaveformLinkBundle'));
start=strfind(bundle,'function T = localCollectPUCCHTrials(');
assert(isscalar(start),'test:MissingCollector','Expected exactly one PUCCH collector.');
bundle=bundle(start:end);
next=regexp(bundle,'(?m)^function ','start');
bundle=bundle(1:next(2)-1);
collector=extractBlock(bundle,'        r.CRCOutcome = ', ...
    '        r.DetectionMetric = ');
crcAssignment=extractBlock(bundle,'        if logical(r.CRCApplicable)', ...
    '        r.DetectionMetric = ');
runtime=fileread(which('sixgr.truth.CoupledTruthRuntime'));
shared=extractBlock(runtime,'        crcApplicable = logical(sixgr.util.structGet(trial, "CRCApplicable", uciCrcBitCount > 0));', ...
    '        detectionOutcome = ');
for expected=[1 0 NaN]
    for overall=[false true]
        out=struct('CRCApplicable',true,'CRCPass',expected, ...
            'Ok',overall,'StrictOk',overall,'UCIContentMatch',overall);
        r=struct('CRCApplicable',true);
        % The collector's local variable is deliberately independent from
        % the recorded CRC. In particular, a CRC-passing wrong word is not
        % converted into a CRC failure by the separate TX comparison.
        ok=overall; %#ok<NASGU>
        eval(crcAssignment);
        assert(isequaln(r.CRCPass,expected), ...
            'test:PUCCHOverallStatusUsedAsCRC','Collector substituted overall outcome for received CRC.');
        eval(collector);
        wanted="unavailable";
        if expected==1, wanted="pass"; elseif expected==0, wanted="fail"; end
        assert(r.CRCOutcome==wanted, ...
            'test:PUCCHCRCOutcomeInferred','Collector inferred CRC outcome from overall success.');
        for usable=[false true]
            trial=out; crcApplicable=true; detectionUsable=usable; decodeOk=overall; %#ok<NASGU>
            uciCrcBitCount=6; %#ok<NASGU>
            eval(shared);
            assert(isequaln(crcPassValue,expected) && crcOutcome==wanted, ...
                'test:PUCCHRuntimeCRCInferred', ...
                'Runtime must retain recorded CRC independently of detection/DTX or HARQ/CSI completion.');
        end
    end
end
% No-CRC short UCI cannot acquire a CRC result from a successful decode.
out=struct('CRCApplicable',false,'CRCPass',1,'Ok',true);
r=struct('CRCApplicable',false); ok=true; %#ok<NASGU>
eval(collector);
assert(isnan(r.CRCPass) && r.CRCOutcome=="not_applicable");
trial=out; crcApplicable=false; detectionUsable=true; decodeOk=true; %#ok<NASGU>
eval(shared);
assert(isnan(crcPassValue) && crcOutcome=="not_applicable");
% An existing explicit producer outcome is preserved, not silently re-scored.
out=struct('CRCPass',NaN,'CRCOutcome',"unavailable_receiver_not_attempted");
r=struct('CRCApplicable',true); ok=false; %#ok<NASGU>
eval(collector);
assert(isnan(r.CRCPass) && r.CRCOutcome=="unavailable_receiver_not_attempted");
fprintf('PUCCH_CRC_EXPORT_AUTHORITY_PASS overall_status_not_crc=1\n');
ok=true;
end

function block=extractBlock(source,first,last)
a=strfind(source,first); b=strfind(source,last);
assert(isscalar(a),'test:AmbiguousProductionBlock','Expected exactly one reduction block.');
b=b(b>a); assert(~isempty(b),'test:MissingProductionBlock','Expected a reduction boundary.');
block=source(a:b(1)-1);
end
