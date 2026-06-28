function ok = harqControlAcceptance()
%HARQCONTROLACCEPTANCE Position-aware HARQ and Msg1-4 access anchors.

layout = struct( ...
    "CodingLayoutHash", "release_layout_hash", ...
    "CombineSignature", "release_layout_hash", ...
    "RateMatchSignature", "rv0_release_map", ...
    "RateMatchPositionMap", struct("MotherCodeLinearIndex", uint32([1; 3; 5])));
current = [1; 0; 2; 0; 3];
prior = [4; 0; 5; 0; 6];
[~, firstInfo] = sixgr.phy.harq.combineSoftLLR(prior, [], "CurrentLayout", layout);
[combined, info] = sixgr.phy.harq.combineSoftLLR(current, firstInfo.SoftBuffer, "CurrentLayout", layout);
assert(logical(info.Applied) && logical(info.PositionAware), ...
    "HARQ soft combining must use the canonical position-aware soft buffer.");
assert(isequal(combined(:).', [5 0 7 0 9]), ...
    "HARQ combined LLRs must sum exact mother-code positions only.");
assert(double(info.OverlapPositionCount) == 3, ...
    "HARQ overlap count must equal exact intersecting mother-code positions.");

bad = layout;
bad.CodingLayoutHash = "different_release_layout";
[badOut, badInfo] = sixgr.phy.harq.combineSoftLLR(current, firstInfo.SoftBuffer, "CurrentLayout", bad);
assert(~logical(badInfo.Applied) && isequal(badOut, current), ...
    "Same-shape but different coding layout must reject/reset instead of adding.");

raOk = testFourStepRASuccessAWGN();
assert(logical(raOk), "Release control/access anchor must complete Msg1-Msg4 RA AWGN flow.");
ok = true;
end
