function ok = testFRCHARQTimeline()
%TESTFRCHARQTIMELINE Guard standards provenance and monotonic slot mapping.

catalog = sixgr.conformance.frcCatalog();
dl = localEntry(catalog.entries, "dl_r_pdsch_1_1_1_fdd_tdlb100_400");
ul = localEntry(catalog.entries, "ul_g_fr1_a3_8_tdlb100_400");

dlFirst = sixgr.conformance.buildFRCHARQTimeline(dl, 1, 4);
assert(isequal(double(dlFirst.AbsoluteSlotByAttempt(:).'), [1 5 9 13]), ...
    "DL HARQ attempts must use the configured four-process spacing.");
assert(dlFirst.ProcessCount == 4 && dlFirst.FeedbackDelaySlots == 2 && ...
    logical(dlFirst.ProcessCountSpecifiedByStandard) && ...
    logical(dlFirst.FeedbackDelaySpecifiedByStandard), ...
    "DL timing must preserve TS 38.101-4 Table 5.2.2.1.1-2 provenance.");

dlSecond = sixgr.conformance.buildFRCHARQTimeline(dl, 2, 4);
assert(all(diff(double(dlSecond.AbsoluteSlotByAttempt)) >= 4) && ...
    isempty(intersect(dlFirst.AbsoluteSlotByAttempt, ...
        dlSecond.AbsoluteSlotByAttempt)), ...
    "Independent DL TB clusters must use monotonic, disjoint slot identities.");
assert(any(double(dlSecond.AbsoluteSlotByAttempt) > 19), ...
    "DL carrier time must advance into later frames rather than wrap to frame zero.");

ulFirst = sixgr.conformance.buildFRCHARQTimeline(ul, 1, 4);
assert(isequal(double(ulFirst.AbsoluteSlotByAttempt(:).'), [0 4 8 12]), ...
    "The selected UL FDD harness must separate retransmissions by four slots.");
assert(~logical(ulFirst.ProcessCountSpecifiedByStandard) && ...
    ~logical(ulFirst.FeedbackDelaySpecifiedByStandard) && ...
    contains(ulFirst.RetransmissionSpacingSource, "assumption"), ...
    ["UL process count and feedback delay must remain explicitly labelled " ...
    "as harness assumptions, not TS 38.104 requirements."]);

didThrow = false;
try
    sixgr.conformance.buildFRCHARQTimeline(ul, 1, 5);
catch ME
    didThrow = strcmp(ME.identifier, ...
        "sixgr:conformance:HARQTimelineAttemptOverflow");
end
assert(didThrow, "HARQ timelines must reject attempts beyond the FRC maximum.");
ok = true;
end

function entry = localEntry(entries, id)
for index = 1:numel(entries)
    if iscell(entries), candidate = entries{index}; else, candidate = entries(index); end
    if string(candidate.id) == string(id)
        entry = candidate;
        return;
    end
end
error("sixgr:tests:MissingFRCEntry", "Missing FRC entry '%s'.", id);
end
