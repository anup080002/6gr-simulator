function validateCSISelectionQualityArithmetic(p)
%VALIDATECSISELECTIONQUALITYARITHMETIC Recheck original archived operands.
% Shared producer/readback contract; no PHY execution or new scoring policy.
H=double(p.Inputs.Reference.H); B=double(p.Inputs.Reference.PortToPhysicalMatrix);
R=double(p.Inputs.Disturbance.Covariance); T=p.Candidates; scores=zeros(height(T),1);
for k=1:height(T)
    W=p.CandidateMatrices{k}; physical=B*W;
    power=sum(abs(physical(:)).^2); factor=sqrt(p.Inputs.Policy.PowerFactor/power);
    layers=zeros(size(H,3),size(W,2));
    for q=1:size(H,3)
        A=H(:,:,q)*W*factor;
        % Independent covariance identity checks the scorer's direct filter.
        E=(eye(size(W,2))+A'*(R\A))\eye(size(W,2));
        layers(q,:)=(1./real(diag(E))-1).';
    end
    objectives=sum(log2(1+layers),2); scores(k)=mean(objectives);
    assert(near(layers,T.LayerSINR{k}) && near(objectives,T.SupportObjective_bpsHz{k}) && ...
        near(scores(k),T.Objective_bpsHz(k)) && near(power,T.UnscaledPhysicalFrobeniusPower(k)) && ...
        near(factor,T.AppliedAmplitudeFactor(k)), ...
        'sixgr:truth:CSISelectionArchiveRecompute','Saved operands do not reproduce candidate scoring.');
end
selected=find(T.SelectedByReceiver); assert(isscalar(selected));
best=max(scores); reported=max(scores(T.Rank==p.Summary.SelectedRank)); s=p.Summary;
assert(near(s.SelectedObjective_bpsHz,scores(selected)) && near(s.BestJointObjective_bpsHz,best) && ...
    near(s.BestReportedRankObjective_bpsHz,reported) && ...
    near(s.ConditionalPMIRegret_bpsHz,reported-scores(selected)) && ...
    near(s.RankRegret_bpsHz,best-reported) && near(s.JointRegret_bpsHz,best-scores(selected)), ...
    'sixgr:truth:CSISelectionArchiveRecompute','Saved candidate population does not reproduce summary regret.');
end

function yes=near(a,b)
yes=isequal(size(a),size(b)) && all(isfinite(a),'all') && all(isfinite(b),'all') && ...
    all(abs(a-b)<=1e-9*max(1,max(abs([a(:);b(:)]))),'all');
end
