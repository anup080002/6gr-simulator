function ok = testLDPCParityEvidence()
% Complete native parity versus legacy partial diagnostic/reporting boundary.
% Declared matrices and one native encoded-LLR component; no waveform,
% feedback, HARQ success, BLER campaign or independent decoder qualification.
setup6GRSimToolkit('Verbose', false);
failures = strings(0,1);
caseCount = 0;
runCase('unequal_codeword_matrices', @unequalMatrices);
runCase('missing_codewords_never_zero_pass', @missingCodewords);
runCase('native_full_matrix', @nativeMatrix);
runCase('legacy_vector_unqualified', @legacyVector);
runCase('append_before_and_after_attachment', @attachmentOrder);
runCase('complete_and_partial_table_projection', @tableProjection);
runCase('CRC_and_bit_metrics_independent_from_parity', @codingMetrics);
runCase('malformed_matrices_and_stages', @malformedInputs);
runCase('contradictory_summary_rejected', @contradictorySummary);
assert(isempty(failures), 'test:LDPCParityEvidenceFailures', '%s', strjoin(failures,newline));
fprintf('LDPC_PARITY_EVIDENCE_PASS cases=%d complete_checks_by_CB_per_CW=1 waveform_qualification=0\n',caseCount);
ok = true;

    function runCase(name, callback)
        caseCount = caseCount + 1;
        try
            callback();
        catch err
            failures(end+1,1) = name + ": " + string(getReport(err,'extended','hyperlinks','off')); %#ok<AGROW>
            fprintf('LDPC_PARITY_CASE_FAIL %s %s\n',name,err.identifier);
        end
    end
end

function matrices = originalMatrices()
matrices = {int8([0 0; 1 0; 0 0]), logical([0; 0; 1; 1; 0])};
end

function unequalMatrices()
matrices = originalMatrices(); original = matrices;
s = sixgr.phy.phycode.summarizeLDPCParity(matrices,'initial_decode');
assert(isequal(matrices,original) && isequal(s.FinalParityChecksPerCodeword,original));
assert(s.Available && s.HasObservedCodewords && isequal(s.CodewordAvailable,[true true]));
assert(isequal(s.UnsatisfiedChecksPerCodeBlock,{[1 0],2}) && ...
    isequal(s.AllChecksPassPerCodeBlock,{[false true],false}));
assert(s.CheckCount==11 && s.UnsatisfiedCheckCount==3 && ...
    s.CodeBlockCount==3 && s.FailedCodeBlockCount==2);
assert(~any(matrices{1}(1,:)) && s.FailedCodeBlockCount>0);
combined = sixgr.phy.phycode.summarizeLDPCParity({zeros(3,2),zeros(5,1)},'harq_combined_decode');
assert(combined.UnsatisfiedCheckCount==0 && combined.FailedCodeBlockCount==0 && ...
    combined.Stage=="harq_combined_decode" && s.Stage=="initial_decode" && ...
    isequal(s.FinalParityChecksPerCodeword,original));
end

function missingCodewords()
for cells = {{}, {[]}, {[],[]}, {zeros(3,2),[]}}
    s = sixgr.phy.phycode.summarizeLDPCParity(cells{1},'initial_decode');
    assert(~s.Available && all(isnan([s.CheckCount,s.UnsatisfiedCheckCount, ...
        s.CodeBlockCount,s.FailedCodeBlockCount])));
    assert(s.HasObservedCodewords==any(s.CodewordAvailable));
end
s = sixgr.phy.phycode.summarizeLDPCParity({[],logical([0;1])},'initial_decode');
assert(isequal(s.CodewordAvailable,[false true]) && isempty(s.AllChecksPassPerCodeBlock{1}) && ...
    isequal(s.UnsatisfiedChecksPerCodeBlock{2},1) && ~s.AllChecksPassPerCodeBlock{2});
end

function nativeMatrix()
bits = int8(reshape(mod(0:639,2),320,2));
coded = nrLDPCEncode(bits,2);
[decoded,~,parity] = nrLDPCDecode(20*(1-2*double(coded)),2,4);
assert(isequal(decoded,bits) && size(parity,1)>1 && size(parity,2)==2);
s = sixgr.phy.phycode.summarizeLDPCParity({parity},'initial_decode');
assert(isequal(s.FinalParityChecksPerCodeword{1},parity) && ...
    s.CheckCount==numel(parity) && s.CodeBlockCount==2 && ...
    s.UnsatisfiedCheckCount==nnz(parity) && ...
    isequal(s.UnsatisfiedChecksPerCodeBlock{1},sum(double(parity),1)));
end

function legacyVector()
rx = append(struct(),[0 NaN Inf 1]);
assert(isnan(rx.MeasuredLDPCParityCheckFailures) && rx.MeasuredLDPCParityAvailable==0 && ...
    rx.MeasuredLDPCParityScope=="legacy_unqualified_partial_or_unknown" && ...
    rx.MeasuredLDPCParityCheckVector=="0|NaN|Inf|1");
rx = struct('ParityChecks',[0 0],'MeasuredLDPCParityCheckFailures',0);
e = sixgr.link.deriveMeasuredPHYEvidence(rx);
assert(isnan(e.MeasuredLDPCParityCheckFailures) && e.MeasuredLDPCParityAvailable==0 && ...
    e.MeasuredLDPCParityScope=="legacy_unqualified_partial_or_unknown");
e = sixgr.link.deriveMeasuredPHYEvidence(struct());
assert(isnan(e.MeasuredLDPCParityCheckFailures) && e.MeasuredLDPCParityAvailable==0 && ...
    e.MeasuredLDPCParityScope=="unavailable_no_complete_native_parity_evidence");
end

function attachmentOrder()
s = sixgr.phy.phycode.summarizeLDPCParity(originalMatrices(),'initial_decode');
before = append(struct('LDPCParityEvidence',s),[0 0 0]);
after = append(struct(),[0 0 0]); after.LDPCParityEvidence = s;
a = sixgr.link.deriveMeasuredPHYEvidence(before);
b = sixgr.link.deriveMeasuredPHYEvidence(after);
assert(isequaln(a,b) && a.MeasuredLDPCParityCheckFailures==3 && ...
    a.MeasuredLDPCParityAvailable==1);
assert(isequaln(sixgr.link.deriveMeasuredPHYEvidence(a),a), ...
    'Compact replay must preserve its original measured projection.');
assert(before.MeasuredCodeBlockCRCErrorCount==1 && before.MeasuredCodeBlockDecodeErrorCount==1);
end

function tableProjection()
s = sixgr.phy.phycode.summarizeLDPCParity(originalMatrices(),'initial_decode');
p = sixgr.phy.phycode.summarizeLDPCParity({zeros(3,2),[]},'initial_decode');
e = sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',s));
partial = sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',p));
T = sixgr.link.appendMeasuredPHYEvidenceColumns(table([1;2], ...
    'VariableNames',{'TrialId'}),{e;partial});
assert(T.MeasuredLDPCParityCheckFailures(1)==3 && isnan(T.MeasuredLDPCParityCheckFailures(2)) && ...
    isequal(T.MeasuredLDPCParityAvailable,[1;0]));
payload = jsondecode(T.MeasuredLDPCParityEvidenceJSON(1));
assert(payload.CheckCount==11 && payload.CodeBlockCount==3 && ...
    ~payload.CompatibilityVectorIsCompleteEvidence && ~payload.TransportBlockAcceptanceDetermined && ...
    ~isfield(payload,'FinalParityChecksPerCodeword'));
% Actual canonical projection: no PHY attempt or completion is manufactured.
cfg = sixgr.config.defaultConfig();
for direction = ["DL","UL"]
    projected = sixgr.truth.SharedDataCompletionRuntime.ensureLinkTrialTable(T,direction,0,cfg);
    names = string(T.Properties.VariableNames);
    names = names(startsWith(names,'MeasuredLDPCParity'));
    for name = names
        assert(isequaln(projected.(name),T.(name)), 'Projection changed %s.',name);
    end
end
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
path = fullfile(folder,'parity.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
roundtrip = readtable(path,'Delimiter',',','TextType','string','VariableNamingRule','preserve');
assert(isequal(string(roundtrip.MeasuredLDPCParityEvidenceJSON),T.MeasuredLDPCParityEvidenceJSON) && ...
    isequaln(roundtrip.MeasuredLDPCParityCheckFailures,T.MeasuredLDPCParityCheckFailures) && ...
    isequal(roundtrip.MeasuredLDPCParityAvailable,T.MeasuredLDPCParityAvailable));
end

function codingMetrics()
% Genuine native segmentation provides exact TX bits; only declared parity
% diagnostics are varied. They must not overwrite bit/CRC-derived CB metrics.
tx = struct('TransportBlockCRC',int8(mod((1:9000).',2)),'BaseGraph',1);
blocks = sixgr.phy.tb.segmentLDPC(tx.TransportBlockCRC,tx.BaseGraph);
assert(size(blocks,2)>1);
rx = struct('DecodedCodeBlocks',blocks,'ParityChecks',ones(1,size(blocks,2)));
m = sixgr.link.deriveCodingTrialMetrics(tx,struct(),rx,struct());
assert(m.CodeBlockErrors==0 && m.CodeBlockCount==size(blocks,2));
rx.ParityChecks(:) = 0; rx.DecodedCodeBlocks(1,1) = 1-rx.DecodedCodeBlocks(1,1);
m = sixgr.link.deriveCodingTrialMetrics(tx,struct(),rx,struct());
assert(m.CodeBlockErrors==1);
rx.DecodedCodeBlocks = blocks; rx.CodeBlockCRCError = [1 zeros(1,size(blocks,2)-1)];
m = sixgr.link.deriveCodingTrialMetrics(tx,struct(),rx,struct());
assert(m.CodeBlockErrors==1);
tx.TransportBlock = int8(mod((1:96).',2));
tx.TransportBlockCRC = nrCRCEncode(tx.TransportBlock,'16');
rx = struct('DecodedCodeBlocks',sixgr.phy.tb.segmentLDPC(tx.TransportBlockCRC,1), ...
    'TransportBlock',tx.TransportBlock,'CRCPass',false,'ParityChecks',0);
m = sixgr.link.deriveCodingTrialMetrics(tx,struct(),rx,struct());
assert(m.CodeBlockCount==1 && m.CodeBlockErrors==1);
end

function malformedInputs()
for raw = {0,struct(),{struct()},{""},{[0 2]}, {NaN}, {Inf}, ...
        {complex(0,1)}, {zeros(2,2,2)}, {sparse(2,2)}, cell(2,2)}
    reject(@() sixgr.phy.phycode.summarizeLDPCParity(raw{1},'initial_decode'), ...
        ["sixgr:phy:ldpc:ParityCodewordCells","sixgr:phy:ldpc:ParityMatrix"]);
end
for stage = {"",string(missing),["initial_decode","harq_combined_decode"],"arbitrary",1}
    reject(@() sixgr.phy.phycode.summarizeLDPCParity({0},stage{1}),"sixgr:phy:ldpc:ParityStage");
end
end

function contradictorySummary()
s = sixgr.phy.phycode.summarizeLDPCParity(originalMatrices(),'initial_decode');
for field = ["CheckCount","UnsatisfiedCheckCount","CodeBlockCount","FailedCodeBlockCount"]
    bad = s; bad.(field) = 0;
    reject(@()sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',bad)), ...
        "sixgr:link:InvalidLDPCParityEvidence");
end
bad = s; bad.ContractVersion = "unqualified";
reject(@()sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',bad)), ...
    "sixgr:link:InvalidLDPCParityEvidence");
bad = rmfield(s,'CodewordAvailable');
reject(@()sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',bad)), ...
    "sixgr:link:InvalidLDPCParityEvidence");
compact = sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',s));
bad = compact; bad.MeasuredLDPCParityCheckFailures = 0;
reject(@()sixgr.link.deriveMeasuredPHYEvidence(bad),"sixgr:link:InvalidLDPCParityEvidence");
bad = rmfield(compact,'MeasuredLDPCParityEvidenceJSON');
reject(@()sixgr.link.deriveMeasuredPHYEvidence(bad),"sixgr:link:InvalidLDPCParityEvidence");
end

function rx = append(rx,parity)
carrier = struct('NSizeGrid',1,'SymbolsPerSlot',14);
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx,carrier,[],[],[],struct(), ...
    [],[],[],struct(),[2 3 4],parity,[0 1 0],'Normalized min-sum',false,0);
end

function reject(callback, identifiers)
try
    callback();
catch err
    assert(any(string(err.identifier)==identifiers),'Unexpected rejection: %s',err.message);
    return;
end
error('test:LDPCParityMissingRejection','Malformed parity evidence was accepted.');
end
