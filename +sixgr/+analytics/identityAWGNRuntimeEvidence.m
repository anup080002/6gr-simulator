function ok=identityAWGNRuntimeEvidence(T,cfg,nTx,nRx)
% Classify declared identity/fixed-matrix AWGN dimensions, not array patterns.
% This validates retained metadata; it does not independently qualify IQ.
ok=false;
matrix=sixgr.util.structGet(cfg,'channel.awgnSpatialMatrixDL',[]);
fixedMatrix=~isempty(matrix);
if ~istable(T) || isempty(T) || ...
        (~isequal(sixgr.util.structGet(cfg,'channel.sharedIdentityAWGNEnabled',false),true) && ~fixedMatrix) || ...
        ~isscalar(nTx) || ~isscalar(nRx) || ~isfinite(nTx) || ...
        ~isfinite(nRx) || nTx<1 || nRx<1 || nTx~=fix(nTx) || nRx~=fix(nRx), return; end
if fixedMatrix
    if ~isnumeric(matrix) || ~all(isfinite(matrix),'all') || ...
            ~(isequal(size(matrix),[nRx nTx]) || isequal(size(matrix),[nTx nRx])), return; end
elseif nTx~=nRx
    return;
end
textFields=["ChannelModel","ChannelModelApplied","ChannelArrayModel", ...
    "ChannelObjectSource","ChannelObjectClass","ChannelArrayHandlingStatus", ...
    "ElementPatternChannelApplicability"];
expected=["AWGN","AWGN","awgn_no_array_channel", ...
    "sixgr.channel.IdentityAWGNRuntime.materialize","explicit_identity_sample_operator", ...
    "awgn_identity_spatial_dimensions_no_array_kernel","not_applicable_awgn_identity_channel"];
if fixedMatrix
    expected(5:7)=["explicit_fixed_matrix_sample_operator", ...
        "awgn_configured_spatial_matrix_no_array_kernel","not_applicable_awgn_fixed_matrix_channel"];
end
dimensions=["ConfiguredTxAntennas","ConfiguredRxAntennas", ...
    "PhysicalTxAntennas","PhysicalRxAntennas","TxWaveformColumns","RxWaveformBranches"];
notApplied=["ChannelUsesSameRuntimeAntennaAssumptions","ChannelUsesCountOnlyAntennaModel", ...
    "TransmitElementPatternApplied","ReceiveElementPatternApplied"];
required=[textFields dimensions notApplied "Rank"];
if ~all(ismember(required,string(T.Properties.VariableNames))), return; end
for k=1:numel(textFields)
    tokens=string(T.(textFields(k)));
    if ~iscolumn(tokens) || any(ismissing(tokens)) || ...
            ~all(strcmpi(strtrim(tokens),expected(k))), return; end
end
for name=dimensions
    x=T.(name);
    dimension=nTx;
    if contains(name,"Rx"), dimension=nRx; end
    if ~isnumeric(x) || ~isreal(x) || ~iscolumn(x) || ...
            ~all(isfinite(x) & x==dimension), return; end
end
for name=notApplied
    x=T.(name);
    if ~(isnumeric(x)||islogical(x)) || ~isreal(x) || ~iscolumn(x) || ...
            ~all(isfinite(x) & x==0), return; end
end
rank=T.Rank;
if ~isnumeric(rank) || ~isreal(rank) || ~iscolumn(rank) || ...
        ~all(isfinite(rank) & rank==fix(rank) & rank>=1 & rank<=min(nTx,nRx)), return; end
if ismember('Layers',T.Properties.VariableNames) && ~isequaln(T.Layers,rank), return; end
ok=true;
end
