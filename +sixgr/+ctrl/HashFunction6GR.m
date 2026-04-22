function [hashValue, trace] = HashFunction6GR(mode, ctrlCfg, searchSpace, slotNumber, aggregationLevel, candidateIndex)
%HashFunction6GR Deterministic candidate hash for the 6GR PDCCH study.

mode = lower(string(mode));
rnti = uint64(round(double(ctrlCfg.RNTI)));
ssId = uint64(round(double(searchSpace.SearchSpaceID)));
slotVal = uint64(round(double(slotNumber)));
cellId = uint64(round(double(ctrlCfg.CellID)));
al = uint64(round(double(aggregationLevel)));
cand = uint64(round(double(candidateIndex)));

base = rnti * 1103515245 + ssId * 12345 + slotVal * 69069 + cellId * 362437 + al * 97 + cand * 193;
switch mode
    case "baseline_hash"
        hashValue = double(bitand(base, uint64(2^31 - 1)));
    case "alt_hash1"
        mixed = bitxor(base, bitshift(base, -13));
        mixed = mixed + uint64(0x9E3779B97F4A7C15);
        hashValue = double(bitand(mixed, uint64(2^31 - 1)));
    case "alt_hash2"
        mixed = base * uint64(2654435761);
        mixed = bitxor(mixed, bitshift(mixed, -17));
        hashValue = double(bitand(mixed, uint64(2^31 - 1)));
    otherwise
        error("sixgr:ctrl:HashFunction6GR:BadMode", ...
            "Unsupported hash mode '%s'.", mode);
end

trace = struct();
trace.Mode = char(mode);
trace.RNTI = double(rnti);
trace.SearchSpaceID = double(ssId);
trace.SlotNumber = double(slotVal);
trace.CellID = double(cellId);
trace.AggregationLevel = double(al);
trace.CandidateIndex = double(cand);
trace.HashValue = double(hashValue);
end
