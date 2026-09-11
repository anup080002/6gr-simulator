function ok=testSRSCodebookOrientation()
% Independent native-codebook/MMSE reference, including square full rank.
cfg=sixgr.config.defaultConfig();
cfg.phy.pusch.transmissionScheme='codebook';
cfg.phy.pusch.transformPrecoding=false;
% Deliberately non-symmetric complex channel: a square-matrix transpose
% error must not be concealed by identity/symmetric-channel fixtures.
base=[1+.2i .4-.1i .2+.3i -.1; .1 .8+.2i .3-.4i .2; ...
    -.2i .2 1.2-.1i .4+.3i; .3 .1-.2i -.3+.1i .9];
for ports=[2 4]
    cfg.phy.nTxAnt=ports; cfg.phy.nRxAnt=ports;
    cfg.phy.pusch.NumAntennaPorts=ports; cfg.phy.pusch.numAntennaPorts=ports;
    cfg.phy.pusch.maxRankDefault=ports;
    H=base(1:ports,1:ports);
    Hgrid=repmat(reshape(H,1,1,ports,ports),[12 2 1 1]);
    for noise=[0.005 0.5]
        measured=sixgr.phy.ul.estimateSRSRITPMI(Hgrid,noise,cfg);
        assert(measured.Valid);
        best=-inf;
        for layers=1:ports
            catalog=sixgr.phy.ul.puschCodebookCatalog(layers,ports,false);
            assert(catalog.Valid);
            for tpmi=double(catalog.ValidTPMISet(:).')
                Wnative=nrPUSCHCodebook(layers,ports,tpmi,false);
                score=localMMSE(H*Wnative.',noise);
                best=max(best,score);
            end
        end
        Wselected=nrPUSCHCodebook(measured.RI,ports,measured.TPMI,false);
        [score,layerSINR]=localMMSE(H*Wselected.',noise);
        assert(abs(score-best)<1e-9, ...
            'SRS-selected codebook must maximize MI using the actual layer-to-port mapping.');
        assert(abs(measured.TPMIMutualInformation-score)<1e-9 && ...
            max(abs(measured.SelectedPostEqSINRPerLayer_dB(:)-10*log10(layerSINR(:))))<1e-9, ...
            'Predicted layer SINR must match independent MMSE on the physically applied codebook.');
        if noise==0.005
            assert(measured.RI==ports,'High-SNR fixture must exercise square full-rank matrices.');
        end
    end
end
ok=true;
end

function [score,sinr]=localMMSE(H,noise)
C=(eye(size(H,2))+(H'*H)/noise)\eye(size(H,2));
sinr=1./real(diag(C))-1;
assert(all(sinr>0 & isfinite(sinr)));
score=sum(log2(1+sinr));
end
