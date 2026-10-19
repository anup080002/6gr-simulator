function T=bindTransportExportIdentity(T,tbId,grantId,process,ndiEpoch)
% Export existing frozen identities; never synthesize a TB ID from row index.
n=height(T);
T.TBId=localColumn(string(tbId),n);
T.LogicalTBID=T.TBId;
T.TransmissionAttemptID=localColumn(string(grantId),n);
T.HARQProcess=localColumn(double(process),n);
T.NDIEpoch=localColumn(double(ndiEpoch),n);
T.IdentityContractVersion=repmat("TransportIdentity/v2",n,1);
T.AttemptIdentitySource=repmat("frozen_grant_context_id",n,1);
missing=ismissing(T.TransmissionAttemptID) | strlength(T.TransmissionAttemptID)==0;
T.AttemptIdentitySource(missing)="unavailable_no_frozen_grant_context";
end
function value=localColumn(value,n)
if isscalar(value), value=repmat(value,n,1); else, value=value(:); end
assert(numel(value)==n,'sixgr:link:TransportIdentityShape','One owning identity per row is required.');
end
