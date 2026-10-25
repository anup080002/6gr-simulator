function evidence = summarizeLDPCParity(parityCells, stage, contractVersion)
%SUMMARIZELDPCPARITY Summarize complete native checks-by-CB matrices per CW.
% The caller must retain the complete final native parity output for each
% codeword. A vector containing only one check per CB is not this contract.
% An empty entry means missing/unattempted, never an observed all-pass result.
% This is a syndrome diagnostic; it does not replace CB-CRC or TB-CRC.
% V2 preserves the actual decoder stage for each observed codeword. Scalar
% stage input explicitly declares a homogeneous population. The optional V1
% mode is solely for validating retained legacy aggregate-only receipts; it
% does not reconstruct per-codeword history that those receipts did not keep.

if nargin < 3, contractVersion = "sixgr.phy.LDPCParitySummary/v2"; end
assert((ischar(contractVersion) && isrow(contractVersion)) || ...
    (isstring(contractVersion) && isscalar(contractVersion)), ...
    'sixgr:phy:ldpc:ParityContract', 'Parity contract must be scalar text.');
contractVersion = string(contractVersion);
assert(~ismissing(contractVersion) && any(contractVersion == ...
    ["sixgr.phy.LDPCParitySummary/v1","sixgr.phy.LDPCParitySummary/v2"]), ...
    'sixgr:phy:ldpc:ParityContract', 'Unsupported parity contract.');

assert(iscell(parityCells) && (isempty(parityCells) || isvector(parityCells)), ...
    'sixgr:phy:ldpc:ParityCodewordCells', ...
    'Parity evidence must be a cell vector with one complete matrix per codeword.');
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

[stage,codewordStages] = localStages(stage,available,contractVersion);
evidence = struct();
evidence.ContractVersion = contractVersion;
evidence.Stage = stage;
if contractVersion == "sixgr.phy.LDPCParitySummary/v2"
    evidence.CodewordStages = codewordStages;
end
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

function [aggregate,stages] = localStages(raw,available,version)
id = 'sixgr:phy:ldpc:ParityStage';
assert((ischar(raw) && isrow(raw)) || ...
    (isstring(raw) && (isvector(raw) || isempty(raw))),id, ...
    'Supply scalar stage text or an ordered string vector per codeword.');
stages = reshape(string(raw),1,[]);
allowed = ["initial_decode","harq_combined_decode"];
assert(~any(ismissing(stages)),id,'Decoder stages cannot be missing.');
if version == "sixgr.phy.LDPCParitySummary/v1"
    assert(isscalar(stages) && any(stages==allowed),id, ...
        'Legacy V1 retains only its original initial/combined aggregate stage.');
    aggregate = stages;
    stages = strings(1,0); % Never invent a legacy per-codeword population.
    return;
end
if isscalar(stages) && any(stages==allowed)
    stages = repmat(stages,1,numel(available));
    stages(~available) = "";
else
    assert(numel(stages)==numel(available),id, ...
        'Stage count must match the original codeword population.');
end
assert(all(ismember(stages(available),allowed)) && all(stages(~available)==""), ...
    id,'Observed codewords need actual decoder stages; unobserved codewords need empty stages.');
observed = stages(available);
if isempty(observed)
    aggregate = "";
elseif all(observed==observed(1))
    aggregate = observed(1);
else
    aggregate = "mixed_codeword_decode";
end
end
