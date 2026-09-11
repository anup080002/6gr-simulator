function score=pilotChannelNMSE(estimate,reference,indices)
% Independent per-resource, per-RX, per-port error; never fit gain or phase.
validateattributes(indices,{'numeric'},{'nonempty','finite','integer','positive'});
assert(isequal(size(estimate),size(reference)) && ndims(estimate)<=4 && ...
    ~isempty(estimate),'sixgr:srs:ChannelReferenceShapeMismatch', ...
    'Estimated and independent channel grids must have identical K/L/RX/port dimensions.');
K=size(estimate,1); L=size(estimate,2); R=size(estimate,3); P=size(estimate,4);
assert(all(indices(:)<=K*L*P),'sixgr:srs:PilotReferenceOutOfRange', ...
    'Every pilot index must belong to the actual transmit port grid.');
[k,l,p]=ind2sub([K L P],double(indices(:)));
assert(numel(unique(indices(:)))==numel(indices), ...
    'sixgr:srs:DuplicatePilotReference','Do not count the same port resource twice.');
sampledEstimate=complex(zeros(numel(k),R)); sampledReference=sampledEstimate;
for r=1:R
    at=sub2ind([K L R P],k,l,repmat(r,size(k)),p);
    sampledEstimate(:,r)=estimate(at); sampledReference(:,r)=reference(at);
end
assert(all(isfinite(sampledEstimate(:))) && all(isfinite(sampledReference(:))), ...
    'sixgr:srs:IncompletePilotChannelReference','Every scored pilot/branch must be finite; no masking or truncation.');
errorEnergy=sum(abs(sampledEstimate-sampledReference).^2,'all');
referenceEnergy=sum(abs(sampledReference).^2,'all');
assert(referenceEnergy>0 && isfinite(referenceEnergy) && isfinite(errorEnergy), ...
    'sixgr:srs:InvalidPilotReferenceEnergy','Independent reference energy must be positive and complete.');
perPort=nan(R,P);
for port=1:P
    selected=p==port;
    assert(any(selected),'sixgr:srs:UnobservedSRSPort','Every configured SRS port needs actual pilot evidence.');
    denominator=sum(abs(sampledReference(selected,:)).^2,1);
    numerator=sum(abs(sampledEstimate(selected,:)-sampledReference(selected,:)).^2,1);
    perPort(:,port)=(numerator./denominator).';
end
score=struct('Linear',errorEnergy/referenceEnergy, ...
    'dB',10*log10(errorEnergy/referenceEnergy),'ErrorEnergy',errorEnergy, ...
    'ReferenceEnergy',referenceEnergy,'PilotResourceCount',numel(k), ...
    'ComparedComplexValueCount',numel(sampledEstimate),'NumReceiveAntennas',R, ...
    'NumSRSPorts',P,'PerReceiveAntennaPortLinear',perPort, ...
    'GainOrPhaseFitted',false,'MissingValuesDiscarded',false,'Available',true);
end
