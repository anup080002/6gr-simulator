function ok=testRuntimeHARQFeedbackPhysicalPublication(transport,outputRoot)
% Actual shared DL reception and independently completed PUCCH/PUSCH UCI.
% Component fixture: does not qualify full access or low-SNR missed-DCI rates.
if nargin<1, transport="PUCCH"; end
assert(any(string(transport)==["PUCCH","PUSCH"]));
root=fileparts(which('setup6GRSimToolkit'));
if nargin<2, outputRoot=tempname(fullfile(root,'logs')); end
isPUCCH=string(transport)=="PUCCH";
fixture='lls_tdd_pusch_independent_harq_csi_fixture.yaml';
if isPUCCH, fixture='lls_tdd_pucch_independent_harq_csi_sr_fixture.yaml'; end
config=fullfile(root,'simulator','configs','scenarios',fixture);
[passed,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    outputRoot,config,false,true,false,false,isPUCCH,2,false,true);
assert(passed);
% The same actually decoded attempts must carry the receive clock through
% the runtime timeline, not just the transmit clock used for HARQ RTT.
attempts=state.HARQTimelineTable;
% The public completion path must supply unique transport goodput for actual
% DL and UL decodes, separately from packet/application delivery.
credit=state.TransportGoodputLedger;
assert(numel(credit.Key)==height(attempts) && ...
    sum(credit.PayloadBits)==sum(attempts.OriginalTBSBits));
for direction=["DL","UL"]
    rows=string(attempts.Direction)==direction;
    stats=state.(direction+"Stats");
    assert(stats(1).GoodBitsSum==sum(attempts.OriginalTBSBits(rows)), ...
        'Actual receiver completions must credit the unique original TB size.');
end
assert(~isempty(attempts) && all(isfinite(attempts.DataDecodeAvailableAtSample)) && ...
    all(attempts.DataDecodeAvailableAtSample>=attempts.DataReceiveSymbolEndSampleExclusive));
for index=1:height(attempts)
    row=table2struct(attempts(index,:));
    clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime( ...
        state,row.Slot,row.FeedbackDueSlot,row);
    assert(clock.TimingAuthority=="received_data_result_availability_sample" && ...
        clock.DeliveryTime_s==row.DataDecodeAvailableAtSample/row.DataReceiveSampleRateHz);
end
% Real traffic arrival -> finalized TX reservation -> actual decoder -> SDU
% timing. Metadata mapping must not be promoted to application-byte delivery.
SDU=state.PacketSDULedgerTable; packets=state.PacketDeliveryLedgerTable;
% Preserve actual measurements even if a later assertion exposes a defect.
sixgr.util.csvWriteTable(fullfile(outputRoot,'physical_packet_sdu_delivery.csv'),SDU,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(outputRoot,'physical_packet_arrivals.csv'),packets,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(outputRoot,'physical_packet_harq_attempts.csv'),attempts,'PreserveSchema',true);
assert(~isempty(SDU) && all(SDU.DeliverySuccess) && all(SDU.FirstSuccessDelivery));
assert(all(SDU.DeliveryEvidenceMode=="CRC_CONFIRMED_PACKET_MAPPING") && ...
    ~any(SDU.ProtocolPayloadSameWaveformTruth) && ~any(SDU.ProtocolDecodedBitExact));
assert(~any(packets.DeliverySuccess) && ~any(packets.SameWaveformProtocolComplete));
assert(all(packets.ProtocolReassemblyStatus=="protocol_stack_not_enabled"));
for k=1:height(SDU)
    match=string(attempts.TBId)==SDU.TransportBlockId(k) & ...
        string(attempts.Direction)==SDU.Direction(k) & attempts.UEIndex==SDU.UEIndex(k);
    assert(nnz(match)==1 && attempts.CombinedDecodeOK(match));
    actual=attempts(match,:);
    assert(SDU.DeliveryAvailableAtSample(k)==actual.DataDecodeAvailableAtSample && ...
        SDU.DeliveryTime_s(k)==actual.DataDecodeAvailableAtSample/actual.DataReceiveSampleRateHz && ...
        SDU.HARQAttemptCount(k)==1 && SDU.NDIEpoch(k)==actual.NDIEpoch);
end
assert(sum(SDU.PayloadBits)==sum(packets.OfferedBits) && all(packets.RemainingBits==0));
assert(all(packets.CRCConfirmedMappedBits==packets.OfferedBits) && ...
    all(packets.CompletedApplicationBits==0 & packets.ReservedInFlightBits==0 & ...
    packets.UnresolvedReservedBits==0 & packets.HARQReleasedUndeliveredBits==0 & ...
    packets.BitConservationErrorBits==0), ...
    'Actual decoded metadata ranges must reconcile without claiming application delivery.');
for k=1:height(packets)
    owned=string(attempts.Direction)==packets.Direction(k) & attempts.UEIndex==packets.UEIndex(k);
    assert(packets.HARQAttemptCount(k)==numel(unique(string(attempts.PHYGrantContextId(owned)))));
end
% Exercise the public live snapshot after actual physical feedback completion,
% not only the reducer invoked by the earlier data receiver callback.
state=sixgr.truth.CoupledTruthRuntime.writeLiveStateTables(state,outputRoot);
localAssertLivePerformanceEvidence(state,outputRoot);
publishedPackets=sixgr.util.csvReadTable(fullfile(outputRoot,'packet_flow','csv', ...
    'live_application_packet_delivery_ledger.csv'));
assert(isequal(double(publishedPackets.CRCConfirmedMappedBits),double(packets.CRCConfirmedMappedBits)) && ...
    all(publishedPackets.BitConservationErrorBits==0 & publishedPackets.CompletedApplicationBits==0));
try
    sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,6,10);
    error('test:ExpectedFailure','Shared runtime accepted missing receive timing.');
catch ex
    assert(strcmp(ex.identifier,'sixgr:protocol:MissingDataDeliveryTiming'));
end
if isPUCCH
    T=state.ControlTrials.PUCCH;
    paired=T(T.ExpectedBitCount>1 & T.DecodedBitCount==T.ExpectedBitCount,:);
    assert(~isempty(paired),'Require actual combined PUCCH reception.');
    assert(all(paired.BitsCompared==paired.ExpectedBitCount));
    assert(all(isfinite(paired.BitErrors) & paired.BitErrors>=0 & ...
        paired.BitErrors<=paired.BitsCompared));
    assert(all(string(paired.BitComparisonStatus)=="complete_equal_width_bit_comparison"));
    population=sixgr.truth.summarizePUCCHPayloadDelivery(T);
    assert(population.Available && population.DeliveredBits>0);
end
F=state.SharedGNBUCIHARQTable;
assert(all(F.SweepPointIndex==state.CurrentSweepPointIndex) && ...
    all(F.ConfiguredSNR_dB==state.CurrentSNR_dB));
artifacts=sixgr.truth.exportLLSLiveDerivedTables(state.CfgMobility, ...
    outputRoot,struct(),struct(),struct(),state);
assert(isequaln(artifacts.RuntimeHARQ.FeedbackObservationTable,F), ...
    'The scenario publication handoff must retain actual UCI receiver rows.');
L=artifacts.RuntimeHARQ.TransmitterLifecycleTable;
assert(~isempty(L) && all(strlength(string(L.TBId))>0) && ...
    all(L.SweepPointIndex==state.CurrentSweepPointIndex));
assert(~any(ismember(["CrcPass","FirstSuccessDelivery","CountedGoodputBits"], ...
    string(L.Properties.VariableNames))), ...
    'TX observed feedback must not be published as data-receiver success.');
savedLifecycle=readtable(artifacts.RuntimeHARQ.TransmitterLifecycleCSV,'TextType','string');
assert(height(savedLifecycle)==height(L) && isequal(string(savedLifecycle.TBId),string(L.TBId)));
beforeLifecycleBytes=fileread(artifacts.RuntimeHARQ.TransmitterLifecycleCSV);
persistedState=rmfield(state,intersect(fieldnames(state), ...
    {'DLHarq','ULHarq','HARQTransmitterLifecycleArchive'}));
restored=sixgr.truth.exportLLSLiveDerivedTables(state.CfgMobility, ...
    outputRoot,struct(),struct(),struct(),persistedState);
assert(strcmp(beforeLifecycleBytes,fileread(restored.RuntimeHARQ.TransmitterLifecycleCSV)) && ...
    height(restored.RuntimeHARQ.TransmitterLifecycleTable)==height(L), ...
    'Refinalization must retain exact lifecycle CSV bytes without reconstructing terminal state.');
if ~isPUCCH
    trace=state.PUCCHGrantTraceTable;
    csi=trace.MultiplexedOnPUSCH & startsWith(string(trace.PUCCHGrantId),'PUCCH-CSI-');
    assert(any(csi) && all(trace.BitsCompared(csi)>0) && all(trace.BitErrors(csi)==0), ...
        'Actual successfully received PUSCH CSI must retain its complete paired bit population.');
end
published=sixgr.truth.publishRuntimeHARQDiagnostics(state.CfgMobility, ...
    fullfile(outputRoot,'air_interface'),artifacts.RuntimeHARQ);
P=published.PacketTable; dl=P(string(P.Direction)=="DL",:);
assert(height(dl)==height(F) && all(dl.FeedbackObservationAvailable));
assert(all(dl.FeedbackTransport==string(transport)));
assert(isequal(logical(dl.ACK),logical(F.ObservedAck)) && ...
    isequal(logical(dl.DTX),string(F.FeedbackOutcome)=="DTX"));
assert(all(isnan(P.FeedbackBits)),'Do not infer coded feedback overhead.');
assert(all(isfinite(dl.DataTransmitSymbolStartSample)));
assert(all(dl.DataTransmitSampleRateHz==dl.FeedbackSampleRateHz));
measured=1000*(dl.FeedbackAvailableAtSample-dl.DataTransmitSymbolStartSample)./dl.DataTransmitSampleRateHz;
assert(all(abs(measured-dl.FeedbackDispositionLatency_ms)<1e-12));
usable=dl.DTX==0;
assert(any(usable),'Fixture must decode usable independent feedback.');
assert(all(abs(dl.RTT_ms(usable)-measured(usable))<1e-12));
assert(all(isnan(dl.RTT_ms(~usable))));
assert(all(dl.RTTStatus(usable)=="measured_independent_usable_feedback_completion"));
fprintf('PHYSICAL_HARQ_PUBLICATION_PASS transport=%s logical_bits=%d folder=%s\n', ...
    transport,height(F),outputRoot);
ok=true;
end

function localAssertLivePerformanceEvidence(state,outputRoot)
% The counters above come from actual shared DL/UL receptions. This checks
% their production snapshot, not another synthetic PHY success population.
path=fullfile(outputRoot,'reports','csv','live_user_performance_snapshot.csv');
assert(isfile(path),'test:LivePerformanceSnapshotMissing', ...
    'The lightweight live writer must publish current performance evidence.');
T=sixgr.util.csvReadTable(path);
required=["UEIndex","FidelityLevel","AggregationStartSample", ...
    "AggregationEndSampleExclusive","AggregationSampleRateHz", ...
    "AggregationDuration_s","AggregationClockBasis", ...
    "DL_ScheduledBits","UL_ScheduledBits", ...
    "DL_UniqueDeliveredTBBits","UL_UniqueDeliveredTBBits"];
assert(all(ismember(required,string(T.Properties.VariableNames))), ...
    'test:LivePerformanceProvenanceMissing', ...
    'Run-average rates require their actual bit numerators and sample-clock denominator.');
fs=state.SharedWaveformStream.SampleRateHz;
stop=state.SharedWaveformStream.Events.NextSampleIndex;
assert(stop>0 && height(T)==state.NumUsers && ...
    all(T.FidelityLevel=="waveform_level") && ...
    all(T.AggregationStartSample==0) && ...
    all(T.AggregationEndSampleExclusive==stop) && ...
    all(T.AggregationSampleRateHz==fs) && ...
    all(abs(T.AggregationDuration_s-stop/fs)<1e-12) && ...
    all(T.AggregationClockBasis=="completed_shared_physical_sample_clock"), ...
    'test:LivePerformanceClockAuthority', ...
    'A scheduled slot end cannot substitute for the completed physical stream clock.');
for ue=1:state.NumUsers
    row=T(T.UEIndex==ue,:);
    assert(height(row)==1);
    for direction=["DL","UL"]
        stats=state.(direction+"Stats");
        stats=stats(ue);
        assert(row.(direction+"_ScheduledBits")==stats.ScheduledBitsSum && ...
            row.(direction+"_UniqueDeliveredTBBits")==stats.GoodBitsSum);
        if stats.Frames>0
            expected=stats.GoodBitsSum/(stop/fs)/1e6;
            assert(abs(row.(direction+"_Goodput_Mbps")-expected)<1e-12 && ...
                abs(row.(direction+"_Throughput_Mbps")- ...
                stats.ScheduledBitsSum/(stop/fs)/1e6)<1e-12);
        else
            assert(isnan(row.(direction+"_Goodput_Mbps")) && ...
                isnan(row.(direction+"_Throughput_Mbps")), ...
                'An unexecuted direction must not acquire a measured zero throughput.');
        end
    end
end
end
