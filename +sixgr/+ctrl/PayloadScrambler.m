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

nID = localResolvePDCCHScramblingID(ctrlCfg, context);
nID = mod(nID, 65536);
rnti = mod(round(double(ctrlCfg.RNTI)), 65536);
cinit = uint32(mod(double(rnti) * 2^16 + double(nID), 2^31));

seq = sixgr.ctrl.GoldSequence(numel(inBits), cinit);
outBits = bitxor(inBits, int8(seq(:)));
out = struct();
out.Bits = int8(outBits(:));
out.Sequence = int8(seq(:));
out.Enabled = true;
out.SequenceInit = double(cinit);
end

function nID = localResolvePDCCHScramblingID(ctrlCfg, context)
if nargin >= 2 && isstruct(context)
    nID = sixgr.util.structGet(context, "PDCCHScramblingID", []);
    if isempty(nID)
        nID = sixgr.util.structGet(context, "CORESETScramblingID", []);
    end
    if ~isempty(nID)
        nID = round(double(nID));
        return;
    end
end
nID = round(double(sixgr.util.structGet(ctrlCfg, "PDCCHScramblingID", ...
    sixgr.util.structGet(ctrlCfg, "CORESETScramblingID", ...
    sixgr.util.structGet(ctrlCfg, "DataScramblingIdentityPDCCH", ...
    sixgr.util.structGet(ctrlCfg, "PayloadSequenceInit", ctrlCfg.CellID))))));
end
