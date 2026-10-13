function T=bindIndependentREObservation(T)
% Preserve the identity of each independently executed waveform observation.
% Never join independent users, SNR points or trials into a shared TX grid.
% Coordinates and allocation identity remain those of the executed producer.
assert(istable(T),'sixgr:truth:InvalidObservedRETable','Expected executed RE rows.');
if isempty(T), return; end
% A cell-owned CSI-RS in a PDSCH waveform has ue_id=NaN. Retain that
% ownership while binding it to the same actually executed observation.
keys=["direction","cell_id","ObservationUEIndex","ConfiguredSNR_dB","Seed", ...
    "TrialIndex","absolute_slot"];
assert(all(ismember(keys,string(T.Properties.VariableNames))), ...
    'sixgr:truth:MissingIndependentREIdentity', ...
    'Independent occupancy requires producer SNR, seed, trial and grid identity.');
for name=["ConfiguredSNR_dB","Seed","TrialIndex","absolute_slot"]
    v=T.(name);
    assert(isnumeric(v) && isreal(v) && size(v,2)==1 && all(isfinite(v)), ...
        'sixgr:truth:InvalidIndependentREIdentity','Invalid producer %s.',name);
    if name~="ConfiguredSNR_dB"
        assert(all(v>=0 & v==fix(v)), ...
            'sixgr:truth:InvalidIndependentREIdentity','Invalid integer %s.',name);
    end
end
assert(all(T.TrialIndex>=1),'sixgr:truth:InvalidIndependentREIdentity', ...
    'Independent trial indices are one-based.');
parts=strings(height(T),numel(keys));
for k=1:numel(keys)
    v=T.(keys(k));
    if isnumeric(v), parts(:,k)=compose('%.17g',v); else, parts(:,k)=string(v); end
end
id="independent_tx|"+join(parts,"|",2);
if ismember('ObservationID',T.Properties.VariableNames)
    assert(isequal(string(T.ObservationID),id), ...
        'sixgr:truth:IndependentREIdentityMismatch','Conflicting observation identity.');
end
T.ObservationID=id;
T.ExecutionScope=repmat("independent_link_execution",height(T),1);
T.SameScenarioInPathEligible=false(height(T),1);
end
