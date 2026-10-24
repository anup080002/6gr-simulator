function out=compareCSIRSCDMModelReference(T,O,R,X,Y,reference,support,nfft,measured,unit)
% Recorded-CDM MODEL comparison, never an independent physical reference.
% Q(Z)=sum_g E_g*abs(w_g.'*Z(I_g,:)).^2/Npilot. The ORIGINAL
% measurement uses Q(Y)-bias*D, where D is the ORIGINAL received CSI-IM
% second moment. D is shared observed evidence, not independent truth.
% All coherent terms, including other-port leakage and common DC, remain.
id='sixgr:refsig:CSIRSCDMModelReferenceOperands';
out=struct('ContractVersion',"sixgr.csirs.recorded_cdm_model_comparison/v1", ...
    'Available',false,'Status',"unavailable_original_CDM_projection_not_recorded", ...
    'Source',"post_reception_original_CDM_operator_fixed_linear_model_comparison", ...
    'RequirementClass',"IMPLEMENTATION_POLICY",'ModelOnly',true, ...
    'OperatorMatchedModelComparisonAvailable',false, ...
    'DenominatorIndependentlyReferenced',false,'OriginalCSIIMSecondMomentReproduced',false, ...
    'IndependentAccuracyQualified',false,'UniqueNonlinearPortAttributionQualified',false, ...
    'StandardizedAccuracyQualified',false,'StatisticallyQualified',false,'HardwareQualified',false, ...
    'ReferenceUsedByReceiver',false,'AdditionalRFExecutions',0,'AdditionalChannelExecutions',0, ...
    'AdditionalTimingAcquisitions',0,'AdditionalChannelEstimates',0);
assert(isstruct(measured)&&isscalar(measured),id,'Original measurement must be one structure.');
if ~isfield(measured,'SignalPowerEstimation')|| ...
        ~isstruct(measured.SignalPowerEstimation)|| ...
        ~isfield(measured.SignalPowerEstimation,'CDMProjectionReceipt')
    return; % Native or joint-LS measurement has no recorded local CDM operator.
end
est=measured.SignalPowerEstimation;
assert(isscalar(est)&&isfield(est,'CDMProjectionReceiptSHA256')&& ...
    textEquals(measured.Source,"received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"), ...
    id,'Only the original dedicated-CSIIM local CDM producer is supported.');
c=est.CDMProjectionReceipt;
assert(isstruct(c)&&isscalar(c)&& ...
    textEquals(c.ContractVersion,"sixgr.csirs.original_cdm_projection/v1")&& ...
    textEquals(c.Source,"original_practical_CDM_port3000_projection")&& ...
    textEquals(c.SampleHashSerialization,"WaveformHash.runtimeArray_class_dimensions_real_imag_double")&& ...
    textEquals(c.ProjectionConvention,"weights_nonconjugating_transpose_times_received_tile")&& ...
    textEquals(c.WeightDefinition,"conj_original_port3000_pilot_divided_by_original_tile_pilot_energy")&& ...
    textEquals(c.PowerNormalization,"sum_tile_energy_times_abs_coefficient_squared_divided_by_original_pilot_count")&& ...
    textEquals(c.UsedSupportSerializationOrder,"TileIndices1Based_column_major_then_original_receive_or_reference_columns")&& ...
    isequal(c.ClippedToNonnegative,false)&&isequal(c.WaveformAmplitudeUnitBound,false)&& ...
    isequal(c.ResourceIdentityBound,false)&&isequal(c.OriginalSharedOwnerBound,false)&& ...
    isequal(c.IndependentReferenceAvailable,false)&&isequal(c.StandardizedAccuracyQualified,false)&& ...
    isequal(c.ReferenceUsedByReceiver,false)&&isequal(est.ClippedToNonnegative,false)&& ...
    textEquals(est.CDMProjectionReceiptSHA256, ...
        sixgr.util.sha256Hex(char(jsonencode(c)))),id,'Original CDM receipt/hash changed.');
grids={T,O,R,X,Y};
for k=1:numel(grids)
    a=grids{k};
    assert((isa(a,'double')||isa(a,'single'))&&~issparse(a)&&~isempty(a)&& ...
        ndims(a)<=3&&all(isfinite(a),'all')&&isequal(size(a),size(Y))&& ...
        strcmp(class(a),class(Y)),id,'Use matching original typed finite FFT grids.');
end
K=size(Y,1); L=size(Y,2); nRx=size(Y,3);
assert((isa(reference,'double')||isa(reference,'single'))&&~issparse(reference)&& ...
    ndims(reference)<=3&&size(reference,1)==K&&size(reference,2)==L&& ...
    all(isfinite(reference),'all'),id,'Use the original mapped logical pilot grid.');
assert(realScalar(nfft)&&isfinite(nfft)&&nfft>=K&&nfft==fix(nfft)&& ...
    (textEquals(unit,"sqrt_mW")||textEquals(unit,"normalized_complex_baseband")), ...
    id,'Explicit original FFT size and power unit are required.');
assert(isnumeric(support)&&isreal(support)&&ismatrix(support)&&size(support,2)==2&& ...
    ~isempty(support)&&all(isfinite(support),'all')&&all(support==fix(support),'all')&& ...
    all(support(:,1)>=0&support(:,1)<K)&&all(support(:,2)>=0&support(:,2)<L)&& ...
    size(unique(support,'rows'),1)==size(support,1),id,'Retain unique original port-3000 REs.');
scale=1; powerUnit="unit_RE";
if textEquals(unit,"sqrt_mW"), scale=double(nfft)*sqrt(1000); powerUnit="W"; end
% Match the actual measurement's class-preserving scaling BEFORE double.
for k=1:numel(grids)
    if scale~=1, grids{k}=grids{k}./cast(scale,'like',grids{k}); end
end
ym=grids{5};
assert(textEquals(c.InputGridClass,class(ym))&&textEquals(c.ReferenceGridClass,class(reference))&& ...
    vectorEqual(c.InputGridSize,size(ym))&&vectorEqual(c.ReferenceGridSize,size(reference)), ...
    id,'Receipt must bind the exact original scaled noisy and logical-reference grid dimensions/classes.');
indices=c.TileIndices1Based; wr=c.ProjectionWeightsReal; wi=c.ProjectionWeightsImag;
assert(realArray(indices)&&ismatrix(indices)&&~isempty(indices)&& ...
    all(indices==fix(indices),'all')&&all(indices>=1&indices<=K*L,'all')&& ...
    numel(unique(indices(:)))==numel(indices)&&realArray(wr)&&realArray(wi)&& ...
    isequal(size(wr),size(indices),size(wi)),id,'Original tiles/weights must be finite numeric arrays.');
g=size(indices,2); N=numel(indices); weights=complex(double(wr),double(wi));
typedY=reshape(ym,K*L,nRx); typedReference=reshape(reference,K*L,[]);
usedY=typedY(double(indices(:)),:); usedReference=typedReference(double(indices(:)),:);
inputDigest=hash(usedY); referenceDigest=hash(usedReference);
arithmeticInputDigest=inputDigest; arithmeticReferenceDigest=referenceDigest;
if ~isa(usedY,'double'), arithmeticInputDigest=hash(double(usedY)); end
if ~isa(usedReference,'double'), arithmeticReferenceDigest=hash(double(usedReference)); end
assert(textEquals(c.InputUsedSupportSHA256,inputDigest)&& ...
    textEquals(c.ReferenceUsedSupportSHA256,referenceDigest)&& ...
    textEquals(c.ArithmeticInputUsedSupportSHA256,arithmeticInputDigest)&& ...
    textEquals(c.ArithmeticReferenceUsedSupportSHA256,arithmeticReferenceDigest)&& ...
    isequal(c.ArithmeticInputHashReusesTypedSupportHash,isa(usedY,'double'))&& ...
    isequal(c.ArithmeticReferenceHashReusesTypedSupportHash,isa(usedReference,'double')),id, ...
    'Receipt must bind every original typed used-support sample in original tile order.');
energy=vector(c.ReferenceEnergyPerTile,g,id); noiseGain=vector(c.UnitNoiseGainPerTile,g,id);
assert(all(energy>0)&&all(noiseGain>0)&&scalarEqual(c.NormalizationPilotCount,N)&& ...
    scalarEqual(c.TileCount,g)&&scalarEqual(c.ReceiveColumnCount,nRx)&& ...
    scalarEqual(c.ReferencePortCount,size(reference,3))&&scalarEqual(c.ReferencePortNumber,3000)&& ...
    scalarEqual(c.TileSize,size(indices,1))&&vectorEqual(c.ReceiveColumnIndices0,0:nRx-1)&& ...
    vectorEqual(c.CDMLengths,measured.CDMLengths)&& ...
    scalarEqual(measured.ReferencePort,3000)&&scalarEqual(measured.ReferenceRECount,N)&& ...
    isequal(sort(double(indices(:))),sort(sub2ind([K L],double(support(:,1))+1,double(support(:,2))+1))), ...
    id,'Exact original tile population, port, receive columns and support are required.');
flatReference=typedReference;
assert(isequal(sort(double(indices(:))),find(flatReference(:,1)~=0)),id,'Do not omit original port-3000 pilots.');
coeff=cell(1,5); powers=zeros(4,nRx); pairs=zeros(6,2); cross=zeros(6,nRx);
flatGrids=cell(1,5); absoluteProducts=cell(1,5);
for k=1:5
    coeff{k}=complex(zeros(g,nRx)); flatGrids{k}=reshape(grids{k},K*L,nRx);
    absoluteProducts{k}=zeros(g,nRx);
end
for j=1:g
    idx=double(indices(:,j)); pilot=double(flatReference(idx,1));
    moment(energy(j),sum(abs(pilot).^2),numel(idx),id);
    moment(weights(:,j),conj(pilot)/energy(j),numel(idx),id);
    moment(noiseGain(j),sum(abs(weights(:,j)).^2),numel(idx),id);
    projection=weights(:,j).'*double(flatReference(idx,:));
    moment(projection,[1 zeros(1,size(reference,3)-1)],numel(idx),id);
    for k=1:5
        samples=double(flatGrids{k}(idx,:));
        coeff{k}(j,:)=weights(:,j).'*samples;
        absoluteProducts{k}(j,:)=sum(abs(weights(:,j)).*abs(samples),1);
    end
end
assert(realArray(c.ProjectedCoefficientsReal)&&realArray(c.ProjectedCoefficientsImag)&& ...
    isequal(size(c.ProjectedCoefficientsReal),[g nRx])&& ...
    isequal(size(c.ProjectedCoefficientsImag),[g nRx]),id,'Original noisy projection shape/type changed.');
moment(coeff{5},complex(double(c.ProjectedCoefficientsReal),double(c.ProjectedCoefficientsImag)),N,id);
sumCoefficients=coeff{1}+coeff{2}+coeff{3}+coeff{4};
productScale=absoluteProducts{1}+absoluteProducts{2}+absoluteProducts{3}+ ...
    absoluteProducts{4}+absoluteProducts{5};
coefficientBound=closure(sumCoefficients,coeff{5},productScale,N,id);
for k=1:4, powers(k,:)=sum(energy(:).*abs(coeff{k}).^2,1)/N; end
qY=sum(energy(:).*abs(coeff{5}).^2,1)/N;
n=0;
for i=1:3
    for j=i+1:4
        n=n+1; pairs(n,:)=[i j];
        cross(n,:)=2*real(sum(energy(:).*conj(coeff{i}).*coeff{j},1))/N;
    end
end
projectionScale=sum(energy(:).*productScale.^2,1)/N;
powerBound=closure(sum(powers,1)+sum(cross,1),qY, ...
    sum(abs(powers),1)+sum(abs(cross),1)+abs(qY)+projectionScale,N,id);
moment(vector(c.WeightedSquaredCoefficientSumPerBranch,nRx,id),qY*N,N,id);
unitBias=sum(energy(:).*noiseGain(:))/N;
assert(realScalar(c.UnitNoiseBiasWeightedSum)&&realScalar(c.UnitDisturbancePowerBias),id,'Original bias operands must be numeric.');
moment(double(c.UnitNoiseBiasWeightedSum),unitBias*N,N,id);
moment(double(c.UnitDisturbancePowerBias),unitBias,N,id);
% Reuse the strict original CSI-IM moment/support validation, not its raw
% model residual denominator. That raw comparison remains a separate view.
raw=sixgr.phy.refsig.compareCSIRSSINRReference(T,Y,support,nfft,measured,unit);
assert(raw.DedicatedCSIIM&&raw.OriginalCSIIMSecondMomentVerified,id,'Dedicated original CSI-IM evidence is mandatory.');
D=raw.MeasuredDisturbancePerReceiveColumn;
bias=unitBias*D; signed=qY-bias;
for holder={c,est}
    h=holder{1};
    moment(vector(h.RawPort3000PowerPerBranch,nRx,id),qY,N,id);
    moment(vector(h.EstimatedNoiseBiasPerBranch,nRx,id),bias,N,id);
    moment(vector(h.SignedPort3000PowerPerBranch,nRx,id),signed,N,id);
end
moment(vector(c.DisturbancePowerPerBranch,nRx,id),D,N,id);
moment(raw.MeasuredSignedDesiredPerReceiveColumn,signed,N,id);
sameSpecial(raw.MeasuredEstimatorRatioPerReceiveColumn,signed./D,id);
target=powers(1,:); modelRatio=target./D;
modelLogs=10*log10(modelRatio); measuredLogs=raw.MeasuredSINR_dB;
powerLogs=positiveLog(signed); targetLogs=10*log10(target);
sinrDifference=nan(1,nRx); valid=isfinite(measuredLogs)&isfinite(modelLogs);
sinrDifference(valid)=measuredLogs(valid)-modelLogs(valid);
powerDifference=nan(1,nRx); valid=isfinite(powerLogs)&isfinite(targetLogs);
powerDifference(valid)=powerLogs(valid)-targetLogs(valid);
[ms,mc]=maximum(measuredLogs); [rs,rc]=maximum(modelLogs);
[mp,pc]=maximum(powerLogs); [rp,rpc]=maximum(targetLogs);
out.Available=true; out.OperatorMatchedModelComparisonAvailable=true;
out.Status="available_recorded_CDM_model_comparison_shared_observed_CSI_IM_not_independent_accuracy";
out.OriginalCSIIMSecondMomentReproduced=true;
out.OriginalCDMProjectionReceiptSHA256=string(est.CDMProjectionReceiptSHA256);
out.OriginalMeasurementUsedSupportSHA256=inputDigest;
out.OriginalReferenceUsedSupportSHA256=referenceDigest;
out.WaveformAmplitudeUnit=string(unit); out.LinearPowerUnit=powerUnit; out.RawGridAmplitudeDivisor=scale;
out.SignalSupport0Based=support; out.CSIIMSupport0Based=raw.DisturbanceSupport0Based;
out.CDMGroupCount=g; out.NormalizationPilotCount=N; out.OriginalUnitDisturbancePowerBias=unitBias;
out.TermOrder=["target_model","other_linear_including_common_DC","nonlinear_DAC_model_residual","external_and_noise"];
out.ProjectedCoefficients=coeff;
out.ProjectedPowerPerTermPerReceiveColumn=powers; out.CrossPairIndices1=pairs;
out.ProjectedSignedCrossPowerPerReceiveColumn=cross; out.OriginalProjectedNoisyPowerPerReceiveColumn=qY;
out.ProjectedPowerClosureResidual=qY-sum(powers,1)-sum(cross,1);
out.CoefficientClosureRoundoffBound=coefficientBound;
out.ProjectedPowerClosureRoundoffBound=powerBound;
out.OriginalObservedCSIIMTotalPowerPerReceiveColumn=D;
out.OriginalNoiseBiasPerReceiveColumn=bias; out.OriginalMeasuredSignedPowerPerReceiveColumn=signed;
out.ModelTargetProjectedPowerPerReceiveColumn=target;
out.ReferenceTargetRawREPowerPerReceiveColumn=raw.ReferenceDesiredPerReceiveColumn;
out.ReferenceTargetProjectedPowerPerReceiveColumn=target;
out.TargetProjectionMinusRawREPowerPerReceiveColumn=target-raw.ReferenceDesiredPerReceiveColumn;
out.TargetProjectionIsPhysicalREPower=false;
out.MeasuredMinusTargetPowerPerReceiveColumn=signed-target;
out.NonTargetPlusCrossMinusBiasPerReceiveColumn=sum(powers(2:4,:),1)+sum(cross,1)-bias;
out.PowerDifferenceClosureRoundoffBound=closure(out.MeasuredMinusTargetPowerPerReceiveColumn, ...
    out.NonTargetPlusCrossMinusBiasPerReceiveColumn, ...
    abs(qY)+abs(target)+sum(abs(powers),1)+sum(abs(cross),1)+abs(bias)+projectionScale,N,id);
out.CSIIMTerms=imTerms(grids,raw.DisturbanceSupport0Based,D,id);
out.MeasuredSINR_dB=measuredLogs; out.ModelSINR_dB=modelLogs;
out.MeasuredEstimatorRatioPerReceiveColumn=raw.MeasuredEstimatorRatioPerReceiveColumn;
out.ModelRatioPerReceiveColumn=modelRatio;
out.PowerDifferencePerReceiveColumn_dB=powerDifference;
out.SINRLogRatioDifferencePerReceiveColumn_dB=sinrDifference;
out.OriginalPowerSelectedColumn1=pc; out.ModelPowerSelectedColumn1=rpc;
out.OriginalSINRSelectedColumn1=mc; out.ModelSINRSelectedColumn1=rc;
out.ReportedPowerDifference_dB=finiteDifference(mp,rp);
out.SelectedColumnPowerDifference_dB=selectedDifference(powerDifference,pc);
out.ReportedSINRLogRatioDifference_dB=finiteDifference(ms,rs);
out.SelectedColumnSINRLogRatioDifference_dB=selectedDifference(sinrDifference,mc);
out.SignalComparisonScope="original_noisy_CDM_signed_power_minus_same_recorded_projection_of_fixed_linear_target";
out.DenominatorScope="same_original_received_total_CSI_IM_second_moment_in_both_ratios_not_independent_reference";
out.NoiseBiasAssumption=string(est.NoiseBiasModel);
out.NumericTokens=struct();
for name=["MeasuredSINR_dB","ModelSINR_dB","MeasuredEstimatorRatioPerReceiveColumn", ...
        "ModelRatioPerReceiveColumn","PowerDifferencePerReceiveColumn_dB", ...
        "SINRLogRatioDifferencePerReceiveColumn_dB","ReportedPowerDifference_dB", ...
        "SelectedColumnPowerDifference_dB","ReportedSINRLogRatioDifference_dB", ...
        "SelectedColumnSINRLogRatioDifference_dB"]
    out.NumericTokens.(name)=compose('%.17g',out.(name));
end
end

function e=imTerms(grids,support,D,id)
K=size(grids{5},1); L=size(grids{5},2); nrx=size(grids{5},3);
idx=sub2ind([K L],support(:,1)+1,support(:,2)+1);
values=cell(1,4); power=zeros(4,nrx); cross=zeros(6,nrx); pairs=zeros(6,2);
for k=1:4
    flat=reshape(double(grids{k}),K*L,nrx); values{k}=flat(idx,:);
    power(k,:)=mean(abs(values{k}).^2,1);
end
n=0;
for i=1:3
    for j=i+1:4
        n=n+1; pairs(n,:)=[i j]; cross(n,:)=2*real(mean(conj(values{i}).*values{j},1));
    end
end
bound=closure(sum(power,1)+sum(cross,1),D, ...
    sum(abs(power),1)+sum(abs(cross),1)+abs(D),numel(idx),id);
e=struct('PowerPerTermPerReceiveColumn',power,'CrossPairIndices1',pairs, ...
    'SignedCrossPowerPerReceiveColumn',cross,'OriginalTotalPowerPerReceiveColumn',D, ...
    'TargetLeakagePowerPerReceiveColumn',power(1,:),'TargetLeakageSubtracted',false, ...
    'ClosureResidual',D-sum(power,1)-sum(cross,1),'ClosureRoundoffBound',bound);
end
function value=vector(x,count,id)
assert(realArray(x)&&isvector(x)&&numel(x)==count,id,'Retain original finite numeric vectors.');
value=double(x(:).');
end
function tf=realArray(x), tf=isnumeric(x)&&isreal(x)&&~issparse(x)&&all(isfinite(x),'all'); end
function tf=realScalar(x), tf=isnumeric(x)&&isreal(x)&&isscalar(x)&&~issparse(x); end
function tf=scalarEqual(a,b), tf=realScalar(a)&&isfinite(a)&&isequal(double(a),double(b)); end
function tf=vectorEqual(a,b), tf=realArray(a)&&isvector(a)&&isequal(double(a(:)),double(b(:))); end
function tf=textEquals(a,b)
tf=((ischar(a)&&isrow(a))||(isstring(a)&&isscalar(a)&&~ismissing(a)))&&string(a)==string(b);
end
function value=hash(x), value=sixgr.phy.waveform.WaveformHash.runtimeArray(x); end
function moment(a,b,count,id)
assert(isnumeric(a)&&isnumeric(b)&&isequal(size(a),size(b))&&all(isfinite(a),'all')&&all(isfinite(b),'all'), ...
    id,'Original finite moment shape/type changed.');
if isempty(a), return; end
scale=max(realmin('double'),max([abs(double(a(:)));abs(double(b(:)))]));
assert(all(abs(double(a)-double(b))<=128*max(1,count)*eps(scale),'all'),id,'Original projection or moment differs.');
end
function sameSpecial(a,b,id)
assert(isequal(size(a),size(b))&&isequal(isnan(a),isnan(b))&&isequal(isinf(a),isinf(b))&& ...
    all(a(isinf(b))==b(isinf(b))),id,'Original signed ratio differs.');
valid=isfinite(b); moment(a(valid),b(valid),max(1,numel(b)),id);
end
function bound=closure(a,b,operandMagnitude,count,id)
% Forward-error bound, not an accuracy tolerance. Complex dot products,
% squared magnitudes, weighted sums, cross products and division use at most
% this conservative real-operation count on each scalar dependency path.
% Absolute original products/terms retain the conditioning information that
% is lost when a physical cancellation leaves a nearly zero final residual.
assert(isequal(size(a),size(b),size(operandMagnitude))&& ...
    all(isfinite(a),'all')&&all(isfinite(b),'all')&& ...
    all(isfinite(operandMagnitude),'all')&&all(operandMagnitude>=0,'all'),id, ...
    'Finite original closure operands and magnitudes are required.');
operations=16*double(count)+64; u=eps('double')/2;
assert(operations*u<1,id,'Arithmetic operation count exceeds the supported roundoff bound.');
gamma=operations*u/(1-operations*u);
bound=gamma*max(realmin('double'),abs(a)+abs(b)+operandMagnitude);
assert(all(abs(a-b)<=bound,'all'),id, ...
    'Original component closure differs beyond its operand-conditioned arithmetic roundoff bound.');
end
function y=positiveLog(x), y=nan(size(x)); hit=x>0; y(hit)=10*log10(x(hit)); end
function [value,col]=maximum(x)
[value,col]=max(x,[],'omitnan'); if isempty(value)||isnan(value), value=NaN; col=NaN; end
end
function d=finiteDifference(a,b), d=NaN; if isfinite(a)&&isfinite(b), d=a-b; end; end
function d=selectedDifference(values,col), d=NaN; if isfinite(col), d=values(col); end; end
