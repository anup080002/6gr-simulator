function ok=testRAStagePowerEvidence()
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25);
grid=complex(zeros(300,14)); grid(1:12,:)=1;
[wave,ofdm]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
cfg=struct('powerAndRF',struct('bsTxPower_dBm',30,'ueTxPower_dBm',23, ...
    'downlinkPowerNormalizationPolicy',"fixed_epre_over_configured_bwp"));
for duplex=["TDD","FDD"]
    cfg.phy.duplex.mode=duplex;
    for direction=["DL","UL"]
        [~,context]=sixgr.rf.applyPowerContext(wave,cfg,direction, ...
            struct('OFDM',ofdm,'PortGrid',grid),'ApplyPA',false);
        before=context;
        row=sixgr.phy.ra.bindStagePowerEvidence(struct(),context);
        assert(isequaln(before,context));
        assert(row.MeasuredTxPowerBeforeRF_dBm==context.OutputTotalPower_dBm);
        assert(row.ReferenceOutputPower_dBm==context.ReferenceOutputPower_dBm);
        assert(abs(row.ReferenceOutputPower_dBm-row.AppliedTxPower_dBm- ...
            row.TxPowerClosureError_dB)<1e-12);
        assert(abs(row.ReferenceOutputPower_dBm-row.MeasuredTxPowerBeforeRF_dBm+ ...
            10*log10(row.FullBWPActivityFactor))<1e-10);
        if direction=="DL"
            assert(abs(row.FullBWPActivityFactor-1/25)<1e-12);
            assert(row.MeasuredTxPowerBeforeRF_dBm<row.AppliedTxPower_dBm-13);
        else
            assert(row.FullBWPActivityFactor==1);
        end
        try
            sixgr.phy.ra.bindStagePowerEvidence(struct(),rmfield(context,'ReferenceOutputPower_dBm'));
            error('test:MissingError','Missing actual reference must fail.');
        catch cause
            assert(strcmp(cause.identifier,'sixgr:phy:ra:MissingStagePowerReference'));
        end
    end
end
fprintf('RA_STAGE_POWER_EVIDENCE_PASS: actual DL sparse-grid and UL waveform contexts, both duplex modes.\n');
ok=true;
end
