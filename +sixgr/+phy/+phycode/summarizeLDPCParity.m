function evidence = summarizeLDPCParity(parityCells, stage)
%SUMMARIZELDPCPARITY Summarize complete native checks-by-CB matrices per CW.
% The caller must retain the complete final native parity output for each
% codeword. A vector containing only one check per CB is not this contract.
% An empty entry means missing/unattempted, never an observed all-pass result.
% This is a syndrome diagnostic; it does not replace CB-CRC or TB-CRC.

assert(iscell(parityCells) && (isempty(parityCells) || isvector(parityCells)), ...
    'sixgr:phy:ldpc:ParityCodewordCells', ...
    'Parity evidence must be a cell vector with one complete matrix per codeword.');
assert((ischar(stage) && isrow(stage)) || (isstring(stage) && isscalar(stage)), ...
    'sixgr:phy:ldpc:ParityStage', 'Parity stage must be scalar text.');
stage = string(stage);
assert(~ismissing(stage) && any(stage == ["initial_decode", "harq_combined_decode"]), ...
    'sixgr:phy:ldpc:ParityStage', ...
    'Parity stage must identify initial_decode or harq_combined_decode.');

parityCells = reshape(parityCells, 1, []);
count = numel(parityCells);
available = false(1, count);
unsatisfied = cell(1, count);
passed = cell(1, count);
checkCount = 0;
unsatisfiedCount = 0;
codeBlockCount = 0;
failedBlockCount = 0;
for cw = 1:count
    matrix = parityCells{cw};
    assert((isnumeric(matrix) || islogical(matrix)) && isreal(matrix) && ...
        ismatrix(matrix) && ~issparse(matrix), ...
        'sixgr:phy:ldpc:ParityMatrix', ...
        'Each codeword must contain a real full numeric/logical checks-by-CB matrix.');
    if isempty(matrix)
        unsatisfied{cw} = [];
        passed{cw} = [];
        continue;
    end
    assert(all(isfinite(matrix(:))) && all(matrix(:) == 0 | matrix(:) == 1), ...
        'sixgr:phy:ldpc:ParityMatrix', 'Final parity checks must be finite binary values.');
    available(cw) = true;
    unsatisfied{cw} = sum(double(matrix), 1);
    passed{cw} = all(matrix == 0, 1);
    checkCount = checkCount + numel(matrix);
    unsatisfiedCount = unsatisfiedCount + sum(unsatisfied{cw});
    codeBlockCount = codeBlockCount + size(matrix, 2);
    failedBlockCount = failedBlockCount + nnz(~passed{cw});
end

evidence = struct();
evidence.ContractVersion = "sixgr.phy.LDPCParitySummary/v1";
evidence.Stage = stage;
evidence.FinalParityChecksPerCodeword = parityCells;
evidence.CodewordAvailable = available;
evidence.UnsatisfiedChecksPerCodeBlock = unsatisfied;
evidence.AllChecksPassPerCodeBlock = passed;
evidence.Available = count > 0 && all(available);
evidence.HasObservedCodewords = any(available);
% Whole-population totals require every expected codeword. Observed cells
% above remain usable when another codeword is missing/unattempted.
if ~evidence.Available
    checkCount = NaN;
    unsatisfiedCount = NaN;
    codeBlockCount = NaN;
    failedBlockCount = NaN;
end
evidence.CheckCount = double(checkCount);
evidence.UnsatisfiedCheckCount = double(unsatisfiedCount);
evidence.CodeBlockCount = double(codeBlockCount);
evidence.FailedCodeBlockCount = double(failedBlockCount);
end
