function ok=testRRCSetupCompleteReceiverLength()
% Actual coded PUSCH recovery with bounded tagged RRC payloads, not NR ASN.1.
% This isolates received message length. Allocation remains the existing
% configured procedure context; this is not received-DCI/access qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
ra=sixgr.mac.ra.RAConfig(cfg,'UEId',1,'AttemptId',1);
grant=sixgr.mac.ra.buildRARULGrant(ra);
message=sixgr.mac.ra.buildRRCSetupComplete('TransactionID',ra.RRCTransactionID, ...
    'SRB1LCID',ra.SRB1LCID,'UEIdentity','UE-1');
tx=sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg,ra,grant,message);
waveform=tx.Waveform;
[reference,decoded]=sixgr.phy.ra.recoverRRCSetupComplete(waveform,cfg,ra,tx);
assert(reference.Ok && isequal(reference.TransportBlock,tx.TransportBlock) && ...
    decoded.PayloadHash==message.PayloadHash && decoded.TransactionID==message.TransactionID && ...
    decoded.SRB1LCID==message.SRB1LCID && decoded.UEIdentity==message.UEIdentity);
assert(numel(reference.TransportBlock)>numel(message.PayloadBits), ...
    'This fixture must exercise actual TB padding after the in-band message.');

% Replay the identical received samples. Neither missing nor contradictory
% transmitter-only length metadata can alter a decoded message or its hash.
withoutLength=rmfield(tx,'RRCSetupCompleteBitLength');
[rx,actual]=sixgr.phy.ra.recoverRRCSetupComplete(waveform,cfg,ra,withoutLength);
localSameReception(rx,actual,reference,decoded);
for poisonedLength=[0,tx.TransportBlockSize+1,NaN]
    changed=tx; changed.RRCSetupCompleteBitLength=poisonedLength;
    [rx,actual]=sixgr.phy.ra.recoverRRCSetupComplete(waveform,cfg,ra,changed);
    localSameReception(rx,actual,reference,decoded);
end
assert(isequal(waveform,tx.Waveform));

% Encode a different actual waveform whose bounded in-band identity length
% is zero. Its PHY TB CRC is valid: the semantic parser must reject rather
% than rescue it with the transmitter's valid-looking payload length.
malformed=message;
malformed.PayloadBytes(4)=uint8(0);
malformed.PayloadBits(25:32)=int8(0);
malformed.PayloadHex=upper(string(reshape(dec2hex(malformed.PayloadBytes,2).',1,[])));
malformed.PayloadHash=sixgr.rrc.asn1.asn1SHA256Hex(malformed.PayloadBytes);
badTX=sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg,ra,grant,malformed);
assert(~isequal(badTX.Waveform,waveform) && ...
    badTX.RRCSetupCompleteBitLength==tx.RRCSetupCompleteBitLength);
cfgRx=sixgr.phy.ra.localizeRAPUSCHConfig(cfg,ra,badTX.Grant, ...
    ra.SetupCompleteSlot,'RRCSetupComplete');
badRX=sixgr.phy.ul.PUSCH_Rx(badTX.Waveform,cfgRx, ...
    'Carrier',badTX.Carrier,'PUSCH',badTX.PUSCH, ...
    'TransportBlockSize',double(badTX.TransportBlockSize), ...
    'TargetCodeRate',double(badTX.Grant.TargetCodeRate),'RV',double(badTX.Grant.RV), ...
    'InitialIMCSPerCodeword',double(badTX.Grant.MCS),'ExecutionProfile','ra_setup_complete');
assert(badRX.Ok && isequal(badRX.TransportBlock,badTX.TransportBlock) && ...
    all(badRX.TransportBlock(25:32)==0), ...
    'The negative must reach semantic parsing after an actual successful TB decode.');
localReject(@()sixgr.phy.ra.recoverRRCSetupComplete(badTX.Waveform,cfg,ra,badTX), ...
    'sixgr:mac:ra:InvalidRRCSetupComplete');
fprintf(['RRC_SETUP_COMPLETE_RECEIVER_LENGTH_PASS actual_PUSCH=1 same_IQ_metadata_isolation=1 ' ...
    'malformed_in_band_length_rejected=1 bounded_tagged_codec=1 MACRRCStandardsQualified=0\n']);
ok=true;
end

function localSameReception(rx,message,reference,expected)
assert(rx.Ok==reference.Ok && isequal(rx.TransportBlock,reference.TransportBlock) && ...
    isequaln(message,expected), ...
    'Transmitter-only payload length must not change decoded bytes or semantic evidence.');
end

function localReject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',identifier);
end
