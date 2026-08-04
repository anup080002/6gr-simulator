function ok = testStrictULLowSINRSuccessEvidence()
%TESTSTRICTULLOWSINRSUCCESSEVIDENCE Negative SINR success requires full truth.

setup6GRSimToolkit("Verbose", false);

row = table();
for name = [ ...
        "StrictReceiverEvidenceOk", "ReceiverUsable", "DecodeAttempted", ...
        "DecodeUsable", "ChannelEstimateAttempted", "ChannelEstimateAvailable", ...
        "ResourceExtractionAttempted", "ResourceExtractionAvailable", ...
        "EqualizationAttempted", "EqualizationAvailable", ...
        "ULSCHDecodeAttempted", "ULSCHDecodeAvailable", "LLRAvailable", ...
        "LLRFinite", "PostEqSINRAvailable", "PostEqSINRReceiverDerived"]
    row.(char(name)) = true;
end
row.FallbackFlag = false;
row.FallbackUsed = false;
row.PlaceholderFlag = false;
row.Crash = false;
row.TruthStatus = "real_lls_evidence";
row.SourceArtifact = "air_interface/csv/ul_pusch_trials.csv";
row.BitsCompared = 14856;
row.BitErrors = 0;
row.PostEqSINRValueStatus = "OK_dmrs_residual_bounded";

[accepted, reason] = sixgr.truth.hasStrictULReceiverDecoderEvidence(row);
assert(accepted, "Complete strict receiver evidence was rejected: %s", reason);

unbacked = row;
unbacked.LLRFinite = false;
[accepted, reason] = sixgr.truth.hasStrictULReceiverDecoderEvidence(unbacked);
assert(~accepted && contains(reason, "llrfinite"), ...
    "A row without finite LLR evidence must remain review-required.");

fallback = row;
fallback.FallbackUsed = true;
[accepted, reason] = sixgr.truth.hasStrictULReceiverDecoderEvidence(fallback);
assert(~accepted && contains(reason, "fallbackused"), ...
    "Fallback evidence must never close a low-SINR receiver review.");

ok = true;
end
