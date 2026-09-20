function ok=testMsg3CommonMCSIsolation()
% RAR-owned coding/waveform regression; not shared access qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
root=fullfile(pwd,'results','lls','msg3_common_mcs_isolation', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
original=cfg;
ra=sixgr.mac.ra.RAConfig(cfg,'UEId',1,'AttemptId',1);
grant=sixgr.mac.ra.buildRARULGrant(ra);
payload=sixgr.mac.ra.buildMsg3Payload('UEId',1);
[tx,pusch]=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ra,grant,payload);
assert(pusch.Modulation==grant.Modulation && pusch.NumLayers==1 && ...
    ~isfield(tx,'ResearchTransport'));
native=cfg; native.phy.pusch.mcsTable=char(grant.MCSTable);
baseline=sixgr.phy.ra.generateMsg3PUSCHWaveform(native,ra,grant,payload);
assert(isequal(tx.Waveform,baseline.Waveform) && ...
    isequal(tx.TransportBlock,baseline.TransportBlock));
changed=cfg;
changed.phy.pusch.modulation='1024QAM'; changed.phy.pusch.mcsIndex=10;
changed.phy.pusch.numLayers=4; changed.phy.pusch.targetCodeRate=0.9;
other=sixgr.phy.ra.generateMsg3PUSCHWaveform(changed,ra,grant,payload);
assert(isequal(other.Waveform,tx.Waveform));
[rx,decoded]=sixgr.phy.ra.recoverMsg3PUSCH(tx.Waveform,changed,ra,grant,tx);
save(fullfile(root,'msg3_isolation.mat'),'grant','tx','rx','decoded','-v7.3');
assert(rx.Ok && isequal(rx.TransportBlock,tx.TransportBlock));
assert(decoded.ContentionIdentity==payload.ContentionIdentity);
assert(isequaln(cfg,original) && startsWith(string(cfg.phy.pusch.mcsTable),'experimental_'));
slot=sixgr.phy.ra.resolveMsg3SlotFromRAR(ra,grant);
for field=["MCSTable","Modulation","TargetCodeRate","NLayers"]
    bad=grant;
    switch field
        case "MCSTable", bad.MCSTable="experimental_square_qam_v1";
        case "Modulation", bad.Modulation="1024QAM";
        case "TargetCodeRate", bad.TargetCodeRate=0.9;
        case "NLayers", bad.NLayers=4;
    end
    caught=false;
    try
        sixgr.phy.ra.localizeRAPUSCHConfig(cfg,ra,bad,slot);
    catch ME
        assert(string(ME.identifier)=="sixgr:phy:ra:Msg3MCSContextMismatch",'%s',ME.message);
        caught=true;
    end
    assert(caught,'Contradictory Msg3 context accepted: %s',field);
end
fprintf('MSG3_COMMON_MCS_ISOLATION_PASS root=%s\n',root);
% The later SRB1 stage has its own installed table and final C-RNTI. It must
% not inherit either the connected table or the RAR's Msg3 table/index.
setupRA=ra; setupRA.FinalCRNTI=ra.TempCRNTI+1;
profile=sixgr.phy.ul.pusch.PUSCHMCSResolver.resolve('qam64LowSE',7,false);
setupRA.SetupCompletePUSCH.MCSTable=profile.MCSTable;
setupRA.SetupCompletePUSCH.MCS=profile.MCSIndex;
setupRA.SetupCompletePUSCH.Modulation=profile.Modulation;
setupRA.SetupCompletePUSCH.TargetCodeRate=profile.TargetCodeRate;
message=sixgr.mac.ra.buildRRCSetupComplete('TransactionID',ra.RRCTransactionID, ...
    'SRB1LCID',ra.SRB1LCID,'UEIdentity','UE-1');
setupTX=sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg,setupRA,grant,message);
native.phy.pusch.mcsTable=char(profile.MCSTable);
setupNative=sixgr.phy.ra.generateRRCSetupCompleteWaveform(native,setupRA,grant,message);
setupChanged=sixgr.phy.ra.generateRRCSetupCompleteWaveform(changed,setupRA,grant,message);
assert(isequal(setupTX.Waveform,setupNative.Waveform) && ...
    isequal(setupTX.Waveform,setupChanged.Waveform) && ~isfield(setupTX,'ResearchTransport'));
assert(setupTX.Grant.MCSTable==profile.MCSTable && setupTX.PUSCH.RNTI==setupRA.FinalCRNTI);
[setupRX,decodedSetup]=sixgr.phy.ra.recoverRRCSetupComplete(setupTX.Waveform,changed,setupRA,setupTX);
save(fullfile(root,'setup_complete_isolation.mat'),'setupRA','setupTX','setupRX','decodedSetup','-v7.3');
assert(setupRX.Ok && isequal(setupRX.TransportBlock,setupTX.TransportBlock) && ...
    decodedSetup.TransactionID==message.TransactionID && decodedSetup.UEIdentity==message.UEIdentity);
bad=setupRA; bad.SetupCompletePUSCH.TargetCodeRate=.9;
caught=false;
try
    sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg,bad,grant,message);
catch ME
    assert(string(ME.identifier)=="sixgr:phy:ra:RRCSetupMCSContextMismatch",'%s',ME.message);
    caught=true;
end
assert(caught && isequaln(cfg,original));
fprintf('RRC_SETUP_COMMON_MCS_ISOLATION_PASS root=%s\n',root);
ok=true;
end
