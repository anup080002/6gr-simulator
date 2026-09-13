function ok=testPUCCHReceiverAssignmentEquivalence()
% Same actual transmitter IQ, different independent receiver assignment.
% Standalone fixture equivalence; not shared-runtime/codebook qualification.
setup6GRSimToolkit('Verbose',false);
for format=0:4
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[]);
    context=f.Context;
    data=struct('ObservationID',"independent-fixture-"+format, ...
        'ResourceID',f.Assignment.Resource.ID,'RNTI',f.Assignment.Data.RNTI, ...
        'AbsoluteSlot0',double(f.Carrier.NSlot)+double(f.Carrier.NFrame)*f.Carrier.SlotsPerFrame, ...
        'Source','standalone_receiver_resource_fixture', ...
        'TimingSource','prescribed_fixture_slot');
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(data,f.RRCContext,context);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
    legacy=sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform,f.Carrier,f.Assignment,context);
    received=sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform,f.Carrier,assignment,context);
    assert(isequal(received.DecodedSequence1,legacy.DecodedSequence1) && ...
        isequal(received.DecodedSequence2,legacy.DecodedSequence2));
    assert(isequaln(received.DetectionMetric,legacy.DetectionMetric) && received.DTX==legacy.DTX);
    serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(f.Report);
    assert(~received.DTX && received.CRCPassed);
    assert(isequal(received.DecodedSequence1,serialized.Sequence1.Bits));
    assert(isequal(received.DecodedSequence2,serialized.Sequence2.Bits));
    assert(received.ReceiverOnlyAssignment && ~legacy.ReceiverOnlyAssignment);
    fprintf('PUCCH_RECEIVER_ASSIGNMENT_EQUIVALENCE format=%d exact_decoded_bits=%d\n', ...
        format,numel(received.DecodedSequence1)+numel(received.DecodedSequence2));
end
ok=true;
end
