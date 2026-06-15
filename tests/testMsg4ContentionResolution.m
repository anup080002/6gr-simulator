function ok = testMsg4ContentionResolution()
res = raStrictAnchorSuccessResult();
assert(logical(res.Msg4PDCCHCrcPass), "UE must decode temp-C-RNTI PDCCH for MSG4.");
assert(logical(res.Msg4PDSCHCrcPass), "UE must decode MSG4 PDSCH/DL-SCH.");
assert(logical(res.ContentionIdentityMatches), "MSG4 contention identity must match MSG3 identity.");
assert(logical(res.RACompleted), "RA must complete only after contention resolution.");
ok = true;
end
