function ok=testSharedTRSPilotPowerPublication(retainedNativeRoot,retainedFlatRoot)
% Actual native and explicitly static-AWGN publication components.
% Neither arm is full scenario acceptance or fading SINR qualification.
if nargin<1 || strlength(string(retainedNativeRoot))==0
    retainedNativeRoot=diagnoseShared4Tx2RxTRS();
end
nativePath=fullfile(retainedNativeRoot,'received_trs.mat');
nativeHash=sixgr.util.sha256File(nativePath);
native=load(nativePath,'out','p');
assert(string(native.p.StrictConfig.RuntimeChannelEstimator)=="nr_channel_estimate", ...
    'The native publication arm must retain its configured per-resource estimator.');
assert(~native.out.Crash && native.out.TRSRuntimeEvidenceUsable && ...
    native.out.ChannelEstimateAvailable);
assert(isnan(native.out.MeasuredTrialSINR_dB) && ...
    isnan(native.out.SignedPilotSINRLinear) && ...
    isnan(native.out.DesiredPilotPower) && isnan(native.out.ResidualPilotPower));
assert(native.out.MeasuredTrialSINRSource=="unavailable_pilot_fit_is_not_independent_SINR" && ...
    native.out.MeasuredTrialSINRNAReason==native.out.MeasuredTrialSINRSource && ...
    all(isnan(native.out.ChannelEstimationTable.PilotSINR_dB)), ...
    'Native channel fitting must not be promoted to an independent pilot SINR.');
localVerifyPublication(native.out,false);
assert(sixgr.util.sha256File(nativePath)==nativeHash);

% Retain the finite-pilot publication test on a real eligible positive arm.
% Declare its static operator before transmission; never relabel the native
% piecewise-operator capture or silently switch that production scenario.
if nargin<2 || strlength(string(retainedFlatRoot))==0
    retainedFlatRoot=diagnoseShared4Tx2RxTRS(fullfile('simulator','configs', ...
        'scenarios','lls_trs_static_awgn_pilot_publication_fixture.yaml'));
end
flatPath=fullfile(retainedFlatRoot,'received_trs.mat');
flatHash=sixgr.util.sha256File(flatPath);
flat=load(flatPath,'out','p'); out=flat.out;
assert(string(flat.p.StrictConfig.RuntimeChannelEstimator)=="flat_static_awgn_ls" && ...
    strcmpi(string(flat.p.StrictConfig.ChannelModel),'AWGN') && ...
    ~logical(flat.p.ReceiverConfig.channel.awgnBeamFailureRecoveryEnabled), ...
    'Finite flat-LS pilot power requires the explicitly static AWGN fixture.');
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
localVerifyPublication(out,true);
assert(sixgr.util.sha256File(flatPath)==flatHash);
fprintf(['SHARED_TRS_PILOT_POWER_PUBLICATION_PASS native_unavailable_retained=1 ' ...
    'static_measured=%g desired=%g disturbance=%g native=%s static=%s\n'], ...
    out.MeasuredTrialSINR_dB,out.DesiredPilotPower,out.ResidualPilotPower, ...
    retainedNativeRoot,retainedFlatRoot);
ok=true;
end

function localVerifyPublication(out,finitePilotExpected)
% The live collector preallocates localMakeLinkTrialRow before binding RX
% evidence. Its typed schema must include both fields even before reception.
% The real slot-9 failure was missed by testing the binder on struct() alone.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
template=fileread(which('sixgr.truth.makeLinkTrialRow'));
assert(contains(source,'[varargout{1:nargout}] = sixgr.truth.makeLinkTrialRow(varargin{:});') && ...
    ~contains(source,'row.SignedPilotSINRLinear = NaN;'), ...
    'The live collector must use the single complete trial-row schema owner.');
assert(contains(template,'row.SignedPilotSINRLinear = NaN;') && ...
    contains(template,'row.PilotPowerEvidenceJSON = "";'), ...
    'TRS measured fields must be declared in the runtime preallocation schema.');
prototype=sixgr.truth.bindReferenceSignalSINREvidence(struct(),struct(),"TRS");
rows=repmat(prototype,2,1);
rows(1)=sixgr.truth.bindReferenceSignalSINREvidence(prototype,out,"TRS");
assert(isnan(rows(2).SignedPilotSINRLinear) && rows(2).PilotPowerEvidenceJSON=="", ...
    'An unmeasured row must not inherit pilot evidence from another trial.');
row=rows(1);
if finitePilotExpected
    assert(row.ReceiverHestSINRApplicable && ...
        sixgr.util.isAcceptableSINRStatus(out.MeasuredTrialSINRValueStatus), ...
        'Actual receiver SINR status must survive runtime/export applicability checks.');
else
    assert(~row.ReceiverHestSINRApplicable && isnan(row.ReceiverHestSINR_dB) && ...
        ~sixgr.util.isAcceptableSINRStatus(row.MeasuredTrialSINRValueStatus) && ...
        row.MeasuredTrialSINRNAReason=="unavailable_pilot_fit_is_not_independent_SINR", ...
        'Unsupported native pilot SINR must remain explicitly unavailable after binding.');
end
assert(isequaln(row.SignedPilotSINRLinear,out.SignedPilotSINRLinear) && ...
    row.PilotPowerEvidenceJSON==out.PilotPowerEvidenceJSON);
temporaryCSV=[tempname '.csv']; cleanup=onCleanup(@()delete(temporaryCSV)); %#ok<NASGU>
writetable(struct2table(row),temporaryCSV);
published=readtable(temporaryCSV,'TextType','string','VariableNamingRule','preserve', ...
    'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0);
if finitePilotExpected
    assert(abs(published.SignedPilotSINRLinear-out.SignedPilotSINRLinear)<1e-12);
else
    assert(isnan(published.SignedPilotSINRLinear) && ...
        ~published.ReceiverHestSINRApplicable && ...
        published.MeasuredTrialSINRNAReason==out.MeasuredTrialSINRNAReason);
end
assert(published.PilotPowerEvidenceJSON==out.PilotPowerEvidenceJSON);
end
