function ok = testRAPayloadExportOwnership()
% Actual coded TDD component: erased Msg4 receive samples are not TX evidence.
cfg=raStrictAnchorConfig();
cfg.phy.duplex.mode="TDD";
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
[~,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg,'RunFolder',root, ...
    'WriteArtifacts',false,'StopAfterStage','Msg3');
[prepared,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg, ...
    'Continuation',checkpoint,'StageAction','prepare_next_stage');
tx=prepared.PreparedTransmission;
assert(tx.StageName=="Msg4");
streams=struct('Msg4RxWaveform',zeros(size(tx.Waveform),'like',tx.Waveform));
[failed,~]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',checkpoint, ...
    'RuntimeStageWaveforms',streams);
assert(~failed.Msg4PDSCHCrcPass && ~failed.RACompleted && ...
    strlength(failed.Msg4PayloadHex)==0 && strlength(failed.Msg4TransmittedPayloadHex)>0);
fields=failed.ArtifactTables.msg4_dci_fields;
assert(height(fields)==12 && all(fields.Endpoint=="gNB_TX"), ...
    'Erased control reception must not publish decoded DCI fields.');
sixgr.phy.ra.exportRAEvidenceArtifacts(root,failed);
layout=sixgr.report.resultLayout(root);
published=readtable(fullfile(layout.ControlCSVDir,'msg4_dci_fields.csv'),'TextType','string');
assert(height(published)==12 && all(published.Endpoint=="gNB_TX") && ...
    isequal(published.Value,fields.Value));
decoded=jsondecode(fileread(fullfile(layout.ReportDir,'json','msg4_contention_resolution_decoded.json')));
assert(~decoded.CRCPass && strlength(string(decoded.PayloadHex))==0 && ...
    string(decoded.PayloadEvidenceRole)=="crc_valid_receiver_decoded_payload");
assert(strlength(strtrim(string(fileread(fullfile(layout.ReportDir,'text','msg4_payload.hex.txt')))))==0);
fprintf('RA_PAYLOAD_EXPORT_OWNERSHIP_PASS: actual erased Msg4 RX has no decoded payload or fields.\n');
ok=true;
end
