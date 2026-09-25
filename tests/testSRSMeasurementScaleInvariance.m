function ok=testSRSMeasurementScaleInvariance()
% Declared-channel algebra, NOT waveform or statistical CSI qualification.
% A change of amplitude units cannot alter RI, TPMI, MI or layer SINR.
setup6GRSimToolkit('Verbose',false);
cfg=struct(); cfg.phy.pusch.transmissionScheme='codebook';
cfg.phy.pusch.transformPrecoding=false;
rows=struct([]); failures=0;
for ports=[2 4]
    cfg.phy.pusch.NumAntennaPorts=ports;
    cfg.phy.pusch.numAntennaPorts=ports;
    cfg.phy.pusch.maxRankDefault=ports;
    H=[.8 .1+.15i .05 .03i;.2-.1i .7 .08i .04; ...
        .6 .2 .9 .07i;.1 .8 .03 .6];
    H=H(:,1:ports);
    for snr=[-30 -20 -10 0 10 20 30 40]
        noise=10^(-snr/10);
        baseline=sixgr.phy.ul.estimateSRSRITPMI(H,noise,cfg);
        assert(baseline.Valid);
        for amplitude=[1 1e-4 1e-8 1e-12 1e4]
            actual=sixgr.phy.ul.estimateSRSRITPMI(amplitude*H,amplitude^2*noise,cfg);
            W=double(nrPUSCHCodebook(actual.RI,ports,actual.TPMI,false)).';
            A=H*W/sqrt(noise);
            % Independent explicit signal/inter-layer/noise expression.
            B=(A'*A+eye(actual.RI))\A'; response=B*A;
            desired=abs(diag(response)).^2;
            cross=response-diag(diag(response));
            expected=10*log10(desired./(sum(abs(cross).^2,2)+sum(abs(B).^2,2)));
            errorDB=max(abs(actual.SelectedPostEqSINRPerLayer_dB(:)-expected));
            passed=actual.RI==baseline.RI && actual.TPMI==baseline.TPMI && ...
                abs(actual.TPMIMutualInformation-baseline.TPMIMutualInformation)<1e-9 && errorDB<1e-8;
            failures=failures+~passed;
            row=struct('Ports',ports,'RxBranches',4,'ReferenceSNR_dB',snr, ...
                'AmplitudeScale',amplitude,'NoisePower',amplitude^2*noise, ...
                'RI',actual.RI,'TPMI',actual.TPMI,'BaselineRI',baseline.RI, ...
                'BaselineTPMI',baseline.TPMI,'IndependentSINRError_dB',errorDB,'Pass',passed, ...
                'EvidenceScope',"declared_channel_algebra_not_physical_run");
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
    end
end
folder=fullfile(pwd,'results','lls','srs_measurement_scale_invariance', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(struct2table(rows),fullfile(folder,'scale_invariance.csv'));
fprintf('SRS_SCALE_INVARIANCE cases=%d failures=%d max_error_db=%g output=%s\n', ...
    numel(rows),failures,max([rows.IndependentSINRError_dB]),folder);
assert(failures==0,'sixgr:test:SRSAmplitudeUnitDependence', ...
    '%d cases changed spatial prediction solely by changing amplitude units.',failures);
ok=true;
end
