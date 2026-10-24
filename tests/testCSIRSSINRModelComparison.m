function ok=testCSIRSSINRModelComparison()
% Explicitly declared arithmetic/operator scopes, NOT physical evidence.
% No native receiver, channel, RF, waveform, feedback or accuracy campaign.
setup6GRSimToolkit('Verbose',false);
initialRNG=rng;
call=@sixgr.phy.refsig.classifyCSIRSSINRModelComparison;

% 1. Native residual and raw other-port energy are unlike estimands. The
% measured and reference maxima deliberately select DIFFERENT columns.
a=fixture([100 1],[1 1],[1 4],[2 1],"native",false);
saved=a; out=call(a);
assert(isequaln(a,saved)&&out.MeasuredSelectedColumn1==1&&out.ReferenceSelectedColumn1==2);
assert(out.SINREstimandCompatibilityStatus=="incompatible_native_reference_residual_operator");
close(out.ReportedSINRLogRatioDifference_dB,20-10*log10(4));
close(out.SelectedColumnSINRLogRatioDifference_dB,20-10*log10(.5));
close(out.LogRatioDifferencePerReceiveColumn_dB,a.ErrorPerReceiveColumn_dB);
assertUnavailable(out); assertSources(a,out);
assert(~isfield(out,'ReportedError_dB')&&~isfield(out,'ErrorPerReceiveColumn_dB')&& ...
    ~isfield(out,'MeasuredSelectedColumnError_dB')&& ...
    ~isfield(out.NumericTokens,'ErrorPerReceiveColumn_dB'));
assert(out.OriginalArithmeticSHA256== ...
    sixgr.util.sha256Hex(char(jsonencode(sixgr.util.jsonSafeValue(a)))));
fprintf('CSI_SINR_MODEL_COMPARISON group=native_unmatched PASS\n');

% 2. Actual pure second-moment arithmetic on declared CSI-IM grid samples.
% Nonzero target leakage is retained. Zero leakage is not a signal-operator
% compatibility proof either; no CSI-IM case is upgraded automatically.
for leakage=[true false]
    im=fixture([5 2],[1 1],[1 4],[2 1],"cdm",true,leakage);
    z=call(im); assertSources(im,z); assertUnavailable(z);
    assert(z.SINREstimandCompatibilityStatus=="unproven_dedicated_CSI_IM_signal_and_leakage_operators"&& ...
        z.DedicatedCSIIM&&z.OriginalCSIIMSecondMomentVerified&& ...
        isequal(z.DesiredPowerOnDisturbanceSupport,im.DesiredPowerOnDisturbanceSupport));
    assert(contains(z.MeasuredDisturbanceScope,"received_total")&& ...
        contains(z.ReferenceDisturbanceScope,"composite_minus_target"));
    if leakage, assert(any(z.DesiredPowerOnDisturbanceSupport>0));
    else, assert(all(z.DesiredPowerOnDisturbanceSupport==0)); end
end
fprintf('CSI_SINR_MODEL_COMPARISON group=CSI_IM_not_automatic PASS\n');

% 3. Original estimator-specific corrected ratios must not be replaced with
% signed power/noise. Flat-LS degrees-of-freedom residual is also unmatched.
flat=fixture([2 -1],[1 2],[1 4],[2 1],"flat",false);
z=call(flat); assertSources(flat,z); assertUnavailable(z);
assert(z.SINREstimandCompatibilityStatus=="incompatible_joint_LS_residual_operator"&& ...
    isequal(z.MeasuredSignedDesiredPerReceiveColumn,[2 -1])&& ...
    isequal(z.MeasuredPowerRatioPerReceiveColumn,[2 -.5])&& ...
    isequal(z.MeasuredEstimatorRatioPerReceiveColumn,[1.6 -.4])&&isnan(z.MeasuredSINR_dB(2)));
fprintf('CSI_SINR_MODEL_COMPARISON group=signed_original_estimator PASS\n');

% 4. Numeric agreement does not establish operator agreement. Unknown
% sources are preserved as unknown, not silently mapped to the native path.
equal=fixture([1 4],[2 1],[1 4],[2 1],"native",false);
z=call(equal); close(z.LogRatioDifferencePerReceiveColumn_dB,[0 0]); assertUnavailable(z);
unknown=equal; unknown.OriginalSource="declared_unknown_signal";
unknown.OriginalDisturbanceSource="declared_unknown_disturbance";
z=call(unknown); assertSources(unknown,z); assertUnavailable(z);
assert(z.SINREstimandCompatibilityStatus=="unproven_original_measurement_operator");
fprintf('CSI_SINR_MODEL_COMPARISON group=coincidence_not_authority PASS\n');

% 5. Original Inf/NaN/zero/signed values retain exact meaning through JSON.
% Undefined Inf-Inf is NaN, not zero and not a finite accuracy error.
special=fixture([1 0 -1],[0 0 1],[1 0 0],[0 0 1],"flat",false);
z=call(special); assertUnavailable(z);
assert(z.MeasuredSINR_dB(1)==Inf&&z.ReferenceSINR_dB(1)==Inf&& ...
    isnan(z.MeasuredSINR_dB(2))&&isnan(z.ReferenceSINR_dB(2))&& ...
    z.ReferenceSINR_dB(3)==-Inf&&isnan(z.ReportedSINRLogRatioDifference_dB)&& ...
    all(isnan(z.LogRatioDifferencePerReceiveColumn_dB)));
decoded=jsondecode(jsonencode(sixgr.util.jsonSafeValue(special)));
zz=call(decoded);
assert(isequaln(zz.MeasuredSINR_dB,z.MeasuredSINR_dB)&& ...
    isequaln(zz.ReferenceSINR_dB,z.ReferenceSINR_dB)&& ...
    isequaln(zz.LogRatioDifferencePerReceiveColumn_dB,z.LogRatioDifferencePerReceiveColumn_dB));
assertSources(decoded,zz); assertUnavailable(zz);
allMissing=fixture([-1 0],[1 0],[0 0],[1 0],"flat",false);
zz=call(jsondecode(jsonencode(sixgr.util.jsonSafeValue(allMissing))));
assert(isnan(zz.MeasuredSelectedColumn1)&&isnan(zz.MeasuredReportedSINR_dB)&& ...
    isnan(zz.SelectedColumnSINRLogRatioDifference_dB));
fprintf('CSI_SINR_MODEL_COMPARISON group=nonfinite_JSON PASS\n');

% 6. Exact retained-receipt entry point: normal JSON vector orientation and
% source strings survive. Input metadata is not rewritten or re-estimated.
decoded=jsondecode(jsonencode(sixgr.util.jsonSafeValue(a)));
decoded.MeasuredSINR_dB=decoded.MeasuredSINR_dB(:);
decoded.ReferenceSINR_dB=decoded.ReferenceSINR_dB(:);
before=decoded;
z=call(decoded); assertSources(decoded,z); assertUnavailable(z);
close(z.ReportedSINRLogRatioDifference_dB,out.ReportedSINRLogRatioDifference_dB);
close(z.SelectedColumnSINRLogRatioDifference_dB,out.SelectedColumnSINRLogRatioDifference_dB);
assert(isequaln(decoded,before));
fprintf('CSI_SINR_MODEL_COMPARISON group=retained_receipt_shape PASS\n');

% 7. Reject raw character-codepoint identities/powers and contradictory
% redundant values; original string tokens cannot overwrite finite numbers.
bad=a; bad.ReceiveColumnCount=char(2); reject(@()call(bad));
bad=a; bad.DedicatedCSIIM=char(0); reject(@()call(bad));
bad=a; bad.DedicatedCSIIM=2; reject(@()call(bad));
bad=a; bad.ReferenceDesiredPerReceiveColumn=char([1 4]); reject(@()call(bad));
bad=a; bad.MeasuredSelectedColumn1=char(1); reject(@()call(bad));
bad=a; bad.OriginalSource=17; reject(@()call(bad));
bad=a; bad.ReferenceSINR_dB=ones(2); reject(@()call(bad));
bad=a; bad.ReportedError_dB=bad.ReportedError_dB+1; reject(@()call(bad));
bad=a; bad.NumericTokens.MeasuredSINR_dB=string(bad.NumericTokens.MeasuredSINR_dB);
bad.NumericTokens.MeasuredSINR_dB(1)="19"; reject(@()call(bad));
bad=a; bad.NumericTokens.MeasuredSINR_dB=string(bad.NumericTokens.MeasuredSINR_dB);
bad.NumericTokens.MeasuredSINR_dB(1)="not_a_number"; reject(@()call(bad));
assert(isequal(rng,initialRNG),'Pure classification must not draw or reseed randomness.');
fprintf('CSI_SINR_MODEL_COMPARISON group=guards_and_no_mutation PASS\n');
ok=true;
end

function a=fixture(ps,pn,referencePower,referenceNoise,mode,dedicated,leakage)
if nargin<7, leakage=true; end
n=numel(ps); d=complex(zeros(4,2,n)); u=d;
for k=1:n, d(:,:,k)=sqrt(referencePower(k)); u(:,:,k)=1i*sqrt(referenceNoise(k)); end
if dedicated&&~leakage, d(:,2,:)=0; end
y=d+u; im=struct('Plan',struct('Enabled',false));
noiseSource="nrChannelEstimate_received_reference_residual";
source="nrChannelEstimate_port3000_reference_RE_power_per_receive_branch";
if dedicated
    idx=[5;6]; flat=reshape(y,[],n); samples=flat(idx,:);
    covariance=samples.'*conj(samples)/numel(idx); covariance=(covariance+covariance')/2;
    pn=real(diag(covariance)).';
    im=struct('Available',true,'SampleCount',numel(idx),'Covariance',covariance, ...
        'PowerPerReceiveAntenna',pn,'MeanPower',mean(pn), ...
        'Source',"configured_CSI_IM_received_RE_second_moment", ...
        'Plan',struct('Enabled',true,'Scheduled',true,'PhysicalIndices1Based',idx,'NumRE',numel(idx)));
    noiseSource="configured_CSI_IM_received_RE_second_moment";
end
ratio=ps./pn; est=struct();
if mode=="flat"
    source="received_flat_LS_noise_debiased_port3000_reference_RE_power";
    if ~dedicated, noiseSource="received_flat_joint_LS_residual_with_degrees_of_freedom"; end
    ratio=.8*ratio; est=struct('SignedPort3000SNRLinearPerBranch',ratio);
elseif mode=="cdm"
    source="received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power";
    est=struct('SignedPort3000SNRLinearPerBranch',ratio);
end
logs=10*log10(ratio);
if mode~="native", logs=nan(size(ratio)); pos=ratio>0; logs(pos)=10*log10(ratio(pos)); end
[reported,column]=max(logs,[],'omitnan'); if isnan(reported), column=NaN; end
m=struct('DesiredPowerPerReceiveAntenna',ps,'NoiseInterferencePowerPerReceiveAntenna',pn, ...
    'CSI_SINRPerReceiveAntenna_dB',logs,'CSI_SINR_dB',reported,'ReceiveBranch1Based',column, ...
    'SignalPowerEstimation',est,'InterferenceMeasurement',im,'ReferencePort',3000, ...
    'ReferenceRECount',2,'Source',source,'DisturbanceSource',noiseSource);
a=sixgr.phy.refsig.compareCSIRSSINRReference(d,y,[0 0;1 0],8,m,"normalized_complex_baseband");
end
function assertUnavailable(a)
assert(isequal(a.SINREstimandCompatible,false)&&isequal(a.AccuracyComparisonAvailable,false)&& ...
    isnan(a.ReportedSINRError_dB)&&isnan(a.SelectedColumnSINRError_dB)&& ...
    all(isnan(a.AccuracyErrorPerReceiveColumn_dB))&& ...
    ~a.StandardizedAccuracyQualified&&~a.StatisticallyQualified&&~a.HardwareQualified&&~a.ReferenceUsedByReceiver);
end
function assertSources(a,b)
assert(isequal(a.OriginalSource,b.OriginalSource)&& ...
    isequal(a.OriginalDisturbanceSource,b.OriginalDisturbanceSource)&& ...
    isequaln(a.OriginalSignalPowerEstimation,b.OriginalSignalPowerEstimation)&& ...
    isequaln(a.OriginalInterferenceMeasurement,b.OriginalInterferenceMeasurement));
end
function close(a,b)
assert(isequal(size(a),size(b))&&all(abs(a-b)<=1e-12*max(1,abs(b)),'all'));
end
function reject(call)
try, call(); catch cause
    assert(string(cause.identifier)=="sixgr:refsig:CSIRSSINRModelComparisonOperands"); return;
end
error('test:MissingRejection','Malformed model comparison operands were accepted.');
end
