function digest = harqContextDigest(context)
%HARQCONTEXTDIGEST Installed HARQ identity, distinct from one DCI's beam.
% TS 38.321 5.3.2/5.4.2 associate HARQ with the serving cell and process,
% not the currently selected TCI state. Keep the full DCI digest for exact
% received-assignment validation. Exclude ONLY the active beam selection
% from this connected-profile lifetime identity; epoch, RNTI, cells/BWPs,
% MCS tables, reference-signal configuration and all other fields remain.
assert(isa(context,'sixgr.phy.pdcch.DCIContext') && isscalar(context), ...
    'sixgr:phy:pdcch:InvalidHARQContext','Require a validated DCI context.');
data = context.Data;
if ~isfield(data,'ConnectedPolicy')
    digest = context.Digest; % Legacy profiles retain exact-context checking.
    return;
end
data = rmfield(data,'ActiveTCIStateID');
digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
    'Contract',"connected_harq_context/v1",'InstalledContext',data));
end
