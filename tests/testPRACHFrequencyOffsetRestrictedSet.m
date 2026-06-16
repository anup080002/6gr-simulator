function ok = testPRACHFrequencyOffsetRestrictedSet()
%TESTPRACHFREQUENCYOFFSETRESTRICTEDSET Frequency-offset restricted-set evidence.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
freqT = b.Result.ArtifactTables.prach_frequency_offset_sweep;
assert(height(freqT) >= 6, "Frequency-offset sweep must cover offsets across unrestricted and restricted sets.");
assert(all(strcmpi(strtrim(string(freqT.Status)), "measured")), ...
    "Mini-anchor long-sequence frequency-offset rows must be measured, not unavailable.");
assert(all(ismember(["UnrestrictedSet","RestrictedSetTypeA","RestrictedSetTypeB"], unique(string(freqT.RestrictedSet)))), ...
    "Frequency-offset sweep must compare unrestricted, restricted set A, and restricted set B.");
assert(any(double(freqT.InjectedFrequencyOffsetHz) ~= 0), ...
    "Frequency-offset sweep must include a nonzero CFO point.");
assert(any(double(freqT.DetectionProbability) > 0), ...
    "Frequency-offset sweep must expose measured detection probability.");

ok = true;
end
