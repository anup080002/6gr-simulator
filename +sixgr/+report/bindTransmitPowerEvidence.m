function row=bindTransmitPowerEvidence(row,context)
% Export the applied numerical reference without changing internal RF units.
arguments
    row (1,1) struct
    context (1,1) struct
end
targets=["ReferenceInputPower","ReferenceOutputPower","ActualEmittedPower"];
sources=["ReferenceInputPower_dBm","ReferenceOutputPower_dBm","OutputTotalPower_dBm"];
for name=targets
    row.(name+"_dBm")=NaN;
    row.(name+"_dB_re_UnitOccupiedRE_Es")=NaN;
end
row.PowerContextTotalTxPower_dB_re_UnitOccupiedRE_Es=NaN;
row.TransmitPowerEvidenceAvailable=false;
row.TransmitPowerPhysicalApplicable=false;
row.TransmitPowerReferencePlane="unavailable";
if isempty(fieldnames(context)), return; end
required=[sources,"FixedSNRNormalizedReference","PhysicalDevicePowerClaim","PowerNormalizationPolicy"];
assert(all(isfield(context,required)), 'sixgr:report:MissingTransmitPowerDomain', ...
    'An applied power ledger must explicitly identify physical versus normalized reference.');
flags=["FixedSNRNormalizedReference","PhysicalDevicePowerClaim"];
for name=flags
    value=context.(name);
    assert((islogical(value)||isnumeric(value)) && isscalar(value) && isreal(value) && ...
        isfinite(value) && (value==0 || value==1), ...
        'sixgr:report:InvalidTransmitPowerDomain','Power domain flags must be explicit binary scalars.');
end
normalized=logical(context.FixedSNRNormalizedReference);
physical=logical(context.PhysicalDevicePowerClaim);
policy=string(context.PowerNormalizationPolicy);
assert(isscalar(policy) && ~ismissing(policy) && strlength(policy)>0 && ...
    normalized~=physical && normalized==(policy=="unit_occupied_re_fixed_esn0"), ...
    'sixgr:report:ConflictingTransmitPowerDomain','Power reference flags and applied normalization policy must agree.');
if normalized
    assert(isfield(context,'FixedSNRReferenceEnergyPerOccupiedRE') && ...
        isequal(context.FixedSNRReferenceEnergyPerOccupiedRE,1), ...
        'sixgr:report:UnsupportedNormalizedPowerReference','The relative export requires the declared unit occupied-RE energy.');
    row.TransmitPowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es";
else
    row.TransmitPowerReferencePlane="physical_transmit_waveform_power_reference";
end
values=NaN(1,numel(sources));
for index=1:numel(sources)
    value=context.(sources(index));
    assert(isnumeric(value) && isscalar(value) && isreal(value) && ~isinf(value), ...
        'sixgr:report:InvalidTransmitPowerValue','Retain a scalar measured value or explicit NaN.');
    values(index)=double(value);
    suffix="_dBm";
    if normalized, suffix="_dB_re_UnitOccupiedRE_Es"; end
    row.(targets(index)+suffix)=values(index);
end
% This existing field is a replay-ledger value, not necessarily emitted power.
% Preserve its value/reference distinction rather than substituting a TX value.
if normalized && isfield(row,'PowerContextTotalTxPower_dBm')
    value=row.PowerContextTotalTxPower_dBm;
    assert(isnumeric(value) && isscalar(value) && isreal(value) && ~isinf(value), ...
        'sixgr:report:InvalidTransmitPowerValue','Retain the scalar replay power value or NaN.');
    row.PowerContextTotalTxPower_dB_re_UnitOccupiedRE_Es=value;
    row.PowerContextTotalTxPower_dBm=NaN;
end
row.TransmitPowerPhysicalApplicable=physical;
row.TransmitPowerEvidenceAvailable=all(isfinite(values));
end
