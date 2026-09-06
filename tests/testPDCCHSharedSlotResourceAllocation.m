function ok = testPDCCHSharedSlotResourceAllocation()
% Exact allocation and composite-waveform checks, not a complete slot runner.
for duplex = ["TDD", "FDD"]
    cfg = localConfig(duplex);
    bitsA = int8(mod((0:31).',2));
    bitsB = 1 - bitsA;
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
    [ledger, occupied] = sixgr.truth.PDCCHSlotResourceLedger.lookup( ...
        struct(), 21, 1, carrier);
    [a, ia] = sixgr.phy.dl.PDCCH_Tx(cfg, 'DCIBits',bitsA, ...
        'ReservedRECoordinates',occupied, 'OFDMModulate',false);
    ledger = sixgr.truth.PDCCHSlotResourceLedger.reserve( ...
        ledger,21,1,carrier,ia.AllocatedRECoordinates);
    saved = ledger;
    % The future UL grant uses the same current DL control occasion, not
    % its future PUSCH slot. Same RNTI deliberately exercises candidate 1
    % collision and forces actual candidate reassignment.
    [ledger, occupied] = sixgr.truth.PDCCHSlotResourceLedger.lookup(ledger,21,1,carrier);
    [b, ib] = sixgr.phy.dl.PDCCH_Tx(cfg, 'DCIBits',bitsB, ...
        'ReservedRECoordinates',occupied, 'OFDMModulate',false);
    assert(a.PDCCH.AllocatedCandidate ~= b.PDCCH.AllocatedCandidate);
    assert(isempty(intersect(ia.AllocatedRECoordinates,ib.AllocatedRECoordinates,'rows')));
    assert(numel(a.PDCCHInd) == 54*4 && numel(a.DMRSInd) == 18*4);
    ledger = sixgr.truth.PDCCHSlotResourceLedger.reserve( ...
        ledger,21,1,carrier,ib.AllocatedRECoordinates);
    assert(isequal(saved.Entries.Coordinates,ia.AllocatedRECoordinates), ...
        'A copied runtime checkpoint must not share a mutable map.');
    [~, allOccupied] = sixgr.truth.PDCCHSlotResourceLedger.lookup(ledger,21,1,carrier);
    localReject(@() sixgr.phy.dl.PDCCH_Tx(cfg,'DCIBits',bitsA, ...
        'ReservedRECoordinates',allOccupied), 'sixgr:phy:pdcch:NoFreeCandidate');
    localReject(@() sixgr.truth.PDCCHSlotResourceLedger.reserve( ...
        ledger,21,1,carrier,ia.AllocatedRECoordinates), 'sixgr:truth:PDCCHResourceCollision');

    % Different logical CORESET IDs do not legalize identical physical REs.
    cfgAlias = cfg;
    cfgAlias.phy.pdcch.coreset.id = 2;
    localReject(@() sixgr.phy.dl.PDCCH_Tx(cfgAlias,'DCIBits',bitsA, ...
        'ReservedRECoordinates',allOccupied), 'sixgr:phy:pdcch:NoFreeCandidate');
    % Different carrier-grid origins still identify the same CRB0 REs.
    cfgWide = cfg;
    cfgWide.phy.carrier.NStartGrid = 0;
    cfgWide.phy.carrier.NSizeGrid = 30;
    cfgWide.phy.pdcch.nStartBWP = 6;
    cfgWide.phy.pdcch.nSizeBWP = 24;
    localReject(@() sixgr.phy.dl.PDCCH_Tx(cfgWide,'DCIBits',bitsA, ...
        'ReservedRECoordinates',allOccupied), 'sixgr:phy:pdcch:NoFreeCandidate');
    % A later monitored symbol can use the same frequency resources.
    cfgLater = cfg;
    cfgLater.phy.pdcch.searchSpace.startSymbol = 3;
    [~, later] = sixgr.phy.dl.PDCCH_Tx(cfgLater,'DCIBits',bitsA, ...
        'ReservedRECoordinates',allOccupied,'OFDMModulate',false);
    assert(isempty(intersect(allOccupied,later.AllocatedRECoordinates,'rows')));
    [~, otherCell] = sixgr.truth.PDCCHSlotResourceLedger.lookup(ledger,21,2,carrier);
    assert(isempty(otherCell));
    [nextLedger, nextSlot] = sixgr.truth.PDCCHSlotResourceLedger.lookup(ledger,22,1,carrier);
    assert(isempty(nextSlot) && nextLedger.Slot == 22);
    localReject(@() sixgr.truth.PDCCHSlotResourceLedger.lookup(nextLedger,21,1,carrier), ...
        'sixgr:truth:PDCCHReservationTimeReversal');
    incompatibleCarrier = nrCarrierConfig('SubcarrierSpacing',60);
    localReject(@() sixgr.truth.PDCCHSlotResourceLedger.lookup(ledger,21,1,incompatibleCarrier), ...
        'sixgr:truth:PDCCHReservationNumerologyMismatch');

    % Produce a single OFDM buffer containing both DCIs, and propagate it
    % ONCE through real TDL-C. Known-location decoding here tests allocator
    % mapping; it is not claimed as multi-DCI blind-search qualification.
    compositeGrid = a.Grid + b.Grid;
    waveform = sixgr.phy.waveform.ofdmModulate(carrier,compositeGrid);
    channel = sixgr.link.initWaveformTruthChannelState( ...
        cfg,struct('Waveform',waveform),struct('OFDM',nrOFDMInfo(carrier)));
    [received, replay, channel] = sixgr.link.applyRuntimeFadingChannel(waveform,channel);
    assert(replay.RuntimeChannelStartSample == 0 && ...
        channel.RuntimeChannelState.CurrentSampleIndex == size(waveform,1));
    for item = 1:2
        if item == 1, tx = a; expected = bitsA; else, tx = b; expected = bitsB; end
        rx = sixgr.phy.dl.PDCCH_Rx(received,cfg,'Carrier',carrier, ...
            'PDCCH',tx.PDCCH,'K',32,'NoiseVar',1e-10);
        assert(rx.Ok && isequal(int8(rx.DCIBits),int8(expected)), ...
            'Both independently allocated DCIs must decode from the same faded waveform.');
    end
    % Ideal, already synchronized receiver input isolates blind decoding
    % from timing acquisition. Do not provide ExpectedDCIBits. Both same-UE
    % DCIs must survive as observed hypotheses, while the scalar API must
    % still refuse to select one arbitrarily.
    blindCfg = cfg;
    blindCfg.phy.pdcch.blindSearch = true;
    [scalarRX, setInfo] = sixgr.phy.dl.PDCCH_Rx(waveform,blindCfg, ...
        'Carrier',carrier,'PDCCH',a.PDCCH,'K',32,'NoiseVar',1e-12);
    hypotheses = setInfo.CRCValidHypotheses;
    assert(~scalarRX.Ok && scalarRX.AmbiguousValidHypotheses && numel(hypotheses) == 2);
    assert(any(cellfun(@(h) isequal(int8(h.DCIBits),bitsA) && h.ErrFlag == 0, hypotheses)) && ...
        any(cellfun(@(h) isequal(int8(h.DCIBits),bitsB) && h.ErrFlag == 0, hypotheses)), ...
        'Blind search must preserve both CRC-valid payloads without a transmit-bit oracle.');
end

% Exercise changed bandwidth, AL and CCE-to-REG mapping against the actual
% Toolbox resource generator. No assumed consecutive-CCE arithmetic.
for nRB = [24 48]
    for mapping = ["noninterleaved", "interleaved"]
        for level = [1 2 4 8]
            cfg = localConfig("TDD");
            cfg.phy.carrier.NSizeGrid = nRB;
            cfg.phy.pdcch.coreset.frequencyResources = ones(1,nRB/6);
            cfg.phy.pdcch.coreset.mappingType = mapping;
            cfg.phy.pdcch.aggregationLevel = level;
            cfg.phy.pdcch.aggregationLevels = [1 2 4 8];
            cfg.phy.pdcch.searchSpace.numCandidates = [8 8 4 2 1];
            [first, firstInfo] = sixgr.phy.dl.PDCCH_Tx(cfg, ...
                'DCIBits',bitsA,'ReservedRECoordinates',zeros(0,2),'OFDMModulate',false);
            levels = [1 2 4 8 16];
            count = first.PDCCH.SearchSpace.NumCandidates(levels == level);
            if count == 1
                localReject(@() sixgr.phy.dl.PDCCH_Tx(cfg,'DCIBits',bitsB, ...
                    'ReservedRECoordinates',firstInfo.AllocatedRECoordinates, ...
                    'OFDMModulate',false), 'sixgr:phy:pdcch:NoFreeCandidate');
            else
                [second, secondInfo] = sixgr.phy.dl.PDCCH_Tx(cfg,'DCIBits',bitsB, ...
                    'ReservedRECoordinates',firstInfo.AllocatedRECoordinates,'OFDMModulate',false);
                assert(isempty(intersect(firstInfo.AllocatedRECoordinates, ...
                    secondInfo.AllocatedRECoordinates,'rows')));
                assert(isempty(intersect([first.PDCCHInd;first.DMRSInd], ...
                    [second.PDCCHInd;second.DMRSInd])));
            end
        end
    end
end

% Check the active production caller carries reservations between DL and
% UL calls, not only the independent value-ledger API above.
source = fileread(fullfile('+sixgr','+truth','runWaveformLinkBundle.m'));
start = strfind(source,'function [state, qualifiedGrants] = localQualifyCoupledGrantsWithPDCCH');
finish = strfind(source,'function tf = localPDCCHPreAttachAssumptionApplies');
body = source(start:finish-1);
assert(contains(body,'state.PDCCHResourceLedger') && ...
    contains(body,'occupiedControlREs') && contains(body,'allocatedControlREs') && ...
    ~contains(body,'containers.Map'), ...
    'The active qualifier must share exact reservations rather than reset per-pass CCE counters.');
ok = true;
fprintf('PASS testPDCCHSharedSlotResourceAllocation: exact shared candidates and one faded composite in TDD/FDD.\n');
end

function cfg = localConfig(duplex)
cfg = struct();
cfg.run.seed = 717;
cfg.frequency.duplex_mode = duplex;
cfg.phy.duplex.mode = duplex;
cfg.phy.carrier = struct('NSizeGrid',24,'NStartGrid',6, ...
    'SubcarrierSpacing',30,'NCellID',1,'NSlot',0,'NFrame',1);
cfg.phy.pdcch = struct('enable',true,'dmrs',struct('enable',true), ...
    'rnti',101,'aggregationLevel',4,'aggregationLevels',4,'blindSearch',false);
cfg.phy.pdcch.coreset = struct('id',0,'duration',2, ...
    'frequencyResources',ones(1,4),'mappingType','noninterleaved');
cfg.phy.pdcch.searchSpace = struct('id',1,'startSymbol',0, ...
    'numCandidates',[0 0 2 0 0],'slotPeriodAndOffset',[1 0],'duration',1);
cfg.channel = struct('model','TDL','tdlProfile','TDL-C', ...
    'delaySpread_s',30e-9,'doppler_Hz',90,'channelFiltering',true, ...
    'normalizePathGains',true);
cfg.phy.fc_Hz = 4e9;
cfg.phy.nRxAnt = 1;
cfg.lls6g.userContext = struct('RuntimeCurrentDirection',"DL", ...
    'UEIndex',1,'RuntimeServingCellIndex',1);
end

function localReject(call, identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier), ...
        'Expected %s, received %s: %s',identifier,exception.identifier,exception.message);
    return;
end
error('testPDCCHSharedSlotResourceAllocation:MissingRejection', ...
    'Expected %s.',identifier);
end
