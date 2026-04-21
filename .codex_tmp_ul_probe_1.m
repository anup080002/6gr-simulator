setup6GRSimToolkit(''Verbose'',false);
scfg = sixgr.lls6g.config.loadScenarioConfig(''simulator/configs/scenarios/lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_5gnb_50ue_10slot.yaml'');
cfg = sixgr.lls6g.buildInternalConfig(scfg,''results'');
fprintf(''ueNum=%g\n'', sixgr.util.structGet(cfg,''antenna.ue.numElements'',NaN));
fprintf(''bsNum=%g\n'', sixgr.util.structGet(cfg,''antenna.bs.numElements'',NaN));
fprintf(''ulTx=%g\n'', sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg,''tx'',NaN));
fprintf(''ulRx=%g\n'', sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg,''rx'',NaN));
[tx,~] = sixgr.phy.ul.PUSCH_Tx(cfg,''CompactOutput'',true);
fprintf(''txWaveCols=%g\n'', size(tx.Waveform,2));
