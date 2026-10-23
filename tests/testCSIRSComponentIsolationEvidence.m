function ok=testCSIRSComponentIsolationEvidence()
% Actual shared one-resource/one-port CSI-only measurement component, then
% declared finite-dependency negatives. No one-port Type-I report, received
% UCI, PDSCH, n40 multiport decomposition, absolute-power/accuracy claim.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; cleanup=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
localGenericEquivalence();
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=tempname; mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder);
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,30);
cfg.run.rootRunFolder=folder;
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csirs.period_slots=1; cfg.phy.csirs.offset_slots=0;
cfg.phy.csirs.runtimeChannelEstimator='nr_channel_estimate';
cfg.phy.synchronization=struct('maxTimingUncertaintySamples',0);
cfg.phy.rx.cfoCorrectionEnabled=false;
cfg.measurements.csiSelectionQuality.Enabled=false;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
% Explicit component fixture: retain the physical 4TX/2RX architecture and
% actual configured first beam, installing only one logical CSI port/RE map.
% The inherited Type-I report is NOT invoked or relabelled as one-port CSI.
cfg.phy.csirs.nPorts=1; cfg.phy.csirs.numPorts=1; cfg.phy.csirs.numResources=1;
cfg.phy.csirs.resourceID=17; cfg.phy.csirs.resourceIDs=17;
cfg.phy.csirs.rowNumber=2; cfg.phy.csirs.rowNumbers=2;
cfg.phy.csirs.density='one'; cfg.phy.csirs.cdmType='noCDM';
cfg.phy.csirs.symbolLocations=4; cfg.phy.csirs.symbolLocationsByResource=4;
cfg.phy.csirs.subcarrierLocations=0; cfg.phy.csirs.subcarrierLocationsByResource=0;
cfg.phy.csirs.rbOffset=0; cfg.phy.csirs.rbOffsetsByResource=0;
cfg.phy.csirs.numRB=cfg.phy.carrier.NSizeGrid;
cfg.phy.csirs.numRBsByResource=cfg.phy.carrier.NSizeGrid;
cfg.phy.csirs.precoderMatrices=cfg.phy.csirs.precoderMatrices(:,1,1);
cfg.phy.csirs.precoderBeamIndices=cfg.phy.csirs.precoderBeamIndices(1,1);
% This receiver component has NO installed CSI report. Do not retain the
% inherited four-port Type-I request beside a one-port measurement, and do
% not fabricate a one-port Type-I request merely to satisfy its port guard.
% The native receive API can retain measured state without report encoding.
cfg.phy.csi.reportConfiguration=[];
for flag=["reportCSI","reportCQI","reportPMI","reportRI","reportCRI"]
    cfg.phy.csi.(flag)=false;
end
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),1);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,30,12);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[cfgUE,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
[state,queued]=sixgr.truth.queueSharedPeriodicCSIRS(state,cfgUE,1,1,1,1,1,30);
assert(queued && owner.hasPending('CSIRS',1));
count=0;
state=owner.advanceSlot(state,cfg,@receive); %#ok<NASGU>
assert(count==1 && isempty(owner.Pending),'Exactly one actual CSI capture must complete.');
fprintf('CSIRS_COMPONENT_ISOLATION_PASS actual_shared_measurements=1 port3000=1 power_comparison=0 accuracy=0 evidence=%s\n',folder);
ok=true;

    function next=receive(next,items)
        for item=reshape(items,1,[])
            assert(item.Kind=="CSIRS");
            p=item.Context.Prepared;
            assert(isempty(p.ReceiverConfig.phy.csi.reportConfiguration) && ...
                ~p.ReceiverConfig.phy.csi.reportCSI && ~p.ReceiverConfig.phy.csi.reportCQI && ...
                ~p.ReceiverConfig.phy.csi.reportPMI && ~p.ReceiverConfig.phy.csi.reportRI && ...
                ~p.ReceiverConfig.phy.csi.reportCRI, ...
                'The original queued receiver must be measurement-only, not an invented one-port Type-I report.');
            [~,pre,~,replay,actual]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
            [desired,source]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,item.Context.DesiredReferencePlane);
            rx=sixgr.phy.refsig.receiveCSIRSWaveform(p.Carrier,p.ReceiverConfig, ...
                actual.readComplete(),pre.readComplete(),[0 0],replay);
            assert(rx.CSIRSObservation.Observed && rx.CSIRSObservation.ChannelEstimateAvailable && ...
                rx.CSIRSInfo.NumCSIRSPorts==1 && rx.PhysicalMeasurementDemodulationReceiptAvailable);
            before=rng; clock=owner.Events.NextSampleIndex;
            originalRX=rx.CSIRSChannelEstimate; originalPower=rx.CSIRSObservation.MeasurementPhysicalResourcesJSON;
            hashes=[pre.sampleHash() desired.sampleHash() actual.sampleHash()];
            evidence=sixgr.truth.sharedCSIRSComponentIsolation(item,rx,desired,source,replay,owner);
            token=string(jsonencode(evidence)); digest=sixgr.util.sha256Hex(char(token));
            scope="actual_shared_single_port_CSI_measurement_no_TypeI_report_no_RSRP_accuracy";
            demodToken=rx.PhysicalMeasurementDemodulationReceiptJSON;
            save(fullfile(folder,'original_isolation.mat'),'evidence','demodToken','scope');
            assert(evidence.Available && evidence.Isolation.Available, ...
                'test:CSIIsolationUnavailable','Original component isolation unavailable: %s',evidence.Status);
            assert(evidence.Transmission.ReferencePort==3000 && evidence.ResourceCount==1 && ...
                evidence.LogicalPortCounts==1 && ~evidence.PowerComparisonPerformed && ...
                ~evidence.IndependentRSRPAccuracyQualified && ~evidence.ReferenceUsedByReceiver && ...
                evidence.AdditionalTimingAcquisitions==0 && evidence.AdditionalOFDMDemodulations==0 && ...
                evidence.AdditionalRFExecutions==0 && evidence.AdditionalChannelExecutions==0);
            assert(evidence.Measurement.InputSHA256==pre.sampleHash() && ...
                evidence.Measurement.DesiredObservationSHA256==desired.sampleHash() && ...
                evidence.Transmission.ComponentSHA256==sixgr.phy.waveform.WaveformHash.numeric(p.TransmitSamples));
            assert(evidence.ReceiveElementBinding.Available && ...
                ~evidence.ReceiveElementBinding.RFReferenceQualified && ...
                ~evidence.ReceiveElementBinding.PowerUnitQualified && ...
                ~evidence.ReceiveElementBinding.StandardizedReferencePointQualified && ...
                ~evidence.ReceiveElementBinding.HardwareConformanceVerified && ...
                ~evidence.ReceiveBranchBinding.Available && ...
                evidence.ReferencePlane=="internal_physical_receive_element_before_RX_front_end" && ...
                evidence.Measurement.WaveformAmplitudeUnit=="normalized_complex_baseband", ...
                'Actual internal columns must not acquire a missing RF reference, watts or a hardware claim.');
            proof=evidence.Isolation;
            receipt=jsondecode(demodToken); windows=double(receipt.FFTSupport.FFTIntervals);
            if isvector(windows)&&numel(windows)==2, windows=reshape(windows,1,2); end
            assert(isequal(proof.Request.FFTIntervals,windows+pre.StartSample));
            assert(isequal(before,rng)&&clock==owner.Events.NextSampleIndex && ...
                isequal(originalRX,rx.CSIRSChannelEstimate)&& ...
                originalPower==rx.CSIRSObservation.MeasurementPhysicalResourcesJSON && ...
                isequal(hashes,[pre.sampleHash() desired.sampleHash() actual.sampleHash()]));
            row=table(string(item.ID),token,digest,scope,'VariableNames', ...
                {'ObservationID','CSIRSReferenceIsolationEvidenceJSON','CSIRSReferenceIsolationEvidenceSHA256','Scope'});
            path=fullfile(folder,'original_isolation.csv');
            sixgr.util.csvWriteTable(path,row,'RoundTripNumericText',true);
            loaded=sixgr.util.csvReadTable(path,'TextType','string');
            assert(loaded.CSIRSReferenceIsolationEvidenceJSON==token && ...
                loaded.CSIRSReferenceIsolationEvidenceSHA256==digest);
            bad=rx; bad.PhysicalMeasurementDemodulationReceiptSHA256="changed";
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,bad,desired,source,replay,owner));
            changed=receipt; changed.InputSHA256=char(actual.sampleHash()+"wrong");
            bad=reseal(rx,changed);
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,bad,desired,source,replay,owner));
            changed=receipt; changed.FFTSupport.FFTIntervals(1)=changed.FFTSupport.FFTIntervals(1)+1;
            bad=reseal(rx,changed);
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,bad,desired,source,replay,owner));
            changed=receipt; changed.Frequency.PhaseOrigin='postRF_start'; bad=reseal(rx,changed);
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,bad,desired,source,replay,owner));
            badItem=item; badItem.Context.ComponentID="transplanted_component";
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(badItem,rx,desired,source,replay,owner));
            badItem=item; badItem.Context.Prepared.TransmitSamples(1)=badItem.Context.Prepared.TransmitSamples(1)+1;
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(badItem,rx,desired,source,replay,owner));
            badSource=source; badSource.LinkID="different_original_link";
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,rx,desired,badSource,replay,owner), ...
                'sixgr:truth:EmittedComponentIsolationEvidence');
            badReplay=replay;
            selected=find(string({badReplay.ReceiveStreamExecutionSegments{1}.Execution.RX.ID})==source.ReceiverID);
            badReplay.ReceiveStreamExecutionSegments{1}.Execution.RX(selected).Replay.ReceiveElementExecution=struct();
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,rx,desired,source,badReplay,owner), ...
                'RF:ReceiveElementObservation');
            badReplay=replay;
            badReplay.ReceiveStreamExecutionSegments{1}.Execution.RX(selected).Replay.RFInputWaveformSHA256="changed_original_input";
            reject(@()sixgr.truth.sharedCSIRSComponentIsolation(item,rx,desired,source,badReplay,owner), ...
                'RF:ReceiveElementObservation');
            % Unsupported declared metadata must not upgrade a composite to
            % port-3000 proof, even when all original capture hashes remain.
            changed=receipt; changed.Resources.NumPorts=4; bad=reseal(rx,changed);
            unavailable=sixgr.truth.sharedCSIRSComponentIsolation(item,bad,desired,source,replay,owner);
            assert(~unavailable.Available && unavailable.Status== ...
                "unavailable_multiport_component_not_independently_decomposed");
            count=count+1;
        end
    end
end

function rx=reseal(rx,r)
rx.PhysicalMeasurementDemodulationReceiptJSON=string(jsonencode(r));
rx.PhysicalMeasurementDemodulationReceiptSHA256=sixgr.util.sha256Hex(char(rx.PhysicalMeasurementDemodulationReceiptJSON));
end

function localGenericEquivalence()
% Actual compositor receipts, declared RF/channel dependency operands only.
% These are checker boundary tests, not a second physical execution.
for endOfPrior=[8 31 32]
    [trace,request]=fixture(endOfPrior);
    generic=sixgr.truth.proveEmittedComponentIsolation(trace,request);
    srs=sixgr.truth.proveSRSComponentIsolation(trace,request);
    expected=generic; expected.ContractVersion="sixgr.truth.SRSComponentIsolation/v1";
    expected.AllHistorySRSOnlyRequired=expected.AllHistoryComponentOnlyRequired;
    expected=rmfield(expected,'AllHistoryComponentOnlyRequired');
    assert(isequaln(srs,expected) && generic.Available==(endOfPrior<=31));
end
[trace,request]=fixture(8);
for mutation=1:5
    bad=trace; req=request;
    switch mutation
        case 1, req.ComponentSHA256="not_original";
        case 2, bad{3}.Execution.TX.Replay.TXSignalDependency.AdditiveTXOutput=true;
        case 3, bad{3}.Execution.ExecutedContributors.Receipt.CompleteContributorList=false;
        case 4, bad{3}.Execution.Links.Replay.ChannelSignalDependency.HistoryInitializationSource="elapsed_idle_only";
        case 5, bad(2)=[];
    end
    reject(@()sixgr.truth.proveEmittedComponentIsolation(bad,req),'sixgr:truth:EmittedComponentIsolationEvidence');
    reject(@()sixgr.truth.proveSRSComponentIsolation(bad,req),'sixgr:truth:SRSIsolationEvidence');
end
end

function [trace,request]=fixture(endOfPrior)
fs=1000; epoch=7;
composer=sixgr.phy.waveform.WaveformStreamComposer(fs,2,0);
composer.enqueue("earlier_data",sixgr.phy.waveform.WaveformChunk(complex(ones(endOfPrior,2)),0),fs);
component=sixgr.phy.waveform.WaveformChunk(complex(ones(16,2),ones(16,2)),32);
composer.enqueue("CSI_port3000",component,fs);
request=struct('TransmitterID',"gnb",'ReceiverID',"ue_rx",'LinkID',"serving", ...
    'ComponentID',"CSI_port3000",'ComponentSHA256',component.SHA256, ...
    'SampleRateHz',fs,'ConfigurationEpoch',epoch,'FFTIntervals',[40 48]);
trace=cell(4,1); first=0;
for k=1:4
    stop=k*16; [chunk,receipt]=composer.readThrough(stop);
    channel=struct('Available',true,'StartSample',first,'EndSampleExclusive',stop, ...
        'SampleRateHz',fs,'ConfigurationEpoch',epoch,'MemorySamples',3, ...
        'ContractVersion',"sixgr.channel.executed_signal_dependency/v1", ...
        'InputHistoryStartSample',0,'ZeroInputHistoryAtOrigin',true, ...
        'HistoryInitializationSource',"original_fresh_zero_warmup", ...
        'FilterSHA256',"declared-FIR-support",'NativeInitializationSHA256',"declared-checker-boundary");
    rf=channel; rf.ContractVersion="sixgr.rf.executed_tx_signal_dependency/v1";
    rf.MemorySamples=2; rf.DelaySamples=4; rf.HistoryOriginSample=0;
    rf.ZeroPreserving=true; rf.AdditiveTXOutput=false;
    rf.OriginalInputChunkSHA256=chunk.SHA256; rf.RFInputWaveformSHA256="declared-original-RF-hash";
    e=struct('Source',"composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf", ...
        'ApproximationMode',"none",'StartSample',first,'EndSampleExclusive',stop, ...
        'SampleRateHz',fs,'ConfigurationEpoch',epoch, ...
        'Links',struct('ID',"serving",'TX',"gnb",'RX',"ue_rx",'Replay',struct('ChannelSignalDependency',channel)), ...
        'TX',struct('ID',"gnb",'Replay',struct('TXSignalDependency',rf,'RFInputWaveformSHA256',rf.RFInputWaveformSHA256)), ...
        'ExecutedContributors',struct('TransmitterID',"gnb",'CommittedThroughSample',stop,'Receipt',receipt));
    trace{k}=struct('StartSample',first,'EndSampleExclusive',stop,'Execution',e); first=stop;
end
end

function reject(fn,id)
if nargin<2, id='sixgr:truth:CSIRSIsolationOwnerIdentity'; end
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Unexpected rejection: %s',cause.identifier); return;
end
error('test:MissingCSIIsolationRejection','Malformed original isolation evidence was accepted.');
end
