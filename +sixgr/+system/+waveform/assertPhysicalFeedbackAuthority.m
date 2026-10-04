function assertPhysicalFeedbackAuthority(grant)
%ASSERTPHYSICALFEEDBACKAUTHORITY Keep ideal modeled SLS feedback out of truth replay.
% Check both scheduler and frozen PHY ownership. An audit-deferred grant
% must obey the same contract as an immediately executed waveform grant.
owners = {grant, sixgr.util.structGet(grant,'PHYGrant.PrecodingState',struct())};
for k = 1:numel(owners)
    owner = owners{k};
    for kind = ["CSI","SRS"]
        field = "Modeled" + kind + "Feedback";
        evidence = sixgr.util.structGet(owner,field,struct());
        emptyEvidence = isempty(evidence) || ...
            (isstruct(evidence) && isscalar(evidence) && isempty(fieldnames(evidence)));
        used = sixgr.util.structGet(owner,"Modeled" + kind + "DecisionUsed",false);
        assert(emptyEvidence && isequal(used,false), ...
            'sixgr:system:WaveformReplay:ModeledFeedback', ...
            'Waveform replay cannot use modeled %s feedback as physical receiver authority.',kind);
    end
end
end
