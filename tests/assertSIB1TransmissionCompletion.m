function assertSIB1TransmissionCompletion(owner,item)
% Assertions on a caller's ACTUAL completed shared SI, no new PHY execution.
% Copied metadata/sample mutations below are corruption tests, not received
% observations or physical cancellation/replacement experiments.
expected='sixgr:truth:SIB1TransmissionCompletionMismatch';
before=owner.Events.ExecutionTrace;
originalHash=item.Planes.Observation.sampleHash();
proof=sixgr.truth.verifySIB1TransmissionCompletion(owner,item);
assert(proof.PhysicalTransmissionVerified && ~proof.ReceiverExecutionClaimed && ...
    proof.ComponentID==item.Context.ComponentID && ...
    proof.OriginalPreparedContractSHA256==owner.originalSIB1PreparedContract(item.Context.ComponentID) && ...
    proof.ExecutedComponentNonzeroSampleCount==nnz(item.Context.Prepared.TransmitSamples) && ...
    proof.TransmitObservationScope=="aggregate_post_TX_RF_not_isolated_SI_power");
bad=item; bad.Context.EnqueueReceipt.OriginalSampleSHA256="changed";
reject(owner,bad,expected);
bad=item; bad.Context.Prepared.TransmitSamples(1)=bad.Context.Prepared.TransmitSamples(1)+1;
reject(owner,bad,expected);
% Identical IQ cannot authorize substituted publication metadata.
bad=item; bad.Context.Prepared.CopiedPublicationMetadata="not_original";
assert(isequaln(bad.Context.Prepared.TransmitSamples,item.Context.Prepared.TransmitSamples));
reject(owner,bad,expected);
bad=item; bad.Context.TransmitterPlane="ue_1_rx:post_rf";
reject(owner,bad,expected);
bad=item; bad.Planes.Segments={};
reject(owner,bad,expected);
bad=item; bad.Planes.Segments{end}.EndSampleExclusive=bad.Planes.Segments{end}.EndSampleExclusive-1;
reject(owner,bad,expected);
bad=item; segment=bad.Planes.Segments{end};
hit=find(string({segment.Execution.ExecutedContributors.TransmitterID})==proof.TransmitterID);
segment.Execution.ExecutedContributors(hit).Receipt.Components= ...
    segment.Execution.ExecutedContributors(hit).Receipt.Components([]);
bad.Planes.Segments{end}=segment;
reject(owner,bad,expected);
bad=item; segment=bad.Planes.Segments{end};
hit=find(string({segment.Execution.TX.ID})==proof.TransmitterID);
segment.Execution.TX(hit).Replay.RFOutputWaveformSHA256='changed';
bad.Planes.Segments{end}=segment;
reject(owner,bad,expected);
bad=item; o=item.Planes.Observation;
samples=o.readComplete(); samples(1)=samples(1)+1;
substitute=sixgr.phy.waveform.WaveformObservationBuffer( ...
    o.StartSample,o.EndSampleExclusive,o.SampleRateHz,o.NumReceiveAntennas);
substitute.append(sixgr.phy.waveform.WaveformChunk(samples,o.StartSample),o.SampleRateHz);
bad.Planes.Observation=substitute;
reject(owner,bad,expected);
assert(isequaln(before,owner.Events.ExecutionTrace) && ...
    item.Planes.Observation.sampleHash()==originalHash, ...
    'Completion verification must not mutate original execution or sample evidence.');
fprintf('SIB1_COMPLETION_PROOF_PASS original_shared_item=1 copied_corruption_negatives=9 new_RF_calls=0\n');
end

function reject(owner,item,expected)
try
    sixgr.truth.verifySIB1TransmissionCompletion(owner,item);
catch cause
    assert(strcmp(cause.identifier,expected),'Expected %s, got %s: %s', ...
        expected,cause.identifier,cause.message);
    return;
end
error('test:SIB1CompletionExpectedRejection','Expected %s.',expected);
end
