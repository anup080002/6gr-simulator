function unit = appliedWaveformAmplitudeUnit(cfg, context)
%APPLIEDWAVEFORMAMPLITUDEUNIT Validate the executed TX amplitude contract.
% This validates metadata only: it must never rescale samples, infer power
% from payloads, or convert normalized fixed-Es samples into absolute power.
required = {'WaveformAmplitudeUnit','FixedSNRNormalizedReference', ...
    'PhysicalDevicePowerClaim','ScaleApplied','AmplitudeScale'};
valid = isstruct(context) && isscalar(context) && ...
    all(isfield(context,required));
if ~valid
    localMismatch('An applied TX power context with explicit unit and scaling authority is required.');
end
raw = context.WaveformAmplitudeUnit;
if ~(ischar(raw) && isrow(raw)) && ~(isstring(raw) && isscalar(raw))
    localMismatch('The waveform amplitude unit must be one scalar text value.');
end
unit = string(raw);
if ismissing(unit) || strlength(unit)==0
    localMismatch('The waveform amplitude unit cannot be missing.');
end
for name = ["FixedSNRNormalizedReference","PhysicalDevicePowerClaim","ScaleApplied"]
    value = context.(name);
    if ~((islogical(value) || isnumeric(value)) && isscalar(value) && ...
            isreal(value) && isfinite(value) && any(value==[0 1]))
        localMismatch('Applied power-domain flags must be scalar logical values.');
    end
end
scale = context.AmplitudeScale;
if ~(isnumeric(scale) && isscalar(scale) && isreal(scale) && ...
        isfinite(scale) && scale>=0)
    localMismatch('Applied waveform amplitude scale must be finite and nonnegative.');
end
normalized = sixgr.rf.isNormalizedFixedSNRPowerReference(cfg);
if normalized
    valid = unit=="normalized_complex_baseband" && ...
        context.FixedSNRNormalizedReference && ~context.PhysicalDevicePowerClaim && ...
        ~context.ScaleApplied && scale==1;
else
    valid = unit=="sqrt_mW" && ~context.FixedSNRNormalizedReference && ...
        context.PhysicalDevicePowerClaim && context.ScaleApplied;
end
if ~valid
    localMismatch('Applied waveform units/scaling disagree with the configured normalized or absolute power domain.');
end
end

function localMismatch(message)
error('sixgr:rf:WaveformAmplitudeAuthorityMismatch','%s',message);
end
