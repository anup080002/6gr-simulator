function ok=testCommonPDCCHWithConnectedPolicy()
% Common physical scrambling must survive installation of connected DCI.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
[common,cfgSI,carrierSI]=sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,cfg);
assert(strcmpi(common.SearchSpace.SearchSpaceType,'common') && ...
    isfield(cfgSI.phy.pdcch.operatorControl,'connected_dci'));
bits=int8(mod((0:39).',2));
for rnti=[65535 1 1234] % SI, RA and TC identity fixtures; not RA-procedure qualification.
    [tx,info]=sixgr.phy.dl.PDCCH_Tx(cfgSI,'Carrier',carrierSI,'PDCCH',common, ...
        'RNTI',rnti,'DCIBits',bits,'PDCCHScramblingRNTI',0);
    assert(info.CommonSearchSpaceApplied && ~info.ConnectedMonitoringApplied && ...
        info.PDCCHScramblingRNTI==0 && info.DCICrcRNTI==rnti);
    [rx,~]=sixgr.phy.dl.PDCCH_Rx(tx.Waveform,cfgSI,'Carrier',carrierSI,'PDCCH',common, ...
        'RNTI',rnti,'PDCCHScramblingRNTI',0,'K',numel(bits));
    assert(rx.Ok && isequal(rx.DCIBits,bits));
end
try
    sixgr.phy.dl.PDCCH_Tx(cfgSI,'Carrier',carrierSI,'PDCCH',common, ...
        'RNTI',65535,'DCIBits',bits,'PDCCHScramblingRNTI',1);
    error('test:MissingRejection','Expected common scrambling mismatch.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:phy:pdcch:CommonMonitoringIdentityMismatch'));
end
ok=true;
end
