function ok = testPDCCHCandidateBlindSearch()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
C = b.Result.ArtifactTables.pdcch_candidates;
assert(height(C) > 0, "Candidate-level PDCCH evidence must be exported.");
assert(numel(unique(double(C.CandidateIndex))) >= 1, "Candidate table must expose candidate indices.");
assert(any(logical(C.SelectedCandidate)), "At least one candidate must be selected by blind decode.");
assert(any(~logical(C.CrcPass)), "Candidate table must include rejected candidates, not only winners.");
ok = true;
end
