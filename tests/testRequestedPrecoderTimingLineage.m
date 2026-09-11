function ok=testRequestedPrecoderTimingLineage()
% Constructed records test identity/time-domain binding, not measured CSI.
rows=table([3;2;1;2],[1;0;NaN;0],[0;NaN;NaN;NaN], ...
    ["frozen_PHYGrant_precoding_state";"frozen_PHYGrant_precoding_state";"";""], ...
    'VariableNames',{'PMI','ConfiguredPMI','RequestedPrecoderPMI','RequestedPrecoderSource'});
for direction=["DL","UL"]
    [pmi,source]=sixgr.phy.grant.requestedPrecoderColumns(rows,direction);
    assert(isequaln(pmi,[0;NaN;NaN;0]));
    assert(all(source(1:2)=="frozen_PHYGrant_precoding_state") && source(3)=="");
    assert(~any(contains(source,"feedback")));
    original=rows;
    original.PMI(:)=7; % New receiver measurements cannot alter a past request.
    [again,againSource]=sixgr.phy.grant.requestedPrecoderColumns(original,direction);
    assert(isequaln(again,pmi) && isequal(againSource,source));
    rows.RequestedPrecoderPMI=pmi; rows.RequestedPrecoderSource=source;
    [again,againSource]=sixgr.phy.grant.requestedPrecoderColumns(rows,direction);
    assert(isequaln(again,pmi) && isequal(againSource,source));
end
ok=true;
end
