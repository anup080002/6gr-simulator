function T=addCFOObservationColumns(T,observations,syncStates)
% Publish only estimator-produced observations, including unavailability.
if nargin<3, syncStates=repmat({struct()},height(T),1); end
assert(istable(T) && iscell(observations) && height(T)==numel(observations), ...
    'sixgr:link:CFOObservationRows','CFO observation count must match actual trial rows.');
assert(iscell(syncStates) && height(T)==numel(syncStates), ...
    'sixgr:link:CFOSynchronizationRows','Synchronization evidence must match actual trial rows.');
T.CFOCPObservationPolicy=strings(height(T),1);
T.CFOCPObservationStatus=repmat("not_reported_by_receiver",height(T),1);
T.ResidualCFOEstimateRole=repmat("not_reported_by_receiver",height(T),1);
T.ResidualCFOReusesAcquisitionObservation=NaN(height(T),1);
T.ResidualCFOEstimatorConsistency_Hz=NaN(height(T),1);
fields=["ObservationCoherenceSquared","ObservationStartFromUsefulSymbol_samples", ...
    "ObservationLength_samples","ObservationPairCount","NoiseOnlyCoherenceThreshold"];
names=["CFOCPCoherenceSquared","CFOCPWindowStartFromUsefulSymbol_samples", ...
    "CFOCPWindowLength_samples","CFOCPObservationPairCount","CFOCPNoiseOnlyCoherenceThreshold"];
for k=1:numel(names), T.(names(k))=NaN(height(T),1); end
for row=1:height(T)
    sync=syncStates{row};
    if isstruct(sync) && isscalar(sync)
        T.ResidualCFOEstimateRole(row)=string(sixgr.util.structGet(sync, ...
            'ResidualCFOEstimateRole','not_reported_by_receiver'));
        T.ResidualCFOReusesAcquisitionObservation(row)=double(sixgr.util.structGet(sync, ...
            'ResidualCFOReusesAcquisitionObservation',NaN));
        T.ResidualCFOEstimatorConsistency_Hz(row)=double(sixgr.util.structGet(sync, ...
            'ResidualCFOEstimatorConsistency_Hz',NaN));
    end
    e=observations{row};
    if ~isstruct(e) || isempty(fieldnames(e)), continue; end
    T.CFOCPObservationPolicy(row)=string(sixgr.util.structGet(e,'ObservationPolicy',''));
    T.CFOCPObservationStatus(row)=string(sixgr.util.structGet(e,'Status','not_reported_by_receiver'));
    for k=1:numel(fields)
        value=sixgr.util.structGet(e,fields(k),NaN);
        assert(isnumeric(value) && isreal(value) && isscalar(value), ...
            'sixgr:link:CFOObservationValue','Receiver CFO field %s must be a numeric scalar.',fields(k));
        T.(names(k))(row)=double(value);
    end
end
end
