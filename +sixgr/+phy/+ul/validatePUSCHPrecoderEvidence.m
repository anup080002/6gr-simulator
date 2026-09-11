function prec=validatePUSCHPrecoderEvidence(tx)
% Validate applied evidence solely against the transmitter-owned objects.
% No grant/config request can stand in for missing transmitter metadata.
if ~isstruct(tx) || ~isscalar(tx) || ~isfield(tx,'PUSCH') || ...
        ~isa(tx.PUSCH,'nrPUSCHConfig') || ~isfield(tx,'PrecodeInfo') || ...
        ~isstruct(tx.PrecodeInfo) || ~isscalar(tx.PrecodeInfo)
    error('sixgr:phy:ul:MissingTransmitterPrecoderEvidence', ...
        'Applied precoder evidence requires the actual PUSCH object and PrecodeInfo.');
end
prec=tx.PrecodeInfo; pusch=tx.PUSCH;
required={'Source','Mode','ApplicationStage','Active','ExplicitBeamWeightsApplied', ...
    'TransformPrecodingApplied','BeamformingApplied','NativeCodebookApplied', ...
    'PMI','PMIType','CodebookMode','MatrixPorts','MatrixLogicalPorts', ...
    'NumPorts','NumLogicalPorts','NumLayers','MatrixRows','MatrixCols','BeamIndices', ...
    'CodebookPortIndices1Based','CodebookPortIndexDefinition'};
if ~all(isfield(prec,required))
    error('sixgr:phy:ul:MissingTransmitterPrecoderEvidence', ...
        'Transmitter PrecodeInfo is incomplete; applied values cannot come from a grant.');
end
W=prec.MatrixPorts; logicalW=prec.MatrixLogicalPorts;
validateattributes(W,{'numeric'},{'2d','nonempty','finite'});
validateattributes(logicalW,{'numeric'},{'2d','nonempty','finite'});
if ~isequal(size(W),[prec.NumPorts prec.NumLayers]) || ...
        ~isequal(size(W),[prec.MatrixRows prec.MatrixCols]) || ...
        ~isequal(size(logicalW),[prec.NumLogicalPorts pusch.NumLayers]) || prec.NumLayers~=pusch.NumLayers || ...
        logical(prec.TransformPrecodingApplied)~=logical(pusch.TransformPrecoding)
    error('sixgr:phy:ul:TransmitterPrecoderMismatch', ...
        'Applied precoder dimensions/transform mode differ from the actual PUSCH.');
end
for name={'Active','ExplicitBeamWeightsApplied','TransformPrecodingApplied','BeamformingApplied','NativeCodebookApplied'}
    flag=prec.(name{1});
    if ~((islogical(flag)||isnumeric(flag)) && isscalar(flag) && isreal(flag) && isfinite(flag) && (flag==0||flag==1))
        error('sixgr:phy:ul:TransmitterPrecoderMismatch','Applied-state flags must be explicit scalar booleans.');
    end
end
for name={'Source','Mode','ApplicationStage'}
    value=string(prec.(name{1}));
    if ~isscalar(value) || ismissing(value) || strlength(strtrim(value))==0
        error('sixgr:phy:ul:MissingTransmitterPrecoderEvidence','Transmitter source/stage must be explicit.');
    end
end
native=strcmpi(string(pusch.TransmissionScheme),'codebook');
if logical(prec.NativeCodebookApplied)~=native
    error('sixgr:phy:ul:TransmitterPrecoderMismatch','Native-codebook evidence conflicts with the transmitter.');
end
if native
    if ~isequal(double(prec.PMI),double(pusch.TPMI))
        error('sixgr:phy:ul:TransmitterPrecoderMismatch','Applied TPMI differs from the actual PUSCH TPMI.');
    end
    [expected,~]=sixgr.phy.ul.puschCodebookProjectionMatrix( ...
        pusch.NumLayers,pusch.NumAntennaPorts,pusch.TPMI,pusch.TransformPrecoding);
    if ~isequal(size(logicalW),size(expected)) || ...
            norm(double(logicalW)-double(expected),'fro')>1e-12
        error('sixgr:phy:ul:TransmitterPrecoderMismatch','Logical precoder differs from the transmitted codebook.');
    end
    ports=find(sum(abs(double(logicalW)).^2,2)>0).';
    if ~isequal(double(prec.CodebookPortIndices1Based),ports) || ...
            string(prec.CodebookPortIndexDefinition)~="one_based_logical_antenna_port_support_not_spatial_beam_ID"
        error('sixgr:phy:ul:TransmitterPrecoderMismatch','Codebook port-support evidence differs from the matrix.');
    end
elseif ~isempty(prec.PMI) && ~all(isnan(prec.PMI))
    error('sixgr:phy:ul:TransmitterPrecoderMismatch','Non-codebook mapping cannot claim an applied TPMI.');
end
actualHash=string(sixgr.phy.mimo.MatrixContract.digest(double(W)));
declaredHash=string(sixgr.util.structGet(prec,'AppliedMatrixSHA256',""));
if strlength(declaredHash)>0 && ~strcmpi(declaredHash,actualHash)
    error('sixgr:phy:ul:TransmitterPrecoderMismatch','Applied matrix digest contradicts transmitter matrix samples.');
end
prec.AppliedMatrixSHA256=actualHash;
end
