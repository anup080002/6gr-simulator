function ok=testReceiverDiagnosticDefinitions()
cfg=struct();
for direction=["DL","UL"]
    for modulation=["QPSK","16QAM","64QAM","256QAM"]
        qm=log2(str2double(erase(modulation,"QAM"))); if modulation=="QPSK", qm=2; end
        ref=nrSymbolModulate(int8(mod((1:qm*48).',2)),char(modulation));
        tx=struct('LayerSymbolDomain','layer');
        if direction=="DL", tx.PDSCH=struct('Modulation',modulation); tx.PDSCHLayerSymbolsForEvidence=ref;
        else, tx.PUSCH=struct('Modulation',modulation); tx.PUSCHLayerSymbolsForEvidence=ref; end
        rx=struct('LayerEqualizedSymbolsForEvidence',ref+.01+.02i, ...
            'EqualizedSymbolDomain','layer','ChannelEstimate',ones(24,14));
        m=sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
        assert(abs(m.DecisionResidualRatio_dB-10*log10(m.DecisionResidualEnergy/m.DecisionReferenceEnergy))<1e-12);
        assert(m.HestCoarseReconstructionErrorEnergy==0 && m.HestMagnitudeStd_dB==0);
        assert(isinf(m.HestCoarseReconstructionErrorRatio_dB) && m.HestCoarseReconstructionErrorRatio_dB<0);
        assert(contains(m.ResidualMetricDefinition,'not_external_interference'));
        % Poison scoring symbols: receiver decisions/residual remain fixed.
        if direction=="DL", tx.PDSCHLayerSymbolsForEvidence=-ref; else, tx.PUSCHLayerSymbolsForEvidence=-ref; end
        changed=sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
        assert(changed.DecisionResidualEnergy==m.DecisionResidualEnergy && changed.SymbolErrors>m.SymbolErrors);
    end
end
ok=true;
end
