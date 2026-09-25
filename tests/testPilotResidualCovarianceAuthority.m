function ok=testPilotResidualCovarianceAuthority()
% Actual NR pilot mapping with algebraic channel/disturbance fixtures.
% Not a fading-estimator or integrated BLER qualification.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
K=12*carrier.NSizeGrid; L=carrier.SymbolsPerSlot;
for antennas=[1 2 4]
    pdsch=nrPDSCHConfig('NumLayers',antennas,'PRBSet',0:24);
    pdsch.DMRS.DMRSPortSet=0:antennas-1;
    pdsch.DMRS.NumCDMGroupsWithoutData=2;
    ind=nrPDSCHDMRSIndices(carrier,pdsch);
    sym=nrPDSCHDMRS(carrier,pdsch);
    tx=nrResourceGrid(carrier,antennas); tx(ind)=sym;
    ref=reshape(tx,K*L,antennas);
    base=unique(mod(double(ind(:))-1,K*L)+1,'stable');
    count=numel(base);
    % Full-rank H: the old y-H*pinv(H)*y residual erased every disturbance.
    H=eye(antennas)+.05i*ones(antennas);
    mix=eye(antennas);
    if antennas>1, mix(1,2)=.7i; end
    orthogonal=exp(2i*pi*(0:count-1).'*(1:antennas)/count);
    disturbance=.2*orthogonal*mix;
    received=ref*H.';
    received(base,:)=received(base,:)+disturbance;
    rx=reshape(received,K,L,antennas);
    Hest=repmat(reshape(H,1,1,antennas,antennas),K,L,1,1);
    expected=complex(zeros(antennas));
    for r=1:antennas
        for c=1:antennas
            expected(r,c)=mean(disturbance(:,r).*conj(disturbance(:,c)));
        end
    end
    for noiseArgument=[0 .01 100]
        [R,info,state]=sixgr.phy.rx.estimateInterferenceCovarianceIRC( ...
            rx,Hest,ind,sym,noiseArgument,'ShrinkageFactor',0);
        assert(info.Available && info.CovarianceIncludesNoise && state.IncludesNoise);
        assert(info.NRE==count && info.NoiseVarianceAdded==0);
        assert(norm(R-expected,'fro')<1e-12, ...
            'Pilot covariance lost disturbance or added noise instead of measuring it.');
    end
    % The known reference signs/ports must affect the reconstruction.
    [wrong,wrongInfo]=sixgr.phy.rx.estimateInterferenceCovarianceIRC( ...
        rx,Hest,ind,-sym,.01,'ShrinkageFactor',0);
    assert(wrongInfo.Available && norm(wrong-expected,'fro')>.1, ...
        'Changing the reference symbols did not change the pilot residual.');
    alpha=.2;
    [shrunk,info]=sixgr.phy.rx.estimateInterferenceCovarianceIRC( ...
        rx,Hest,ind,sym,.01,'ShrinkageFactor',alpha);
    target=trace(expected)/antennas*eye(antennas);
    assert(info.Available && norm(shrunk-((1-alpha)*expected+alpha*target),'fro')<1e-12);
    assert(abs(trace(shrunk)-trace(expected))<1e-12,'Shrinkage changed measured total power.');
    % A singular residual must not be rescued by adding the supplied nVar.
    noiseless=reshape(ref*H.',K,L,antennas);
    [~,zeroInfo]=sixgr.phy.rx.estimateInterferenceCovarianceIRC( ...
        noiseless,Hest,ind,sym,100,'ShrinkageFactor',0);
    assert(~zeroInfo.Available,'A zero residual was fabricated into a positive covariance.');
    % Sample estimator uses centered E[n*n^H], with the same spatial phase.
    samples=disturbance+repmat((1:antennas)+1i,count,1);
    measured=sixgr.phy.mimo.InterferenceCovarianceState.estimate(samples,'ShrinkageFactor',0);
    expectedCentered=expected*count/(count-1);
    assert(norm(measured.Matrix-expectedCentered,'fro')<1e-12);
    if antennas>1
        assert(abs(imag(expected(1,2)))>.01 && ...
            norm(measured.Matrix-conj(expectedCentered),'fro')>.01, ...
            'Complex receive correlation was conjugated.');
    end
    fprintf('PILOT_COVARIANCE ports=%d samples=%d complex_error=%g noise_added=0\n', ...
        antennas,count,norm(R-expected,'fro'));
end
ok=true;
fprintf('PILOT_RESIDUAL_COVARIANCE_AUTHORITY_PASS known_DMRS_used=1 full_rank_disturbance_retained=1 complex_orientation=1\n');
end
