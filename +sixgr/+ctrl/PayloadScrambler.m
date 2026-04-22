function out = PayloadScrambler(inBits, ctrlCfg, context)
%PayloadScrambler Scramble control coded bits before modulation.
%
% This is an explicit study baseline, not a claim of frozen 6GR scrambling.

if nargin < 3 || isempty(context)
    context = struct();
end

inBits = int8(inBits(:) ~= 0);
if ~logical(ctrlCfg.PayloadScramblingEnabled)
    out = struct("Bits", inBits, "Sequence", int8(zeros(size(inBits))), ...
        "Enabled", false, "SequenceInit", double(ctrlCfg.PayloadSequenceInit));
    return;
end

cinit = uint32(mod(double(ctrlCfg.PayloadSequenceInit) + ...
    17 * double(sixgr.util.structGet(context, "SlotNumber", ctrlCfg.SlotNumber)) + ...
    31 * double(sixgr.util.structGet(context, "SearchSpaceID", 0)) + ...
    13 * double(ctrlCfg.RNTI), 2^31 - 1));

seq = localPRBS(cinit, numel(inBits));
outBits = bitxor(inBits, int8(seq(:)));
out = struct();
out.Bits = int8(outBits(:));
out.Sequence = int8(seq(:));
out.Enabled = true;
out.SequenceInit = double(cinit);
end

function seq = localPRBS(cinit, N)
state = false(31,1);
for i = 1:31
    state(i) = bitget(uint32(cinit), i) ~= 0;
end
if ~any(state)
    state(1) = true;
end
seq = false(N,1);
for n = 1:N
    newBit = xor(state(31), state(28));
    seq(n) = state(end);
    state(2:end) = state(1:end-1);
    state(1) = newBit;
end
end
