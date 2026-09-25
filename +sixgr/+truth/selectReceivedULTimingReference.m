function reference=selectReceivedULTimingReference(state,ue,observationStart,nominalStart)
% Select by receiver availability, never by the current callback order.
% Identity, TAG, freshness and FFT coverage are still enforced by align().
validateattributes(ue,{'numeric'},{'scalar','integer','positive'});
validateattributes(observationStart,{'numeric'},{'scalar','integer','nonnegative','finite'});
% With a completed buffer, the cutoff is its end and nominalStart restricts
% selection to this slot or earlier. Existing three-argument prior-clock
% callers retain their original pre-observation availability boundary.
if nargin<4, nominalStart=Inf;
else, validateattributes(nominalStart,{'numeric'},{'scalar','integer','nonnegative','finite'});
end
reference=[];
history=sixgr.util.structGet(state,'ReceivedULTimingHistory',{});
if numel(history)>=ue && ~isempty(history{ue})
    candidates=history{ue};
else
    latest=sixgr.util.structGet(state,'ReceivedULTimingReferences',{});
    if numel(latest)<ue || isempty(latest{ue}), return; end
    candidates={latest{ue}};
end
for k=numel(candidates):-1:1
    candidate=candidates{k};
    assert(isa(candidate,'sixgr.phy.sync.ReceivedULTimingReference') && isscalar(candidate), ...
        'sixgr:truth:InvalidReceivedULTimingReference','A retained clock must be actual validated pilot evidence.');
    if candidate.AvailableAtSample<=observationStart && candidate.NominalStartSample<=nominalStart
        reference=candidate;
        return;
    end
end
end
