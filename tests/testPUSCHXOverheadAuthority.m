function ok = testPUSCHXOverheadAuthority()
% Configured N_oh must agree across scheduler, frozen grants, Tx and Rx.
% TS 38.214 6.1.4.2: absent xOverhead means zero, including DFT-s-OFDM.
setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.useMex = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.frequency.bandwidth_hz = 20e6;
cfg.channel.bandwidth_Hz = 20e6;
cfg.phy.channelBandwidth_MHz = 20;
cfg.channel.subcarrierSpacing_kHz = 30;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.codeRate = 0.3;
cfg.phy.pusch.prbSet = 0:5;
cfg.phy.pusch.symbolAllocation = [0 14];
cfg.phy.pusch.mappingType = "A";
cfg.phy.pusch.dmrs.portSet = 0;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.ptrs.enable = false;
cfg = withCanonicalSchedulerTiming(cfg);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);

for transform = [false true]
    cfg.phy.pusch.transformPrecoding = transform;
    for overhead = [0 6 12 18]
        cfg.phy.pusch.xOverhead = overhead;
        [~, allocation, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg);
        reference = nrTBS('QPSK', 1, 6, allocation.NREPerPRB, 0.3, overhead);
        scheduler = sixgr.l2.mac.SchedulerRR(cfg, "Direction", "UL");
        [scheduled, ~, ~, info] = scheduler.estimateTBS( ...
            'QPSK', 1, 6, [0 14], 0.3, "ForceExact", true);
        assert(scheduled == reference && info.XOverhead == overhead, ...
            "Scheduler changed configured overhead for TransformPrecoding=%d.", transform);
        [tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
            "Carrier", carrier, "PUSCH", pusch, "TargetCodeRate", 0.3);
        assert(tx.TransportBlockSize == reference && tx.XOverhead == overhead);
        [samples, noise] = sixgr.phy.waveform.addOccupiedREAWGN( ...
            tx.Waveform, carrier, 45, "Seed", 63000+overhead+100*transform);
        % Deliberately omit TransportBlockSize: the receiver must derive it
        % from the same configuration, without a transmitter TBS oracle.
        rx = sixgr.phy.ul.PUSCH_Rx(samples, cfg, ...
            "Carrier", carrier, "PUSCH", pusch, "TargetCodeRate", 0.3, ...
            "NoiseVar", noise.GridNoiseVariance, "NoiseVarDomain", "grid");
        assert(~rx.CRCError && isequal(int8(rx.TransportBlock(:)), int8(tx.TransportBlock(:))), ...
            "Configured overhead must preserve exact TB/CRC for both UL waveforms.");
    end
    absent = cfg;
    absent.phy.pusch = rmfield(absent.phy.pusch, 'xOverhead');
    if isfield(absent.phy.pusch, 'XOverhead')
        absent.phy.pusch = rmfield(absent.phy.pusch, 'XOverhead');
    end
    scheduler = sixgr.l2.mac.SchedulerRR(absent, "Direction", "UL");
    [scheduled, ~, ~, info] = scheduler.estimateTBS( ...
        'QPSK', 1, 6, [0 14], 0.3, "ForceExact", true);
    assert(info.XOverhead == 0 && scheduled == nrTBS( ...
        'QPSK', 1, 6, allocation.NREPerPRB, 0.3, 0));
end

% Freeze one nonzero-overhead grant, then change the ambient configuration.
% This must replay the issued coding allocation, including through the
% public WaveformPHY adapter and the payloadless replay-template cache.
cfg.phy.pusch.xOverhead = 6;
cfg.phy.pusch.transformPrecoding = false;
[~, allocation] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg);
tbs = nrTBS('QPSK', 1, 6, allocation.NREPerPRB, 0.3, 6);
grant = struct('Direction','UL','RNTI',71,'PRBSet',0:5, ...
    'SymbolAllocation',[0 14],'MappingType','A','Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',0.3,'XOverhead',6, ...
    'TBSBits',tbs,'TBSBytes',tbs/8,'RV',0);
grant.PHYGrant = sixgr.phy.grant.freezePHYGrant(cfg, "UL", grant);
cfg.phy.pusch.xOverhead = 0;
projected = sixgr.phy.grant.applyPHYGrantToConfig(cfg, grant.PHYGrant);
assert(projected.phy.pusch.xOverhead == 6);
bits = int8(mod((1:tbs).', 2));
phy = sixgr.system.WaveformPHY(cfg, struct('StrictMode',true));
[decoded, ~] = phy.decode(struct('Direction','UL','Grant',grant, ...
    'TransportBlockBits',bits,'SINR_dB',45));
assert(decoded && phy.LastReplay.TransportBlockSize == tbs && ...
    phy.LastReplay.TransmittedTransportBlockSHA256 == string(sixgr.util.sha256Hex(uint8(bits))));
cached = sixgr.system.waveform.replayGrant(cfg, 'UL', grant, [], 45, 'StrictMode',true);
zeroGrant = rmfield(grant, 'PHYGrant');
zeroGrant.XOverhead = 0;
zeroGrant.TBSBits = nrTBS('QPSK', 1, 6, allocation.NREPerPRB, 0.3, 0);
zeroGrant.TBSBytes = zeroGrant.TBSBits/8;
zeroGrant.PHYGrant = sixgr.phy.grant.freezePHYGrant(cfg, 'UL', zeroGrant);
assert(strcmp(grant.PHYGrant.GrantContextId, zeroGrant.PHYGrant.GrantContextId), ...
    "Cache regression must exercise equal occasion IDs with different coding snapshots.");
uncached = sixgr.system.waveform.replayGrant(cfg, 'UL', zeroGrant, [], 45, 'StrictMode',true);
assert(cached.TransportBlockSize == tbs && ...
    uncached.TransportBlockSize == zeroGrant.TBSBits && zeroGrant.TBSBits ~= tbs, ...
    "A shared occasion ID must not reuse a different frozen TBS overhead.");
badGrant = grant;
badGrant.XOverhead = 0;
caught = false;
try
    sixgr.system.waveform.replayGrant(cfg, 'UL', badGrant, bits, 45, 'StrictMode',true);
catch ME
    caught = string(ME.identifier) == "sixgr:system:WaveformReplay:FrozenXOverheadMismatch";
end
assert(caught, "Conflicting frozen and top-level overhead must be rejected.");
fprintf('PUSCH_XOVERHEAD_AUTHORITY_PASS: CP/DFT x 0/6/12/18, absent=0, frozen replay and conflict rejection\n');
ok = true;
end
