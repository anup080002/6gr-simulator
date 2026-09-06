function ok = testPDSCHTransmitReceiveAuthoritySeparation()
% Contract-level waveform test: TX scheduling is not RX decode evidence.
for duplex = ["TDD", "FDD"]
    for rank = [1 2 4]
        fixture = localExactTBSFixture(rank);
        [scheduled, ue, frame, harq] = localScheduledInputs(fixture);
        assignment = sixgr.pdsch.PDSCHAssignmentFactory.fromScheduledDCI( ...
            scheduled,ue,frame,harq);
        assert(assignment.Profile == "connected_strict" && ...
            assignment.Source == "scheduled_dci+ue_context");
        assert(assignment.get('ControlAuthority') == "transmitter_scheduled_dci" && ...
            ~assignment.get('DCICRCPass') && ~assignment.get('DCIRNTIMatch') && ...
            isnan(assignment.get('DecodedRNTI')) && assignment.get('DecodedDCIId') == "");
        context = StrictPDSCHChainFixture.integrationContext( ...
            assignment, fixture.PrecoderBundle);
        cfg = struct('frequency',struct('duplex_mode',duplex));
        [tx, info] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
            'Carrier',fixture.Carrier, 'Assignment',assignment, ...
            'ResourcePlan',fixture.ResourcePlan, ...
            'ReferenceSignalConfig',fixture.ReferenceConfig, ...
            'PrecoderBundle',fixture.PrecoderBundle, ...
            'IntegrationContext',context, ...
            'TransportBlockBits',fixture.TransportBlocks);
        assert(info.CanonicalDelegation && ~isempty(tx.Waveform) && ...
            size(tx.Waveform,2) == rank && any(abs(tx.Waveform(:)) > 0));
        assert(tx.Assignment.get('ControlAuthority') == "transmitter_scheduled_dci" && ...
            ~tx.Assignment.get('DCICRCPass'), ...
            'Generating a coded waveform must not manufacture a DCI decode.');

        localReject(@() sixgr.pdsch.PDSCHReceiver(tx.Waveform,assignment, ...
            fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
            fixture.ReceiverConfig,'PrecoderBundle',fixture.PrecoderBundle, ...
            'IntegrationContext',context), ...
            'sixgr:pdsch:PDSCHReceiver:TransmitterAssignmentAtReceiver');
        localReject(@() sixgr.pdsch.PDSCHAssignmentFactory.fromDecodedDCI( ...
            scheduled,ue,frame,harq), 'sixgr:pdsch:DCICRCFailed');
        forged = assignment.toStruct();
        forged.DCICRCPass = true;
        localReject(@() sixgr.pdsch.PDSCHSchedulingAssignment(forged), ...
            'sixgr:pdsch:UnvalidatedDecodedDCIAssignment');

        % Context/timing validation remains active before transmitter use.
        staleUE = ue;
        staleUE.EpochCurrent = false;
        localReject(@() sixgr.pdsch.PDSCHAssignmentFactory.fromScheduledDCI( ...
            scheduled,staleUE,frame,harq), 'sixgr:pdsch:InvalidEpochCurrent');
        wrongTime = scheduled;
        wrongTime.K0 = 1;
        localReject(@() sixgr.pdsch.PDSCHAssignmentFactory.fromScheduledDCI( ...
            wrongTime,ue,frame,harq), 'sixgr:pdsch:AssignmentSlotBindingMismatch');
    end
end

% The same receiver boundary also rejects existing common-procedure TX
% assignments. Previously their valid class/profile could reach RX directly.
fixture = StrictPDSCHChainFixture.create(1, 'NPRB',2);
[scheduled,ue,frame,harq] = localScheduledInputs(fixture);
scheduled.Format = "1_0";
scheduled.RNTIType = "RA-RNTI";
scheduled.RNTI = 1;
assignment = sixgr.pdsch.PDSCHAssignmentFactory.fromScheduledDCI(scheduled,ue,frame,harq);
assert(assignment.Profile == "ra_si_strict");
localReject(@() sixgr.pdsch.PDSCHReceiver([],assignment,fixture.ResourcePlan), ...
    'sixgr:pdsch:PDSCHReceiver:TransmitterAssignmentAtReceiver');
ok = true;
fprintf('PASS testPDSCHTransmitReceiveAuthoritySeparation: scheduled TX waveforms without invented RX authority.\n');
end

function [scheduled,ue,frame,harq] = localScheduledInputs(fixture)
% Explicit unit-test schedule and active context; not a measured DCI event.
scheduled = fixture.Assignment.toStruct();
scheduled.Present = true;
scheduled.FieldsInRange = true;
scheduled.Id = "scheduled-unit-dci-rank-" + string(scheduled.NumLayers);
scheduled.Format = "1_1";
scheduled.CRCPass = false;
scheduled.RNTIMatch = false;
scheduled.DecodedRNTI = NaN;
scheduled.PDCCHAbsoluteSlot = 0;
scheduled.K0 = 0;
scheduled.TCIStateId = 0;
scheduled.SearchSpaceId = "1";
scheduled.CORESETId = "1";
scheduled.TDRARowIndex = 0;
scheduled.TDRAListId = "unit-full-slot";
scheduled.FDRAType = "type1";
scheduled.FrequencyDomainAssignmentRaw = "0:2";
scheduled.SLIV = 27; % Explicit normal-CP S=0, L=14 test allocation.
ue = scheduled;
for field = ["ActiveBWPContextPresent","EpochCurrent","ServingCellActive", ...
        "MCSContextSupported","TCIStateActive"]
    ue.(field) = true;
end
frame = struct('AbsoluteSlot',0,'ResourceAvailable',true);
harq = struct('ProcessId',scheduled.HARQProcessId,'Consistent',true);
end

function fixture = localExactTBSFixture(rank)
% The helper's default short TB belongs to isolated codec tests. This
% connected-schedule test instead uses nrTBS from the actual allocation.
fixture = StrictPDSCHChainFixture.create(rank, 'NPRB',2);
pdsch = sixgr.pdsch.PDSCHConfigMaterializer.fromAssignment( ...
    fixture.Assignment,fixture.ReferenceConfig.toStruct());
[~, allocationInfo] = nrPDSCHIndices(fixture.Carrier,pdsch);
tbs = nrTBS(pdsch.Modulation,pdsch.NumLayers,numel(pdsch.PRBSet), ...
    allocationInfo.NREPerPRB,fixture.Assignment.get('TargetCodeRatePerCodeword'), ...
    fixture.Assignment.get('XOverhead'));
fixture = StrictPDSCHChainFixture.create(rank, 'NPRB',2,'TransportBlockSize',tbs);
end

function localReject(call, identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier), ...
        'Expected %s, received %s: %s',identifier,exception.identifier,exception.message);
    return;
end
error('testPDSCHTransmitReceiveAuthoritySeparation:MissingRejection', ...
    'Expected %s.',identifier);
end
