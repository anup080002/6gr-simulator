function ok=testFourByTwoInterLayerEvidence(retainedScenario)
% Equalizer/component algebra, not a measured-channel or full-run pass.
% Channel fixture matches the explicit 4TX/2RX laboratory scenario. When
% supplied, the retained scenario verifies that this is the executed matrix.
H=[.8 0 .6 0;0 .6 0 .8];
if nargin>0
    s=jsondecode(fileread(retainedScenario));
    actual=reshape(s.channels.awgn_spatial_matrix_dl_real,4,2).';
    assert(isequal(H,actual) && s.mimo.n_tx_ant==4 && s.mimo.n_rx_ant==2);
end
assert(norm(H*H'-eye(2),'fro')<1e-12);
request=struct('N1',2,'N2',1,'O1',4,'O2',1, ...
    'Ports',4,'CodebookMode',1,'Rank',1);
tested=0; positiveInterLayer=0; largestError=0;
for layers=1:2
    request.Rank=layers;
    candidates=sixgr.phy.mimo.TypeISinglePanelCodebook.enumerate(request);
    for index=1:size(candidates,3)
        P=candidates(:,:,index);
        assert(abs(sum(abs(P).^2,'all')-1)<1e-12, ...
            'Rank change must not create transmit power.');
        effective=H*P;
        h=repmat(reshape(effective,1,2,layers),2,1,1);
        for noise=[.0025 .25 2.5]
            % The two input basis rows recover the actual implemented
            % receive filter; no channel coefficients enter a decoder here.
            [symbols,~,info]=sixgr.phy.rx.equalizeMMSE(eye(2),h,noise);
            filter=(effective'*effective+noise*eye(layers))\effective';
            assert(max(abs(symbols-filter.'),[],'all')<1e-10);
            response=filter*effective;
            covariance=noise*(filter*filter');
            desired=abs(diag(response)).^2;
            offDiagonal=response-diag(diag(response));
            interference=sum(abs(offDiagonal).^2,2);
            expectedSINR=desired./(interference+real(diag(covariance)));
            evidence=sixgr.phy.rx.interLayerEvidence(info.EqualizerResult);
            assert(max(abs(evidence.ResidualInterLayerPowerPerLayer- ...
                (interference./desired).'))<1e-10);
            actualSINR=info.EqualizerResult.PostEqSINRLinear(1,:).';
            assert(max(abs(actualSINR-expectedSINR)./max(expectedSINR,eps))<1e-9);
            % Toolbox may expose gain-normalized symbols. Compare the
            % unit-desired-gain filters and their SINR, not a guessed CSI
            % scaling convention. This is a second implementation.
            referenceSymbols=nrEqualizeMMSE(eye(2),h,noise);
            referenceFilter=referenceSymbols.';
            referenceResponse=referenceFilter*effective;
            referenceUnit=referenceFilter./diag(referenceResponse);
            actualUnit=filter./diag(response);
            errorValue=max(abs(referenceUnit-actualUnit),[],'all');
            assert(errorValue<1e-9);
            largestError=max(largestError,errorValue);
            if layers==1
                assert(evidence.ResidualInterLayerPowerMean==0);
            else
                positiveInterLayer=positiveInterLayer+double(any(interference>1e-10));
            end
            tested=tested+1;
        end
    end
end
assert(positiveInterLayer>0,'Rank-two fixtures must exercise nonzero interference.');
fprintf(['FOUR_BY_TWO_INTER_LAYER_PASS cases=%d nonzero_rank2_cases=%d ' ...
    'toolbox_unit_gain_max_error=%.12g fixed_total_precoder_power=1\n'], ...
    tested,positiveInterLayer,largestError);
ok=true;
end
