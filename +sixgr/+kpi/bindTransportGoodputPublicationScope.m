function T=bindTransportGoodputPublicationScope(T,identity)
%BINDTRANSPORTGOODPUTPUBLICATIONSCOPE Add publisher identity without recredit.
% The lifecycle publisher supplies and validates the immutable run identity.
% Verify the original CRC/TB/experiment credit first, then bind only late
% publication labels. Never drop scientific scope or recompute delivered bits.
if ~istable(T)||isempty(T)||~ismember('UniqueDeliveredTBBits',T.Properties.VariableNames)
    return;
end
fields=["RunId","RunID","ExecutionID","ConfigHash"];
original=string(T.TransportGoodputKey);
for i=1:height(T)
    proof=T(i,:);
    key=original(i);
    keyScope=struct();
    if ~ismissing(key)&&strlength(key)>0
        if startsWith(key,"FIXED|"), key=extractAfter(key,"FIXED|"); end
        keyScope=jsondecode(key);
        assert(isstruct(keyScope)&&isscalar(keyScope),'sixgr:kpi:InvalidTransportGoodputCredit');
    end
    for field=fields
        if ~ismember(field,string(T.Properties.VariableNames)), continue; end
        canonical=field; if field=="RunId", canonical="RunID"; end
        assert(isfield(identity,canonical) && ...
            string(T.(field)(i))==string(identity.(canonical)), ...
            'sixgr:kpi:TransportGoodputPublicationIdentityMismatch', ...
            'Late scope binding requires the immutable publisher %s.',canonical);
        if ~isfield(keyScope,field)
            proof=removevars(proof,field);
        end
    end
    sixgr.kpi.transportGoodputBits(proof);
end
derived=sixgr.kpi.creditTransportGoodput(T);
if ~ismember("TransportGoodputPrePublicationKey",string(T.Properties.VariableNames))
    T.TransportGoodputPrePublicationKey=original;
end
T.TransportGoodputKey=derived.TransportGoodputKey;
T.TransportGoodputScopeBinding=repmat( ...
    "validated_original_credit_then_immutable_publication_identity_no_recredit",height(T),1);
sixgr.kpi.transportGoodputBits(T);
end
