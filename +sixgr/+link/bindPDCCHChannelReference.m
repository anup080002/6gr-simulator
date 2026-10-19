function T=bindPDCCHChannelReference(T,paired)
% Exact coordinate join; data-RE estimates do not invent pilot truth values.
T.NMSECompared=false(height(T),1);
for field=["ReferenceHReal","ReferenceHImag","ChannelErrorEnergy","ChannelReferenceEnergy"]
    T.(field)=nan(height(T),1);
end
if isempty(paired), return; end
keys={'SubcarrierIndex0','SymbolIndex0','RxPortIndex0','ReferencePortIndex0'};
assert(height(unique(T(:,keys),'rows'))==height(T) && ...
    height(unique(paired(:,keys),'rows'))==height(paired), ...
    'sixgr:link:AmbiguousPDCCHReferenceCoordinates','Do not merge repeated pilot hypotheses.');
[found,index]=ismember(paired(:,keys),T(:,keys),'rows');
assert(all(found) && all(T.IsDMRS(index)), ...
    'sixgr:link:MissingPDCCHReferenceCoordinates','Every scored pilot must join its actual receiver estimate.');
T.NMSECompared(index)=true;
for field=["ReferenceHReal","ReferenceHImag","ChannelErrorEnergy","ChannelReferenceEnergy"]
    T.(field)(index)=paired.(field);
end
end
