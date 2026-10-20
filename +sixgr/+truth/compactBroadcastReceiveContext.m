function context=compactBroadcastReceiveContext(context)
% Remove unused duplicate preparation owners, not samples or measurements.
% Shared completion uses Context.Prepared and the actually received planes.
% Standalone runCellSearch_MIB_SIB1 retains its separate RuntimeTx contract.
assert(isstruct(context) && isscalar(context) && isfield(context,'Prepared'), ...
    'sixgr:truth:BroadcastContextRequired','A frozen shared broadcast context is required.');
p=context.Prepared;
assert(isstruct(p) && isfield(p,'TransmitSamples') && isfield(p,'Tx') && ...
    size(p.TransmitSamples,1)==p.NumSamples, ...
    'sixgr:truth:BroadcastPreparationRequired','Retain exact frozen broadcast samples and TX evidence.');
if isfield(context,'Prototype') && isfield(context.Prototype,'PreparedBroadcast')
    % Do not replace or reconstruct any samples. The receiver context already
    % binds the same preparation; this nested copy is not a decoder input.
    nested=context.Prototype.PreparedBroadcast;
    assert(isequaln(nested.TransmitSamples,p.TransmitSamples) && ...
        isequaln(nested.Tx,p.Tx),'sixgr:truth:BroadcastDuplicateMismatch', ...
        'Distinct preparations must not be silently merged.');
    context.Prototype=rmfield(context.Prototype,'PreparedBroadcast');
end
if isfield(p,'RuntimeTx')
    assert(isequaln(p.RuntimeTx.Waveform,p.TransmitSamples), ...
        'sixgr:truth:BroadcastRuntimeTXMismatch','Runtime TX and frozen samples must agree exactly.');
    p=rmfield(p,'RuntimeTx');
end
% TxInfo.PortGrid was consumed by applyPowerContext during preparation.
% Actual mapped grids remain in p.Tx for resource and measurement scoring.
if isfield(p,'TxInfo') && isfield(p.TxInfo,'PortGrid')
    p.TxInfo=rmfield(p.TxInfo,'PortGrid');
end
context.Prepared=p;
end
