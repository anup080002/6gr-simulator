function [trials,symbols]=diagnosePDSCHResidualReplay(capturePaths,outputRoot)
% Matched RX-only ablation of existing residual-variance policies.
% Transmitted bits are used AFTER reception for scoring, never for RX policy.
arguments
    capturePaths (:,1) string
    outputRoot (1,1) string
end
assert(isfolder(outputRoot),'Use an existing retained diagnostic directory.');
trials=table(); symbols=table();
policies=[false false;true false;false true;true true];
names=["baseline";"dmrs_residual";"decision_residual";"both_residuals"];
for file=capturePaths.'
    saved=load(file,'ReceiverReplay'); c=saved.ReceiverReplay; old=c.ReceiverResult;
    assert(c.Direction=="DL" && c.Contract=="exact_receiver_replay/v1");
    assert(c.WaveformSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(c.Waveform)));
    for variant=1:size(policies,1)
        cfg=c.Config;
        if variant>1
            cfg.phy.pdsch.measurements.dmrsResidualPostEqSINRBoundEnabled=policies(variant,1);
            cfg.phy.pdsch.measurements.decisionDirectedPostEqSINRBoundEnabled=policies(variant,2);
            source=cfg.lls6g.resolvedConfig;
            source.pdsch.dmrs_residual_post_eq_sinr_bound_enabled=policies(variant,1);
            source.pdsch.decision_directed_post_eq_sinr_bound_enabled=policies(variant,2);
            cfg.lls6g.resolvedConfig=source;
            cfg.meta.configHash=char(sixgr.lls6g.config.hashResolvedScenario(source));
            cfg=sixgr.config.installRuntimeOperatingAuthority(cfg,source);
        end
        rx=feval(c.ReceiverFunction,c.Waveform,cfg,c.ReceiverArguments{:});
        if variant==1
            assert(isequal(rx.TransportBlock,old.TransportBlock) && rx.TBCRCPass==old.TBCRCPass);
            baseline=rx;
        else
            assert(isequal(rx.LayerSymbols,baseline.LayerSymbols) && ...
                rx.CFOCorrectionApplied_Hz==baseline.CFOCorrectionApplied_Hz && ...
                rx.AppliedTimingCorrection_samples==baseline.AppliedTimingCorrection_samples, ...
                'Residual-variance ablation must not modify synchronization or equalized symbols.');
        end
        % Post-reception reference reconstruction cannot influence decoding.
        if variant==1
            ref=sixgr.phy.dl.PDSCH_Tx(c.Config,'ExecutionProfile','phy_calibration', ...
                'Carrier',old.Carrier,'PDSCH',old.PDSCH, ...
                'TransportBlockBits',c.Context.ScoringOnlyTransmittedBits, ...
                'NumTxAnt',c.Config.channel.nTxAnt);
        end
        [metrics,constellation]=sixgr.link.deriveModulationTrackingMetrics(ref,rx,cfg,"DL");
        eq=rx.LayerSymbols; reference=ref.PDSCHLayerSymbols;
        assert(isequal(size(eq),size(reference)));
        errorPower=mean(abs(eq-reference).^2,'all');
        eqInfo=rx.EqualizationInfo;
        noise=eqInfo.PostEqualizationNoiseVariancePerResourceLayer;
        trials=[trials;table(file,c.Context.Slot,names(variant),logical(rx.TBCRCPass), ...
            metrics.EVM_rms,rx.PostEqSINR_dB,mean(noise,'all'),errorPower, ...
            rx.PostEqSINRDMRSResidual_dB,rx.PostEqDecisionResidual_dB, ...
            string(cfg.meta.configHash),false,'VariableNames', ...
            {'CaptureMAT','Slot','Policy','CRCPass','EVM_rms','PostEqSINR_dB', ...
            'DemapperVarianceMean','ScoringErrorPower','DMRSResidualSINR_dB', ...
            'DecisionResidualSINR_dB','ConfigHash','StatisticallyQualified'})]; %#ok<AGROW>
        if variant==1
            K=12*rx.Carrier.NSizeGrid;
            symbol0=mod(floor((double(rx.PDSCHIndices(:,1))-1)/K),rx.Carrier.SymbolsPerSlot);
            for symbol=unique(symbol0).'
                mask=symbol0==symbol;
                e=eq(mask,:); t=reference(mask,:);
                % This correlation is diagnostic only: no phase/gain fit is applied.
                phase=angle(sum(e.*conj(t),'all'))*180/pi;
                symbols=[symbols;table(file,c.Context.Slot,symbol,nnz(mask), ...
                    sqrt(sum(abs(e-t).^2,'all')/sum(abs(t).^2,'all')),phase, ...
                    mean(noise(mask,:),'all'),mean(abs(e-t).^2,'all'), ...
                    'VariableNames',{'CaptureMAT','Slot','Symbol0','DataREPerLayer', ...
                    'EVM_rms','ScoringPhaseError_deg','DemapperVarianceMean', ...
                    'ScoringErrorPower'})]; %#ok<AGROW>
            end
        end
        sixgr.util.csvWriteTable(fullfile(outputRoot,'dl_residual_policy_comparison.csv'),trials, ...
            'PreserveSchema',true,'RoundTripNumericText',true);
        sixgr.util.csvWriteTable(fullfile(outputRoot,'dl_symbol_error_diagnostic.csv'),symbols, ...
            'PreserveSchema',true,'RoundTripNumericText',true);
        assert(~isempty(constellation),'Actual matched symbols must be retained.');
    end
end
end
