function out=classifyCSIRSSINRModelComparison(a)
%CLASSIFYCSIRSSINRMODELCOMPARISON Separate unlike estimands from accuracy.
% Pure post-reception classification of original_sinr_arithmetic/v1. This
% helper does not establish original-owner authority or run an estimator.
% A raw fixed-linear target/(composite-target) ratio is NOT the native CDM
% channel-estimate/residual ratio. Dedicated CSI-IM alone does not establish
% compatibility either: its measured total may include target leakage, and
% the signal estimate still uses a different operator. No branch here is an
% independently qualified accuracy comparison, even when numbers coincide.
% JSON-decoded receipts are accepted. Original NumericTokens disambiguate
% JSON null from NaN/+Inf/-Inf; vector orientation is not semantic authority.
id='sixgr:refsig:CSIRSSINRModelComparisonOperands';
assert(isstruct(a)&&isscalar(a)&&isfield(a,'ContractVersion')&& ...
    textScalar(a.ContractVersion)&&string(a.ContractVersion)== ...
    "sixgr.csirs.original_sinr_arithmetic/v1",id,'Require the original arithmetic contract.');
required=["ReceiveColumnCount","DedicatedCSIIM","OriginalSource","OriginalDisturbanceSource", ...
    "OriginalSignalPowerEstimation","OriginalInterferenceMeasurement","NumericTokens", ...
    "MeasuredSelectedColumn1","ReferenceSelectedColumn1","ReferenceAtMeasuredSelectedColumn_dB", ...
    "MeasuredSelectedColumnError_dB","ReportedError_dB"];
assert(all(isfield(a,required)),id,'Preserve original arithmetic operands and source metadata.');
assert(realScalar(a.ReceiveColumnCount)&&isfinite(a.ReceiveColumnCount)&& ...
    a.ReceiveColumnCount>=1&&a.ReceiveColumnCount==fix(a.ReceiveColumnCount)&& ...
    booleanScalar(a.DedicatedCSIIM)&&textScalar(a.OriginalSource)&& ...
    textScalar(a.OriginalDisturbanceSource)&& ...
    isstruct(a.OriginalSignalPowerEstimation)&&isscalar(a.OriginalSignalPowerEstimation)&& ...
    isstruct(a.OriginalInterferenceMeasurement)&&isscalar(a.OriginalInterferenceMeasurement)&& ...
    isstruct(a.NumericTokens)&&isscalar(a.NumericTokens),id,'Retain original typed scalar metadata.');
n=double(a.ReceiveColumnCount);
assert(all(isfield(a.NumericTokens,["MeasuredPowerRatioPerReceiveColumn", ...
    "MeasuredEstimatorRatioPerReceiveColumn","ReferenceRatioPerReceiveColumn", ...
    "MeasuredSINR_dB","ReferenceSINR_dB","ErrorPerReceiveColumn_dB", ...
    "MeasuredReportedSINR_dB","ReferenceReportedSINR_dB"])),id, ...
    'Retain the original exact numeric tokens, including nonfinite log values.');
out=a;
% Retain every original power/ratio operand, including signed estimates and
% any original finite-sample ratio correction. Never recompute that estimate.
powerNames=["ReferenceDesiredPerReceiveColumn","ReferenceDisturbancePerReceiveColumn", ...
    "MeasuredSignedDesiredPerReceiveColumn","MeasuredDisturbancePerReceiveColumn", ...
    "DesiredPowerOnDisturbanceSupport","ReceivedPowerOnDisturbanceSupport","CrossEnergyOnDisturbanceSupport"];
for name=powerNames
    out.(name)=numbers(a,name,n,id);
    assert(all(isfinite(out.(name))),id,'Original powers/cross energy must remain finite.');
    if ~any(name==["MeasuredSignedDesiredPerReceiveColumn","CrossEnergyOnDisturbanceSupport"])
        assert(all(out.(name)>=0),id,'Original unsigned powers cannot be negative.');
    end
end
for name=["MeasuredPowerRatioPerReceiveColumn","MeasuredEstimatorRatioPerReceiveColumn", ...
        "ReferenceRatioPerReceiveColumn","MeasuredSINR_dB","ReferenceSINR_dB","ErrorPerReceiveColumn_dB"]
    out.(name)=numbers(a,name,n,id);
end
for name=["MeasuredReportedSINR_dB","ReferenceReportedSINR_dB"]
    out.(name)=numbers(a,name,1,id);
end
measured=out.MeasuredSINR_dB; reference=out.ReferenceSINR_dB;
[measuredMax,selected]=maximum(measured); [referenceMax,refSelected]=maximum(reference);
same(out.MeasuredReportedSINR_dB,measuredMax,id);
same(out.ReferenceReportedSINR_dB,referenceMax,id);
originalScalar(a.MeasuredSelectedColumn1,selected,id);
originalScalar(a.ReferenceSelectedColumn1,refSelected,id);
difference=nan(1,n); finite=isfinite(measured)&isfinite(reference);
difference(finite)=measured(finite)-reference(finite);
same(out.ErrorPerReceiveColumn_dB,difference,id);
selectedDifference=NaN; referenceAtSelected=NaN;
if isfinite(selected)
    selectedDifference=difference(selected); referenceAtSelected=reference(selected);
end
reportedDifference=NaN;
if isfinite(measuredMax)&&isfinite(referenceMax), reportedDifference=measuredMax-referenceMax; end
originalScalar(a.MeasuredSelectedColumnError_dB,selectedDifference,id);
originalScalar(a.ReportedError_dB,reportedDifference,id);
originalScalar(a.ReferenceAtMeasuredSelectedColumn_dB,referenceAtSelected,id);
out.MeasuredSelectedColumn1=selected; out.ReferenceSelectedColumn1=refSelected;
out.ReferenceAtMeasuredSelectedColumn_dB=referenceAtSelected;
out=rmfield(out,{'ErrorPerReceiveColumn_dB','MeasuredSelectedColumnError_dB','ReportedError_dB'});
out.NumericTokens=rmfield(out.NumericTokens,'ErrorPerReceiveColumn_dB');
out.ContractVersion="sixgr.csirs.sinr_model_estimand_comparison/v1";
out.OriginalArithmeticContractVersion=string(a.ContractVersion);
out.OriginalArithmeticSHA256=sixgr.util.sha256Hex(char(jsonencode(sixgr.util.jsonSafeValue(a))));
out.OriginalArithmeticHashSerialization="jsonSafeValue_jsonencode_supplied_arithmetic_receipt";
out.RequirementClass="IMPLEMENTATION_POLICY";
out.Scope="supplied_arithmetic_estimand_classification_not_original_owner_or_accuracy_proof";
out.MeasuredSignalScope=signalScope(string(a.OriginalSource));
out.ReferenceSignalScope="raw_native_FFT_fixed_linear_port3000_model_RE_second_moment";
out.ReferenceDisturbanceScope="raw_native_FFT_composite_minus_target_sample_residual_second_moment_on_port3000_REs";
disturbance=string(a.OriginalDisturbanceSource);
if logical(a.DedicatedCSIIM)
    out.MeasuredDisturbanceScope="original_configured_CSI_IM_received_total_second_moment";
    out.ReferenceDisturbanceScope="raw_native_FFT_composite_minus_target_sample_residual_second_moment_on_CSI_IM_REs";
    out.SINREstimandCompatibilityStatus="unproven_dedicated_CSI_IM_signal_and_leakage_operators";
    out.SINREstimandCompatibilityReason="Dedicated CSI-IM does not equate the CDM/LS signal estimate to raw target power; its received total also differs from composite-minus-target when target leaks onto CSI-IM. No matched-operator proof is supplied.";
    if disturbance~="configured_CSI_IM_received_RE_second_moment"
        out.MeasuredDisturbanceScope="unrecognized_original_dedicated_CSI_IM_operator";
    end
elseif disturbance=="nrChannelEstimate_received_reference_residual"
    out.MeasuredDisturbanceScope="native_CDM_channel_estimation_denoised_reference_residual_variance";
    out.SINREstimandCompatibilityStatus="incompatible_native_reference_residual_operator";
    out.SINREstimandCompatibilityReason="The native channel-estimation residual is not the raw composite-minus-target second moment, which retains other logical-port energy. The signal estimators also differ.";
elseif disturbance=="received_flat_joint_LS_residual_with_degrees_of_freedom"
    out.MeasuredDisturbanceScope="joint_flat_LS_projection_residual_with_degrees_of_freedom";
    out.SINREstimandCompatibilityStatus="incompatible_joint_LS_residual_operator";
    out.SINREstimandCompatibilityReason="A joint LS projection residual with degrees-of-freedom scaling is not the raw composite-minus-target second moment; matching supports alone does not match these operators.";
else
    out.MeasuredDisturbanceScope="unrecognized_original_measurement_operator";
    out.SINREstimandCompatibilityStatus="unproven_original_measurement_operator";
    out.SINREstimandCompatibilityReason="No validated mapping from the original signal/disturbance estimators to the raw fixed-linear model ratio is supplied.";
end
out.SINREstimandCompatible=false;
out.AccuracyComparisonAvailable=false;
out.AccuracyErrorPerReceiveColumn_dB=nan(1,n);
out.ReportedSINRError_dB=NaN;
out.SelectedColumnSINRError_dB=NaN;
out.LogRatioDifferencePerReceiveColumn_dB=difference;
out.ReportedSINRLogRatioDifference_dB=reportedDifference;
out.SelectedColumnSINRLogRatioDifference_dB=selectedDifference;
out.LogRatioDifferenceDefinition="original_measured_log_ratio_minus_raw_fixed_linear_model_log_ratio_not_accuracy_error";
out.ReportedLogRatioDifferencePolicy="independently_selected_measured_max_minus_reference_max";
out.SelectedColumnLogRatioDifferencePolicy="measured_minus_reference_at_original_measured_selected_column";
out.StandardizedAccuracyQualified=false; out.StatisticallyQualified=false;
out.HardwareQualified=false; out.ReferenceUsedByReceiver=false;
for name=["LogRatioDifferencePerReceiveColumn_dB","ReportedSINRLogRatioDifference_dB", ...
        "SelectedColumnSINRLogRatioDifference_dB","AccuracyErrorPerReceiveColumn_dB", ...
        "ReportedSINRError_dB","SelectedColumnSINRError_dB"]
    out.NumericTokens.(name)=compose('%.17g',out.(name));
end
end

function value=numbers(a,name,count,id)
assert(isfield(a,name)&&isnumeric(a.(name))&&isreal(a.(name))&&~issparse(a.(name)), ...
    id,'Original %s must be numeric, not coerced character data.',name);
raw=a.(name);
assert(isvector(raw)||isempty(raw),id,'Original %s must be a scalar/vector.',name);
value=double(raw(:).');
if isfield(a.NumericTokens,name)
    tokens=a.NumericTokens.(name);
    assert(isstring(tokens)||ischar(tokens)||iscellstr(tokens),id,'NumericTokens must be text.'); %#ok<ISCLSTR>
    if ischar(tokens), assert(isrow(tokens),id,'A scalar numeric token must be one text row.'); end
    tokens=string(tokens); tokens=tokens(:).';
    assert(numel(tokens)==count&&~any(ismissing(tokens)),id,'Preserve original numeric token count.');
    decoded=str2double(tokens);
    assert(all(isfinite(decoded)|ismember(tokens,["NaN","Inf","-Inf"])),id,'Invalid original numeric token.');
    if isempty(value)
        assert(count==1&&~isfinite(decoded),id,'Only serialized scalar null has no numeric elements.');
    else
        assert(numel(value)==count,id,'Original numeric count changed.');
        % jsondecode represents numeric null as NaN. A token may restore a
        % nonfinite value only there; it cannot replace any finite operand.
        assert(all(value==decoded | (isnan(value)&~isfinite(decoded))),id, ...
            'Original numeric values and their exact tokens disagree.');
    end
    value=decoded;
end
assert(numel(value)==count,id,'Preserve original numeric count.');
end
function originalScalar(raw,expected,id)
assert(isnumeric(raw)&&isreal(raw)&&~issparse(raw),id,'Original selected values must be numeric.');
if isempty(raw)
    assert(~isfinite(expected),id,'A serialized null cannot stand for a finite original value.');
else
    assert(isscalar(raw),id,'Original selected values must be scalar.');
    % An original scalar null has no token for these redundant selected
    % fields; recover only the value already determined by token-bound logs.
    if isnan(raw)&&~isfinite(expected), return; end
    same(double(raw),expected,id);
end
end
function same(a,b,id)
assert(isequal(isnan(a),isnan(b))&&isequal(isinf(a),isinf(b))&& ...
    all(a(isinf(b))==b(isinf(b))),id,'Original arithmetic fields disagree.');
finite=isfinite(b);
assert(all(abs(a(finite)-b(finite))<=64*eps(max(1,abs(b(finite))))),id, ...
    'Original arithmetic fields disagree.');
end
function [value,index]=maximum(x)
[value,index]=max(x,[],'omitnan');
if isempty(value)||isnan(value), value=NaN; index=NaN; end
end
function value=signalScope(source)
switch source
    case "nrChannelEstimate_port3000_reference_RE_power_per_receive_branch"
        value="native_smoothed_CDM_port3000_channel_estimate_RE_power";
    case "received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"
        value="local_CDM_port3000_signed_CSI_IM_debiased_projection_power";
    case "received_flat_LS_noise_debiased_port3000_reference_RE_power"
        value="joint_flat_LS_port3000_signed_noise_debiased_power";
    otherwise
        value="unrecognized_original_signal_estimator";
end
end
function tf=textScalar(x)
tf=(isstring(x)&&isscalar(x)&&~ismissing(x))||(ischar(x)&&isrow(x));
end
function tf=realScalar(x)
tf=isnumeric(x)&&isreal(x)&&isscalar(x)&&~issparse(x);
end
function tf=booleanScalar(x)
tf=(islogical(x)||isnumeric(x))&&isreal(x)&&isscalar(x)&&~issparse(x)&& ...
    isfinite(x)&&(x==0||x==1);
end
