function ok = testPDCCHEquivalentBlindHypothesisReduction()
%TESTPDCCHEQUIVALENTBLINDHYPOTHESISREDUCTION Verify oracle-free reduction.

setup6GRSimToolkit("Verbose", false);
bits = int8([1;0;1;1;0]);
h1 = struct("DCIBits", bits, "CandidateAggregationLevel", 16, ...
    "CandidateIndexWithinAggregation", 0, "CandidateFlatIndex", 23);
h2 = struct("DCIBits", bits, "CandidateAggregationLevel", 8, ...
    "CandidateIndexWithinAggregation", 1, "CandidateFlatIndex", 22);
[idx, classification] = sixgr.phy.pdcch.reduceBlindHypotheses({h1; h2});
assert(idx == 2 && classification == "equivalent", ...
    "Equivalent CRC-valid hypotheses must select the most specific candidate.");

h3 = h2;
h3.DCIBits(end) = 1;
[idx, classification] = sixgr.phy.pdcch.reduceBlindHypotheses({h1; h3});
assert(idx == 0 && classification == "ambiguous", ...
    "Different CRC-valid payloads must fail closed as ambiguous.");

[idx, classification] = sixgr.phy.pdcch.reduceBlindHypotheses({h1});
assert(idx == 1 && classification == "single", ...
    "A single CRC-valid hypothesis must be retained unchanged.");
ok = true;
end
