function ok = testLLSRawTrialLifecycleTruth()
%TESTLLSRAWTRIALLIFECYCLETRUTH Keep row lifecycle tied to primary raw-truth fields.

setup6GRSimToolkit("Verbose", false);

[dlT, ulT] = localBuildFocusedTrialTables();
localAssertLifecycleTruth(dlT, "DL");
localAssertLifecycleTruth(ulT, "UL");

ok = true;
end

function [dlT, ulT] = localBuildFocusedTrialTables()
% Reuse actual DL/UL decoding with canonical timing, exact feasibility and
% frozen grants. Do not duplicate an obsolete hand-written scheduler grant.
% Control binding in this fixture is explicitly unit-test supplied, not a
% qualification of physical PDCCH reception.
% Preserve this lifecycle test's original absolute-power/thermal-noise
% operating point; the other provenance test defaults to fixed-reference
% AWGN and does not require a CRC pass at that different physical point.
[passed,raw]=testLLSRawTrialProvenance("receiver_noise_figure_thermal_noise");
assert(passed);
for direction=["DL","UL"]
    T=raw.(direction);
    % Deliberately omit only an auxiliary preview, never decoded evidence.
    % This negative lifecycle case must not erase real CRC/TBS/throughput.
    T.LargeScaleSINR_dB(:)=NaN;
    T.LargeScaleSINRSource(:)="explicit_unit_fixture_missing_preview";
    raw.(direction)=sixgr.util.applyLLSRawTrialLifecycle(T);
    assert(isequaln(raw.(direction).CRCPass,T.CRCPass) && ...
        isequaln(raw.(direction).BitsCompared,T.BitsCompared) && ...
        isequaln(raw.(direction).Goodput_Mbps,T.Goodput_Mbps));
end
dlT=raw.DL; ulT=raw.UL;
end

function localAssertLifecycleTruth(T, direction)
assert(istable(T) && height(T) == 1, ...
    "Expected a single focused %s raw trial row.", direction);
requiredVars = { ...
    'CRCPass','BitsCompared','Goodput_Mbps','MCSIndex','Modulation','TargetCodeRate', ...
    'PrimaryTruthValueStatus','SecondaryFieldGapFlag','SecondaryFieldGapCount','SecondaryFieldGapReason', ...
    'LargeScaleSINRValueStatus','LargeScaleSINRFinalizedFlag','LargeScaleSINRNAReason', ...
    'RowLifecycleState','PartialRowFlag','FinalizedFlag','NAReason'};
assert(all(ismember(requiredVars, T.Properties.VariableNames)), ...
    "Raw %s trial table must expose lifecycle truth columns.", direction);
assert(logical(T.CRCPass(1)) && isfinite(double(T.BitsCompared(1))) && isfinite(double(T.Goodput_Mbps(1))), ...
    "Focused %s raw trial row must contain real decode outcome fields.", direction);
assert(strcmpi(string(T.PrimaryTruthValueStatus(1)), "OK"), ...
    "Focused %s raw trial row must classify primary runtime truth as OK.", direction);
assert(logical(T.FinalizedFlag(1)) && ~logical(T.PartialRowFlag(1)) && strcmpi(string(T.RowLifecycleState(1)), "finalized"), ...
    "Focused %s raw trial row must finalize when primary truth fields are present.", direction);
assert(strlength(string(T.NAReason(1))) == 0, ...
    "Focused %s finalized raw trial row must not carry a row-level NA reason.", direction);
assert(logical(T.SecondaryFieldGapFlag(1)) && double(T.SecondaryFieldGapCount(1)) >= 1, ...
    "Focused %s raw trial row must preserve secondary gap tracking separately from row finalization.", direction);
assert(contains(string(T.SecondaryFieldGapReason(1)), "large_scale_sinr_not_finalized"), ...
    "Focused %s raw trial row must disclose unresolved preview SINR as a secondary gap.", direction);
assert(strcmpi(string(T.LargeScaleSINRValueStatus(1)), "NOT_AVAILABLE") && ...
    ~logical(T.LargeScaleSINRFinalizedFlag(1)) && ...
    strcmpi(string(T.LargeScaleSINRNAReason(1)), "preview_source_present_value_not_finalized"), ...
    "Focused %s raw trial row must keep large-scale SINR in field-level NOT_AVAILABLE state without downgrading the whole row.", direction);
end
