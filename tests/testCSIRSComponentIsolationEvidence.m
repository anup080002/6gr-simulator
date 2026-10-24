function ok=testCSIRSComponentIsolationEvidence(powerMode,completeReception,withInterferer)
% Actual shared one-resource/one-port CSI-only measurement component, then
% declared finite-dependency negatives. Optional completion installs an
% explicit singleton report/candidate before runtime construction. Neither
% mode qualifies one-port MIMO choice, received UCI, n40 multiport power,
% standardized RSRP accuracy or hardware conformance.
% Optional interference is a separate actual TX/link with declared IQ. It
% is not an inter-cell scheduling or statistically qualified SINR campaign.
if nargin<1, powerMode="normalized_complex_baseband"; end
if nargin<2, completeReception=false; end
if nargin<3, withInterferer=false; end
assert(isscalar(string(powerMode)) && any(string(powerMode)== ...
    ["normalized_complex_baseband","sqrt_mW"]) && ...
    islogical(completeReception)&&isscalar(completeReception) && ...
    islogical(withInterferer)&&isscalar(withInterferer));
powerMode=string(powerMode);
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; cleanup=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
localGenericEquivalence();
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
declared=scenario.toStruct();
if completeReception
    % Authored component report policy, BEFORE the builder installs feature
    % authority. No runtime flag is changed to bypass the YAML-use guard.
    declared.reference_signals.pmi_reporting_enabled=false;
    declared.csi_acquisition_and_reporting.pmi_policy="disabled";
    declared.canonical_control.reference_signals.pmi_reporting_enabled=false;
    % Legal cri-ri-cqi retains RI policy even though its one-port payload
    % represents rank one implicitly and serializes no spatial bits.
    declared.reference_signals.ri_reporting_enabled=true;
    declared.canonical_control.reference_signals.ri_reporting_enabled=true;
end
if powerMode=="sqrt_mW"
    % A separate declared physical-power component, not a calibrated-SNR
    % alias. Preserve original installed geometry and configured TX budget.
    for base=["integration","canonical_control.integration"]
        declared=sixgr.util.structSet(declared,base+".run_mode","GEOMETRY_NETWORK");
        declared=sixgr.util.structSet(declared,base+".subprofile","connected_network");
        declared=sixgr.util.structSet(declared,base+".configured_snr_is_link_authority",false);
        declared=sixgr.util.structSet(declared,base+".power_reference_mode","absolute_calibrated_sqrt_mw");
    end
    declared.simulation.noise_operating_mode="receiver_noise_figure_thermal_noise";
end
cfg=sixgr.lls6g.buildInternalConfig(declared,folder);
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
% The default remains measurement-only. The completion variant installs a
% real single-port report with CQI and no spatial choice, never an inherited
% four-port report or invented received UCI.
if completeReception
    request=cfg.phy.csi.reportConfiguration;
    request.Ports=1; request.Rank=1; request.MaxRank=1; request.AllowedRanks=1;
    request.N1=1; request.N2=1; request.NumCSIResources=1;
    request.ReportQuantity="cri-ri-cqi";
    cfg.phy.csi.reportConfiguration=request;
    cfg.phy.csi.maxRank=1; cfg.phy.csi.rankDomain=1;
    cfg.phy.mimo.N1=1; cfg.phy.mimo.N2=1;
    cfg.phy.csi.candidateMatricesByRank={1}; % No spatial choice for one port.
    typed=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
    reportFields=[typed.Part1Fields typed.Part2Fields];
    assert(~any(startsWith(reportFields,"PMI")|reportFields=="RI") && ...
        cfg.phy.csi.reportCSI && cfg.phy.csi.reportCQI && cfg.phy.csi.reportCRI && ...
        ~cfg.phy.csi.reportPMI && cfg.phy.csi.reportRI);
else
    cfg.phy.csi.reportConfiguration=[];
    for flag=["reportCSI","reportCQI","reportPMI","reportRI","reportCRI"]
        cfg.phy.csi.(flag)=false;
    end
end
if withInterferer
    % This fixture registers one external TX after the coupled coordinator
    % constructs its own radios. Defer ONLY ledger inventory installation;
    % enable it explicitly below with all real endpoints, still at sample0.
    % The ordinary no-interferer path retains its original configured policy.
    cfg.lls6g.energy_efficiency.enabled=false;
    assert(~cfg.rf.txSpatialPowerEnabled && ~cfg.rf.modeledRadiatedPower.Enabled && ...
        ~cfg.rf.txLinearReference.Enabled, ...
        'This declared source fixture must install the complete ledger inventory once.');
end
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),1);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,30,12);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[cfgUE,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
[state,queued,~,prepared]=sixgr.truth.queueSharedPeriodicCSIRS(state,cfgUE,1,1,1,1,1,30);
assert(queued && owner.hasPending('CSIRS',1));
interference=struct('Enabled',withInterferer,'Scope', ...
    "declared_separate_TX_link_actual_shared_composite_not_intercell_scheduling");
if withInterferer
    assert(owner.Events.NextSampleIndex==0 && isempty(owner.Physical.readRFExecutionLedger()), ...
        'Install the declared independent source before physical execution/inventory freeze.');
    input=prepared.TransmitSamples;
    % A finite deterministic source, not a new noise draw or an alteration
    % of the original desired CSI parent. Independent receiver noise remains
    % produced exactly once by the retained original UE RF/noise owner.
    input=.4*input.*exp(1i*2*pi*(0:size(input,1)-1)'/29);
    txID="declared_interferer"; linkID="declared_interfering_link";
    sourceCfg=prepared.ReceiverConfig;
    native=sixgr.channel.ChannelFactory.createRuntimeChannelState(sourceCfg,'DL', ...
        'LinkKey',linkID,'Seed',double(cfg.run.seed)+407,'AbsoluteSampleIndex',0);
    native=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(native,sourceCfg, ...
        complex(zeros(1,size(input,2))),prepared.TxInfo, ...
        'NumTxAnt',size(input,2),'NumRxAnt',2);
    owner.Physical.addTransmitter(txID,sourceCfg,'DL',size(input,2),false);
    owner.Physical.addLink(linkID,txID,"ue_1_rx",native,sourceCfg);
    owner.Events.addTransmitter(txID,size(input,2),'double');
    owner.Events.addReceiver(txID+":tx",size(input,2));
    chunk=sixgr.phy.waveform.WaveformChunk(input,0);
    interference.Enqueue=owner.Events.enqueue(txID,"declared_interfering_waveform",chunk);
    % Coupled commits only its own registered radios. This external source
    % explicitly commits silence after its finite input through the ORIGINAL
    % queued receive horizon and the current slot's ordinary advance. The
    % queue owns the receive extent; the caller's prepared copy predates it.
    queuedItem=owner.Pending([owner.Pending.UE]==1 & string({owner.Pending.Kind})=="CSIRS");
    assert(isscalar(queuedItem));
    receiveStop=queuedItem.Context.Prepared.ReceiveEndSampleExclusive;
    slotStop=sixgr.phy.frame.slotStartSample(prepared.Carrier,state.CurrentSlot,owner.SampleRateHz);
    committedStop=max(receiveStop,slotStop);
    assert(committedStop>=chunk.EndSample+1 && receiveStop>=prepared.NumSamples);
    owner.Events.commitTransmissionsThrough(txID,committedStop);
    interference.OriginalReceiveEndSampleExclusive=receiveStop;
    interference.KnownIdleCommittedThroughSample=committedStop;
    interference.TransmitterID=txID; interference.LinkID=linkID;
    interference.InputSHA256=chunk.SHA256;
    owner.Physical.enableRFExecutionLedger();
    ledger=owner.Physical.readRFExecutionLedger();
    assert(~isempty(ledger) && owner.Events.NextSampleIndex==0 && ...
        any(ledger.Inventory.EndpointID==txID & ledger.Inventory.Role=="TX"), ...
        'The actual interferer must belong to the installed original RF inventory before execution.');
end
count=0;
state=owner.advanceSlot(state,cfg,@receive);
assert(count==1 && isempty(owner.Pending),'Exactly one actual CSI capture must complete.');
if withInterferer
    ledger=owner.Physical.readRFExecutionLedger();
    assert(~isempty(ledger.Intervals) && any(ledger.Intervals.EndpointID==txID), ...
        'Keep the original interferer RF execution in the active ledger.');
end
if completeReception
    original=state.ControlTrials.CSIRS;
    assert(height(original)==1 && original.CSIRSEmittedPowerComparisonAvailable && ...
        original.CSIRSEmittedSINRComparisonAvailable);
    clock=owner.Events.NextSampleIndex; before=rng;
    [state,drained]=owner.drainDataReceiveTail(state,cfg,@receive);
    assert(isempty(drained)&&count==1&&clock==owner.Events.NextSampleIndex && ...
        isequal(before,rng)&&isequaln(original,state.ControlTrials.CSIRS));
    state=sixgr.truth.CoupledTruthRuntime.writeTables(state,folder);
    layout=sixgr.report.resultLayout(folder);
    fields=string(fieldnames(sixgr.truth.scoreSharedCSIRSPower())).';
    columnTypes=struct();
    for field=fields
        if isstring(original.(field)), columnTypes.(field)='string';
        else, columnTypes.(field)='double'; end
    end
    for path=[string(fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv')), ...
            string(fullfile(layout.ControlCSVDir,'csi_rs_trials.csv'))]
        published=sixgr.util.csvReadTable(path,'TextType','string','ColumnTypes',columnTypes);
        assert(height(published)==1&&all(ismember(fields,string(published.Properties.VariableNames))));
        for field=fields
            actualValue=published.(field); expected=original.(field);
            if islogical(expected), actualValue=logical(actualValue); end
            if isstring(expected)&&expected=="", actualValue=fillmissing(actualValue,'constant',""); end
            assert(isequaln(actualValue,expected),'test:CSIPowerPublication', ...
                'Original comparison field %s did not survive the actual CSV writer.',field);
        end
        assert(published.CSIRSEmittedPowerComparisonEvidenceSHA256== ...
            sixgr.util.sha256Hex(char(published.CSIRSEmittedPowerComparisonEvidenceJSON)));
        assert(published.CSIRSEmittedSINRComparisonEvidenceSHA256== ...
            sixgr.util.sha256Hex(char(published.CSIRSEmittedSINRComparisonEvidenceJSON)));
    end
end
fprintf('CSIRS_COMPONENT_ISOLATION_PASS actual_shared_measurements=1 port3000=1 completion=%d power_comparison=1 SINR_comparison=1 interferer=%d unit=%s standardized_accuracy=0 evidence=%s\n', ...
    completeReception,withInterferer,powerMode,folder);
ok=true;

    function next=receive(next,items)
        for item=reshape(items,1,[])
            assert(item.Kind=="CSIRS");
            p=item.Context.Prepared;
            if ~completeReception
            assert(isempty(p.ReceiverConfig.phy.csi.reportConfiguration) && ...
                ~p.ReceiverConfig.phy.csi.reportCSI && ~p.ReceiverConfig.phy.csi.reportCQI && ...
                ~p.ReceiverConfig.phy.csi.reportPMI && ~p.ReceiverConfig.phy.csi.reportRI && ...
                ~p.ReceiverConfig.phy.csi.reportCRI, ...
                'The original queued receiver must be measurement-only, not an invented one-port Type-I report.');
            end
            [~,pre,~,replay,actual]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
            [desired,source]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,item.Context.DesiredReferencePlane);
            if completeReception
                [next,completedRow,rx,csi]=sixgr.truth.completeSharedCSIRSReception(next,item);
                reportFields=[csi.CSIReportConfiguration.Part1Fields csi.CSIReportConfiguration.Part2Fields];
                assert(csi.CSIReportConfiguration.Ports==1 && ...
                    csi.CSIReportConfiguration.ReportQuantity=="cri-ri-cqi" && ...
                    csi.ReportRI && csi.RI==1 && ~csi.ReportPMI && ...
                    ~any(startsWith(reportFields,"PMI")|reportFields=="RI") && ...
                    numel(csi.CSIPart1Bits)==4 && isempty(csi.CSIPart2Bits) && ...
                    csi.PrecoderMatrixSHA256==sixgr.phy.mimo.MatrixContract.digest(1) && ...
                    csi.MeasurementID==rx.CSIMeasurementState.MeasurementID && ...
                    ~csi.ConfiguredOracleUsed && ~csi.ConfiguredSNRUsed, ...
                    'The actual singleton report must use only its received CSI state, with no spatial bits.');
                powerFields=string(fieldnames(sixgr.truth.scoreSharedCSIRSPower()));
                power=table2struct(completedRow(:,cellstr(powerFields)));
                evidence=jsondecode(completedRow.CSIRSReferenceIsolationEvidenceJSON);
            else
                rx=sixgr.phy.refsig.receiveCSIRSWaveform(p.Carrier,p.ReceiverConfig, ...
                    actual.readComplete(),pre.readComplete(),[0 0],replay);
                [power,evidence]=sixgr.truth.scoreSharedCSIRSPower(item,rx,desired,source,replay,owner);
            end
            assert(rx.CSIRSObservation.Observed && rx.CSIRSObservation.ChannelEstimateAvailable && ...
                rx.CSIRSInfo.NumCSIRSPorts==1 && rx.PhysicalMeasurementDemodulationReceiptAvailable);
            before=rng; clock=owner.Events.NextSampleIndex;
            originalRX=rx.CSIRSChannelEstimate; originalPower=rx.CSIRSObservation.MeasurementPhysicalResourcesJSON;
            hashes=[pre.sampleHash() desired.sampleHash() actual.sampleHash()];
            token=string(jsonencode(evidence)); digest=sixgr.util.sha256Hex(char(token));
            scope="actual_shared_single_port_CSI_emitted_power_model_no_standardized_accuracy";
            demodToken=rx.PhysicalMeasurementDemodulationReceiptJSON;
            save(fullfile(folder,'original_isolation.mat'),'evidence','demodToken','power','scope','interference');
            % Re-audit the SAME capture (one additional reference FFT, no
            % receiver call), to pin nonmutation independently of completion.
            replayed=sixgr.truth.scoreSharedCSIRSPower(item,rx,desired,source,replay,owner);
            assert(isequaln(replayed,power));
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
                string(evidence.Measurement.WaveformAmplitudeUnit)==powerMode, ...
                'Actual internal columns must not acquire a missing RF reference, watts or a hardware claim.');
            assert(power.CSIRSEmittedPowerComparisonAvailable && ...
                ~power.CSIRSEmittedPowerComparisonStandardizedAccuracyQualified, ...
                'test:CSIPowerUnavailable','Original power comparison unavailable: %s (%s).', ...
                power.CSIRSEmittedPowerComparisonStatus,power.CSIRSEmittedPowerComparisonErrorIdentifier);
            comparison=jsondecode(power.CSIRSEmittedPowerComparisonEvidenceJSON);
            assert(comparison.PowerComparisonPerformed && ~comparison.ReferenceUsedByReceiver && ...
                comparison.AdditionalOFDMDemodulations==1 && ...
                comparison.AdditionalRFExecutions==0 && comparison.AdditionalChannelExecutions==0 && ...
                comparison.AdditionalTimingAcquisitions==0 && comparison.AdditionalFrequencyEstimations==0 && ...
                comparison.AdditionalChannelEstimations==0 && ~comparison.MultiportAttributionQualified && ...
                ~comparison.StandardizedAccuracyQualified && ~comparison.StandardizedReferencePlaneQualified && ...
                comparison.DesiredOriginalInputSHA256==desired.sampleHash() && ...
                comparison.OriginalNoisyInputSHA256==pre.sampleHash() && ...
                comparison.PhysicalMeasurementDemodulationReceiptSHA256== ...
                    rx.PhysicalMeasurementDemodulationReceiptSHA256);
            assert(numel(comparison.Comparison.ReferencePerReceiveColumn)==pre.NumReceiveAntennas);
            assert(power.CSIRSEmittedSINRComparisonAvailable && ...
                ~power.CSIRSEmittedSINRComparisonStandardizedAccuracyQualified, ...
                'test:CSISINRUnavailable','Original SINR comparison unavailable: %s (%s).', ...
                power.CSIRSEmittedSINRComparisonStatus,power.CSIRSEmittedSINRComparisonErrorIdentifier);
            sinrProof=jsondecode(power.CSIRSEmittedSINRComparisonEvidenceJSON);
            measuredSINR=rx.CSIRSObservation.MeasurementPhysicalResources{1}.SINR;
            arithmetic=sinrProof.Comparison;
            assert(sinrProof.Available && ~sinrProof.ReferenceUsedByReceiver && ...
                sinrProof.AdditionalOFDMDemodulations==1 && ...
                sinrProof.SharedDesiredDemodulationCountedInPowerComparison && ...
                sinrProof.AdditionalRFExecutions==0 && sinrProof.AdditionalChannelExecutions==0 && ...
                sinrProof.AdditionalChannelEstimations==0 && ...
                sinrProof.AdditionalTimingAcquisitions==0 && ...
                ~sinrProof.StandardizedAccuracyQualified && ~sinrProof.HardwareQualified && ...
                ~sinrProof.StatisticallyQualified && ~sinrProof.IncludesReceiverRF && ...
                sinrProof.OriginalPowerProof.OriginalNoisyInputSHA256==pre.sampleHash() && ...
                sinrProof.OriginalPowerProof.DesiredOriginalInputSHA256==desired.sampleHash() && ...
                sinrProof.OriginalMeasuredSINRReceiveColumn1==measuredSINR.ReceiveBranch1Based);
            assert(all(arithmetic.ReferenceDisturbancePerReceiveColumn>0) && ...
                isequal(double(arithmetic.MeasuredSignedDesiredPerReceiveColumn(:)), ...
                    double(measuredSINR.DesiredPowerPerReceiveAntenna(:))) && ...
                isequal(double(arithmetic.MeasuredDisturbancePerReceiveColumn(:)), ...
                    double(measuredSINR.NoiseInterferencePowerPerReceiveAntenna(:))) && ...
                isequaln(double(arithmetic.MeasuredSelectedColumn1), ...
                    double(measuredSINR.ReceiveBranch1Based)) && ...
                norm(pre.readComplete()-desired.readComplete(),'fro')>0, ...
                'Use original nonzero disturbance, not configured SNR or a redrawn noise realization.');
            assert(power.CSIRSEmittedSINRComparisonEvidenceSHA256== ...
                sixgr.util.sha256Hex(char(power.CSIRSEmittedSINRComparisonEvidenceJSON)));
            if withInterferer
                used=false;
                for segment=reshape(replay.ReceiveStreamExecutionSegments,1,[])
                    executed=segment{1}.Execution;
                    k=find(string({executed.SignalContributions.LinkID})==interference.LinkID);
                    assert(isscalar(k) && executed.SignalContributions(k).TX==interference.TransmitterID);
                    used=used || executed.SignalContributions(k).NonzeroSampleCount>0;
                    contributors=executed.ExecutedContributors;
                    tx=find(string({contributors.TransmitterID})==interference.TransmitterID);
                    assert(isscalar(tx) && contributors(tx).Receipt.CompleteContributorList);
                end
                assert(used,'The optional interferer must have actually reached the original receiver sum.');
            end
            if powerMode=="sqrt_mW"
                assert(power.CSIRSEmittedPowerComparisonUnit=="W");
            else
                assert(power.CSIRSEmittedPowerComparisonUnit=="unit_RE" && ...
                    all(string(comparison.ComparisonLogTokens.ReferencePower_dBm)=="NaN"));
            end
            proof=evidence.Isolation;
            receipt=jsondecode(demodToken); windows=double(receipt.FFTSupport.FFTIntervals);
            if isvector(windows)&&numel(windows)==2, windows=reshape(windows,1,2); end
            proofWindows=double(proof.Request.FFTIntervals);
            if isvector(proofWindows)&&numel(proofWindows)==2, proofWindows=reshape(proofWindows,1,2); end
            assert(isequal(proofWindows,windows+pre.StartSample));
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
            excluded=sixgr.truth.scoreSharedCSIRSPower(item,bad,desired,source,replay,owner);
            assert(~excluded.CSIRSEmittedPowerComparisonAvailable && ...
                excluded.CSIRSEmittedPowerComparisonStatus==unavailable.Status && ...
                isnan(excluded.CSIRSEmittedPowerComparisonReportedError_dB));
            for mutation=1:5
                bad=rx; badDesired=desired; badSource=source;
                switch mutation
                    case 1
                        bad.PhysicalMeasurementDemodulationReceiptSHA256="changed";
                    case 2
                        changed=receipt; changed.FFTSupport.Nfft=changed.FFTSupport.Nfft*2;
                        bad=reseal(rx,changed);
                    case 3
                        bad.CSIRSObservation.MeasurementPhysicalResourcesJSON="changed_measurement";
                    case 4
                        badDesired=pre; % Same shape/clock is not original desired ownership.
                    case 5
                        badSource.TransmitterID="different_original_transmitter";
                end
                excluded=sixgr.truth.scoreSharedCSIRSPower(item,bad,badDesired,badSource,replay,owner);
                assert(~excluded.CSIRSEmittedPowerComparisonAvailable && ...
                    ~excluded.CSIRSEmittedSINRComparisonAvailable && ...
                    strlength(excluded.CSIRSEmittedPowerComparisonErrorIdentifier)>0 && ...
                    isnan(excluded.CSIRSEmittedPowerComparisonReportedError_dB) && ...
                    ~excluded.CSIRSEmittedPowerComparisonStandardizedAccuracyQualified && ...
                    excluded.CSIRSEmittedPowerComparisonEvidenceSHA256== ...
                    sixgr.util.sha256Hex(char(excluded.CSIRSEmittedPowerComparisonEvidenceJSON)));
            end
            % Preserve power independently: a coherent original-measurement
            % token with corrupted SINR-only arithmetic cannot pass the SINR
            % boundary merely because the RSRP comparison remains available.
            for mutation=1:2
                bad=rx;
                if mutation==1
                    bad.CSIRSObservation.MeasurementPhysicalResources{1}.SINR.CSI_SINR_dB= ...
                        measuredSINR.CSI_SINR_dB+1;
                else
                    bad.CSIRSObservation.MeasurementPhysicalResources{1}.SINR.ReceiveBranch1Based= ...
                        pre.NumReceiveAntennas+1;
                end
                bad.CSIRSObservation.MeasurementPhysicalResourcesJSON=string(jsonencode( ...
                    sixgr.util.jsonSafeValue(bad.CSIRSObservation.MeasurementPhysicalResources)));
                excluded=sixgr.truth.scoreSharedCSIRSPower(item,bad,desired,source,replay,owner);
                assert(excluded.CSIRSEmittedPowerComparisonAvailable && ...
                    ~excluded.CSIRSEmittedSINRComparisonAvailable && ...
                    excluded.CSIRSEmittedSINRComparisonErrorIdentifier== ...
                        "sixgr:refsig:CSIRSSINRReferenceOperands" && ...
                    isnan(excluded.CSIRSEmittedSINRComparisonReportedError_dB));
            end
            assert(isequal(before,rng)&&clock==owner.Events.NextSampleIndex && ...
                isequal(originalRX,rx.CSIRSChannelEstimate)&& ...
                originalPower==rx.CSIRSObservation.MeasurementPhysicalResourcesJSON && ...
                isequal(hashes,[pre.sampleHash() desired.sampleHash() actual.sampleHash()]));
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
