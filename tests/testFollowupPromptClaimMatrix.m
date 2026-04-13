function ok = testFollowupPromptClaimMatrix()
%TESTFOLLOWUPPROMPTCLAIMMATRIX Ensure the status matrix stays present.

setup6GRSimToolkit("Verbose", false);

repoRoot = fileparts(fileparts(mfilename("fullpath")));
claimFile = fullfile(repoRoot, "FOLLOWUP_PROMPT_CLAIM_MATRIX.md");
assert(exist(claimFile, "file") == 2, "Missing follow-up prompt claim matrix.");

txt = fileread(claimFile);
assert(contains(txt, "| 1 | `fixed` |"), "Claim matrix is missing item 1 fixed status.");
assert(contains(txt, "| 8 | `partially true` |"), "Claim matrix is missing item 8 partial status.");
assert(contains(txt, "| 10 | `fixed` |"), "Claim matrix is missing item 10 fixed status.");
assert(contains(txt, "Remaining active gap:"), "Claim matrix must document the remaining waveform-system gap honestly.");

ok = true;
end
