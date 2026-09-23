function out=aggregateBitErrorEvidence(bitErrors,bitsCompared)
%AGGREGATEBITERROREVIDENCE Bit-weighted BER on paired receiver observations.
% No CRC-derived bit errors, independent omitnan sums, or zero-error fill.
arguments
    bitErrors {mustBeNumeric,mustBeReal}
    bitsCompared {mustBeNumeric,mustBeReal}
end
assert(isequal(size(bitErrors),size(bitsCompared)), ...
    'sixgr:kpi:BERObservationShapeMismatch', ...
    'BitErrors and BitsCompared must identify the same receiver rows.');
errors=double(bitErrors(:)); bits=double(bitsCompared(:));
observed=isfinite(errors) & isfinite(bits) & bits>0 & ...
    bits==fix(bits) & errors==fix(errors) & errors>=0 & errors<=bits;
totalErrors=sum(errors(observed)); totalBits=sum(bits(observed));
rate=NaN;
if totalBits>0, rate=totalErrors/totalBits; end
out=struct('BER',rate,'BitErrors',totalErrors,'BitsCompared',totalBits, ...
    'ObservedTrialCount',double(nnz(observed)), ...
    'UnavailableTrialCount',double(nnz(~observed)), ...
    'Complete',~isempty(observed) && all(observed));
end
