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
    outputRoot,config,false,true,false,false,isPUCCH);
assert(passed);
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
