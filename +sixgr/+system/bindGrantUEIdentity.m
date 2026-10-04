function grants=bindGrantUEIdentity(grants,states,cellID)
% Associate frozen physical RNTIs with internal UE indices without rewriting IQ identity.
if isempty(grants), return; end
assert(isstruct(states) && all(isfield(states,{'RNTI','UEIndex'})), ...
    'sixgr:system:MissingUEIdentity','Scheduling states must carry protocol and internal identities.');
rntis=double([states.RNTI]); indices=double([states.UEIndex]);
assert(numel(unique(rntis))==numel(rntis) && numel(unique(indices))==numel(indices), ...
    'sixgr:system:AmbiguousUEIdentity','UE and RNTI identities must be unique within a serving cell.');
validateattributes(indices,{'numeric'},{'integer','finite','positive'});
validateattributes(rntis,{'numeric'},{'integer','finite','positive','<=',65535});
if ~isfield(grants,'UEIndex')
    [grants.UEIndex]=deal(NaN);
end
for k=1:numel(grants)
    matches=find(rntis==grants(k).RNTI);
    assert(isscalar(matches),'sixgr:system:UnknownGrantUE','Grant RNTI is absent from its cell scheduling population.');
    u=indices(matches);
    old=sixgr.util.structGet(grants(k),'UEIndex',NaN);
    assert(isscalar(old) && (isnan(old)||old==u), ...
        'sixgr:system:GrantUEIdentityMismatch','A frozen grant cannot change its UE owner.');
    grants(k).UEIndex=u;
    grants(k).SystemServingCellID=cellID;
end
end
