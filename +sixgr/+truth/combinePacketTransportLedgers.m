function [T,initialCount]=combinePacketTransportLedgers(state)
% Initial byte ownership and recovery transmissions stay distinct at rest.
A=sixgr.util.structGet(state,'PacketSDULedgerTable',table());
B=sixgr.util.structGet(state,'RLCRecoveryTransportLedgerTable',table());
assert(istable(A)&&istable(B),'sixgr:protocol:InvalidTransportLedger','Typed actual transport ledgers required.');
initialCount=height(A);
if isempty(B),T=A;return;end
if isempty(A),T=B;return;end
for name=string(B.Properties.VariableNames)
    if ~ismember(name,A.Properties.VariableNames),A.(name)=emptyLike(B.(name),height(A));end
end
for name=string(A.Properties.VariableNames)
    if ~ismember(name,B.Properties.VariableNames),B.(name)=emptyLike(A.(name),height(B));end
end
T=[A;B(:,A.Properties.VariableNames)];
end
function value=emptyLike(example,n)
if isstring(example),value=repmat("",n,size(example,2));
elseif islogical(example),value=false(n,size(example,2));
elseif isnumeric(example),value=nan(n,size(example,2),'like',example);
elseif iscell(example),value=cell(n,size(example,2));
else,error('sixgr:protocol:InvalidTransportLedger','Unsupported transport evidence column type.');end
end
