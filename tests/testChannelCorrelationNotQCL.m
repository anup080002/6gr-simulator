function ok=testChannelCorrelationNotQCL()
% Analytic channel-estimate diagnostic fixtures, not QCL conformance vectors.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
ref=nrSymbolModulate(int8([0;0;0;1;1;0;1;1]),'QPSK');
for mode=["TDD","FDD"]
    cfg=sixgr.config.defaultConfig();
    cfg.duplexMode=mode;
    for direction=["DL","UL"]
        tx=struct('LayerSymbolDomain','layer');
        if direction=="DL"
            tx.PDSCH=struct('Modulation','QPSK'); tx.PDSCHLayerSymbolsForEvidence=ref;
        else
            tx.PUSCH=struct('Modulation','QPSK'); tx.PUSCHLayerSymbolsForEvidence=ref;
        end
        rx=struct('LayerEqualizedSymbolsForEvidence',ref,'EqualizedSymbolDomain','layer');
        for scale=[1 .1]
            rx.ChannelEstimate=scale*ones(24,14,2);
            metrics=sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
            assert(abs(metrics.EstimatedChannelReferenceCorrelationMagnitude-1)<1e-12);
            assert(isnan(metrics.QCLAccuracy) && ...
                metrics.QCLMeasurementStatus=="not_measured_requires_QCL_TCI_binding_evidence");
        end
        rx.ChannelEstimate=[];
        metrics=sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
        assert(isnan(metrics.QCLAccuracy) && isnan(metrics.EstimatedChannelReferenceCorrelationMagnitude));
    end
end
ok=true;
fprintf('CHANNEL_CORRELATION_NOT_QCL_PASS: TDD/FDD DL/UL retain honest diagnostic scope.\n');
end
