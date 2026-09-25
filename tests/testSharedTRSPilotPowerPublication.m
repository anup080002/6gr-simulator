function ok=testSharedTRSPilotPowerPublication(retainedRoot)
% Real 4TX/2RX -10 dB shared-channel component; not full scenario acceptance.
if nargin==0, root=diagnoseShared4Tx2RxTRS(); else, root=retainedRoot; end
x=load(fullfile(root,'received_trs.mat'),'out'); out=x.out;
assert(~out.Crash && out.TRSRuntimeEvidenceUsable && out.ChannelEstimateAvailable);
assert(isfinite(out.MeasuredTrialSINR_dB) && out.SignedPilotSINRLinear>0);
assert(abs(out.MeasuredTrialSINR_dB-10*log10(out.SignedPilotSINRLinear))<1e-12);
assert(out.MeasuredTrialSINRSource== ...
    "received_known_pilot_LS_projection_and_residual_degrees_of_freedom");
e=jsondecode(out.PilotPowerEvidenceJSON);
assert(~isempty(e));
assert(out.DesiredPilotPower>0 && out.ResidualPilotPower>0);
assert(all(isfinite(out.ChannelEstimationTable.PilotSINR_dB)));
% These are measured grid disturbance powers, not injected sample variance.
assert(out.SINRMeasurementDomain== ...
    "received_TRS_pilot_RE_equal_slot_branch_mean_signed_linear_SNR");
% The live collector preallocates localMakeLinkTrialRow before binding RX
% evidence. Its typed schema must include both fields even before reception.
% The real slot-9 failure was missed by testing the binder on struct() alone.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
template=extractBetween(string(source), ...
    'function row = localMakeLinkTrialRow(', 'function T = localEmptyLinkTrialTable(');
assert(isscalar(template) && contains(template,'row.SignedPilotSINRLinear = NaN;') && ...
    contains(template,'row.PilotPowerEvidenceJSON = "";'), ...
    'TRS measured fields must be declared in the runtime preallocation schema.');
prototype=sixgr.truth.bindReferenceSignalSINREvidence(struct(),struct(),"TRS");
rows=repmat(prototype,2,1);
rows(1)=sixgr.truth.bindReferenceSignalSINREvidence(prototype,out,"TRS");
assert(isnan(rows(2).SignedPilotSINRLinear) && rows(2).PilotPowerEvidenceJSON=="", ...
    'An unmeasured row must not inherit pilot evidence from another trial.');
row=rows(1);
assert(row.ReceiverHestSINRApplicable && ...
    sixgr.util.isAcceptableSINRStatus(out.MeasuredTrialSINRValueStatus), ...
    'Actual receiver SINR status must survive runtime/export applicability checks.');
assert(row.SignedPilotSINRLinear==out.SignedPilotSINRLinear && ...
    row.PilotPowerEvidenceJSON==out.PilotPowerEvidenceJSON);
temporaryCSV=[tempname '.csv']; cleanup=onCleanup(@()delete(temporaryCSV));
writetable(struct2table(row),temporaryCSV);
published=readtable(temporaryCSV,'TextType','string','VariableNamingRule','preserve', ...
    'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0);
assert(abs(published.SignedPilotSINRLinear-out.SignedPilotSINRLinear)<1e-12 && ...
    published.PilotPowerEvidenceJSON==out.PilotPowerEvidenceJSON);
if nargin==0
    writetable(out.ChannelEstimationTable,fullfile(root,'channel_measurements.csv'));
end
fprintf('SHARED_TRS_PILOT_POWER_PUBLICATION_PASS measured=%g desired=%g disturbance=%g folder=%s\n', ...
    out.MeasuredTrialSINR_dB,out.DesiredPilotPower,out.ResidualPilotPower,root);
ok=true;
end
