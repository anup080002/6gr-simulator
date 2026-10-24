function reference=linearPAReferenceCoefficients(profile)
%LINEARPAREFERENCECOEFFICIENTS Declared fixed first-order PA reference.
% Input is the explicit profile supplied to the original PA owner, not a
% configuration from which this helper resolves defaults. A profile ALONE
% does not prove that an RF interval executed it. Later owner binding must
% establish that provenance separately.
%
% Taps operate on PA input BEFORE input backoff. Backoff is included ONCE:
% rapp: g; saleh: AlphaAM*g; memory polynomial: sum(c(order==1,:),1)*g,
% g=10^(-InputBackoff_dB/20). No fitted/trajectory-conditioned gain, output
% power restoration, RF execution or unique nonlinear per-port attribution.

id='RF:InvalidLinearPAReferenceProfile';
assert(isstruct(profile)&&isscalar(profile),id,'Supply one explicit PA profile.');
required={'ProfileID','Version','Model','ReferenceDomain','InputBackoff_dB'};
assert(all(isfield(profile,required)),id, ...
    'Explicit PA identity, version, model, reference domain and input backoff are required.');
profileID=localText(profile.ProfileID,id,'ProfileID');
versionID=localText(profile.Version,id,'Version');
declaredModel=localText(profile.Model,id,'Model');
domain=localText(profile.ReferenceDomain,id,'ReferenceDomain');
model=lower(strtrim(declaredModel));
assert(any(model==["rapp","saleh","memory_polynomial"]), ...
    'RF:UnsupportedLinearPAReferenceModel', ...
    'No fixed first-order contract is installed for PA model %s.',model);
backoff=localReal(profile.InputBackoff_dB,id,'InputBackoff_dB');
gain=10^(-backoff/20);
assert(isfinite(gain)&&gain>0,id, ...
    'Input backoff must have a finite positive representable amplitude gain.');
parameters=struct('ProfileID',profileID,'Version',versionID,'Model',declaredModel, ...
    'ReferenceDomain',domain,'InputBackoff_dB',backoff);
orders=zeros(0,1); depth=1; present=true;
switch model
    case "rapp"
        smoothness=localField(profile,'Smoothness',id);
        saturation=localField(profile,'SaturationAmplitude',id);
        assert(smoothness>0&&saturation>0,id, ...
            'Original Rapp smoothness and saturation amplitude must be positive.');
        firstOrder=1;
        parameters.Smoothness=smoothness;
        parameters.SaturationAmplitude=saturation;
        source="rapp_origin_first_order_unit_gain_before_input_backoff";
    case "saleh"
        alphaAM=localField(profile,'AlphaAM',id);
        betaAM=localField(profile,'BetaAM',id);
        alphaPM=localField(profile,'AlphaPM',id);
        betaPM=localField(profile,'BetaPM',id);
        % Finite negative beta is accepted by the original PA kernel. Its
        % derivative at zero is still AlphaAM; poles/global operating range
        % are not certified by this fixed origin-reference calculation.
        firstOrder=alphaAM;
        parameters.AlphaAM=alphaAM; parameters.BetaAM=betaAM;
        parameters.AlphaPM=alphaPM; parameters.BetaPM=betaPM;
        source="saleh_origin_AlphaAM_gain_zero_first_order_AM_PM";
    case "memory_polynomial"
        assert(all(isfield(profile,{'Coefficients','Orders','MemoryDepth'})),id, ...
            'Original coefficients, orders and memory depth are all required.');
        depth=localReal(profile.MemoryDepth,id,'MemoryDepth');
        assert(depth>=1&&depth==fix(depth),id,'MemoryDepth must be a positive integer.');
        orders=profile.Orders;
        assert(isnumeric(orders)&&isreal(orders)&&isvector(orders)&&~isempty(orders) && ...
            all(isfinite(orders(:)))&&all(orders(:)>=1)&& ...
            all(orders(:)==fix(orders(:))),id, ...
            'Polynomial orders must be positive integers in original row order.');
        coefficients=profile.Coefficients;
        assert(isnumeric(coefficients)&&ismatrix(coefficients)&&~isempty(coefficients) && ...
            all(isfinite(coefficients(:))),id, ...
            'Original complex coefficients must be a finite nonempty matrix.');
        % Match PAProfile.apply / RFImpairmentStream's existing D=1 vector
        % convention, without transposing a one-order, multi-tap row.
        normalized=double(coefficients);
        if isvector(normalized)&&depth==1&&numel(normalized)==numel(orders)
            normalized=normalized(:);
        end
        assert(size(normalized,1)==numel(orders)&&size(normalized,2)==depth,id, ...
            'Coefficient rows are original polynomial orders; columns are delays 0..D-1.');
        one=find(double(orders(:))==1);
        present=~isempty(one);
        firstOrder=complex(zeros(1,depth));
        if present, firstOrder=sum(normalized(one,:),1); end
        % Hash the original shape/class/real/imag operands, not jsonencode
        % of a complex matrix. Preserve the original order vector as given.
        parameters.CoefficientsSHA256=localHash(coefficients);
        parameters.CoefficientsClass=string(class(coefficients));
        parameters.CoefficientsSize=size(coefficients);
        parameters.OrdersSHA256=localHash(orders);
        parameters.OrdersClass=string(class(orders));
        parameters.OrdersSize=size(orders);
        parameters.Orders=double(orders);
        parameters.MemoryDepth=depth;
        source="sum_original_order_one_coefficient_rows_before_input_backoff";
        if ~present, source="no_declared_order_one_zero_linear_reference"; end
end
taps=firstOrder.*gain;
assert(all(isfinite(taps(:))),id,'The declared first-order coefficient calculation overflowed.');
parameterJSON=string(jsonencode(parameters));
reference=struct('ContractVersion',"sixgr.rf.fixed_linear_PA_reference/v1", ...
    'ReferenceModel',"fixed_declared_first_order_PA", ...
    'LinearizationScope',"origin_derivative_not_global_PA_operating_range_validation", ...
    'Source',source,'ProfileID',profileID,'Version',versionID,'PAModel',model, ...
    'ReferenceDomain',domain, ...
    'InputPlane',"PA_input_before_original_input_backoff", ...
    'OutputPlane',"declared_linear_PA_output_before_downstream_TX_stages", ...
    'InputBackoff_dB',backoff,'InputBackoffAmplitudeGain',gain, ...
    'InputBackoffIncluded',true,'AdditionalBackoffApplicationsRequired',0, ...
    'MemoryDepth',depth,'TapDelaysSamples0',0:depth-1, ...
    'OriginalPolynomialOrders',orders,'DeclaredOrderOnePresent',present, ...
    'TapsBeforeInputBackoff',firstOrder,'LinearTaps',taps, ...
    'LinearTapsSHA256',localHash(taps), ...
    'ConsumedProfileParameters',parameters, ...
    'ConsumedProfileParametersJSON',parameterJSON, ...
    'ConsumedProfileParametersSHA256',sixgr.util.sha256Hex(char(parameterJSON)), ...
    'ParameterHashScope',"explicit_consumed_model_parameters_not_entire_profile_or_execution", ...
    'NumericHashSerialization',"WaveformHash.runtimeArray_class_dimensions_real_imag_double", ...
    'OriginalRFExecutionBound',false,'CoefficientsFittedFromSamples',false, ...
    'OperatingTrajectoryConditioned',false,'ActualNonlinearPerPortOutput',false, ...
    'HardwareQualified',false,'StandardizedPowerAccuracyQualified',false, ...
    'ReferenceUsedByReceiver',false,'AdditionalRFExecutions',0, ...
    'AdditionalChannelExecutions',0);
end

function value=localText(value,id,name)
assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)),id, ...
    'Profile %s must be scalar text.',name);
value=string(value);
assert(~ismissing(value)&&strlength(strtrim(value))>0,id, ...
    'Profile %s must be explicitly nonblank.',name);
end
function value=localReal(value,id,name)
assert(isnumeric(value)&&isreal(value)&&isscalar(value)&&isfinite(value),id, ...
    'Profile %s must be a finite real numeric scalar.',name);
value=double(value);
end
function value=localField(profile,name,id)
assert(isfield(profile,name),id,'Missing original PA parameter %s.',name);
value=localReal(profile.(name),id,name);
end
function digest=localHash(value)
digest=string(sixgr.phy.waveform.WaveformHash.runtimeArray(value));
end
