function ok=testNRAccessWaveformPayloads()
% Original coded Msg3/Msg4 payloads through the real PHY decoders.
% Explicit common/procedure configuration and noiseless local observations;
% this does not claim shared cell monitoring, SRB activation or full access.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
folder=fullfile(pwd,'results','validation','nr_access_payloads',char(java.util.UUID.randomUUID()));
sixgr.util.ensureFolder(folder);cfg=sixgr.lls6g.buildInternalConfig(s,folder);
% This codec/PHY component supplies its original configured SSB association;
% it does not claim a measured beam selection or a received access procedure.
cfg.random_access.associated_ssb_index=cfg.phy.ssb.runtimeSSBIndex;
cfg.random_access.associated_ssb_selection_source="configured_NR_Msg4_component_reference_not_measured_selection";
ra=sixgr.mac.ra.RAConfig(cfg,'UEId',1,'AttemptId',1);
ra.RRCEncodingProfile="nr_rrc_access_base_srb1_uper_v1";
request=sixgr.mac.ra.buildNRMsg3Payload("randomValue",2^38+7,"mo-Signalling");
grant=sixgr.mac.ra.buildRARULGrant(ra);
before=rng;a=sixgr.phy.ra.resolveMsg3PUSCHAllocation(cfg,ra,grant);
assert(isequal(before,rng)&&~isfield(a,'Waveform'));
tx3=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ra,grant,request);
assert(tx3.TransportBlockSize==a.TransportBlockSize);
% Deliberately no transmitted payload length, carrier or TX object is
% available to the NR receiver. The original issued grant owns its TBS.
[rx3,msg3]=sixgr.phy.ra.recoverMsg3PUSCH(tx3.Waveform,cfg,ra,grant,struct());
assert(rx3.Ok&&isequal(rx3.TransportBlock,tx3.TransportBlock)&& ...
    msg3.ContentionIdentity==request.ContentionIdentity&& ...
    numel(msg3.PayloadBytes)==a.TransportBlockSize/8&& ...
    msg3.MACDecodeEvidence.PaddingBytes>0);
response=sixgr.mac.ra.buildNRMsg4ContentionResolution(msg3.ContentionIdentityBytes,2);
tx4=sixgr.phy.ra.generateMsg4Waveform(cfg,ra,response);
[dci,rx4,msg4]=sixgr.phy.ra.recoverMsg4Waveform(tx4.Waveform,cfg,ra,struct(),struct());
assert(dci.CausalGrantDecodeOk&&rx4.Ok&&msg4.ContentionIdentity==msg3.ContentionIdentity&& ...
    msg4.RRCSetup.TransactionID==2&&isnan(msg4.FinalCRNTI)&& ...
    numel(msg4.PayloadBytes)==tx4.TransportBlockSize/8&& ...
    msg4.MACDecodeEvidence.PaddingBytes>0&& ...
    rx4.Msg4MACEncodingProfile==ra.RRCEncodingProfile);
save(fullfile(folder,'original_coded_access.mat'),'cfg','ra','request','grant', ...
    'tx3','rx3','msg3','response','tx4','dci','rx4','msg4','-v7.3');
ok=true;fprintf('NR_ACCESS_WAVEFORM_PAYLOADS_PASS original_ULCCCH48=1 DLCCCH=1 full_MAC_TB=1 shared_access=0 root=%s\n',folder);
end
