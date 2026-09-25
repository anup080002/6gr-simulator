function token=encodeCSIReportAudit(fields)
%ENCODECSIREPORTAUDIT Persist decoded fields without losing complex weights.
% Audit only. Reconstruct scheduler CSI from the actual received Part-1 and
% Part-2 bits and installed report configuration, not this JSON view.
assert(isstruct(fields) && isscalar(fields), ...
    'sixgr:mimo:InvalidCSIReportAudit','Decoded CSI fields must be a scalar structure.');
if isfield(fields,'Precoder_W')
    assert(~any(isfield(fields,{'PrecoderMatrixToken','PrecoderMatrixSHA256'})), ...
        'sixgr:mimo:InvalidCSIReportAudit','Do not overwrite a competing precoder identity.');
    W=fields.Precoder_W;
    fields.PrecoderMatrixToken=sixgr.phy.mimo.MatrixContract.serialize(W);
    fields.PrecoderMatrixSHA256=sixgr.phy.mimo.MatrixContract.digest(double(W));
    fields=rmfield(fields,'Precoder_W');
end
token=string(jsonencode(fields));
end
