function [ok,evidence]=testSharedCSIRSMultiportCSIIMReference()
% Actual native-CDL/RF, multiport CSI and dedicated muted-RE measurement.
% Canonical completion produces an original UE report, NOT received UCI.
% Fixed-linear component attribution remains a declared diagnostic model.
setup6GRSimToolkit('Verbose',false);
initialRNG=rng; cleanup=onCleanup(@()rng(initialRNG)); %#ok<NASGU>
parent=fullfile(pwd,'logs','shared_csirs_multiport_csiim');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('SHARED_CSIRS_MULTIPORT_CSIIM_AUDIT %s\n',folder);
cfg=configuration(folder); carrier=sixgr.phy.grid.makeCarrier(cfg);
info=nrOFDMInfo(carrier); fs=double(info.SampleRate);
slotSamples=sixgr.phy.frame.slotStartSample(carrier,1,fs);
arms=cell(2,1); completedRows=cell(2,1);
for arm=1:2
    enabled=arm==2; current=cfg; current.rf.txLinearReference.Enabled=enabled;
    current.run.rootRunFolder=fullfile(folder,char("model_"+string(enabled)));
    mkdir(current.run.rootRunFolder);
    rng(initialRNG);
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(current,current.run.rootRunFolder,multi,struct(),1);
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,current,'DL',1,1,1,3,30);
    state.CurrentServingIdx(:)=1;
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,current,{current});
    initializedRNG=rng;
    initialization=struct('RNG',initializedRNG,'Layout',state.Layout,'UE',state.UE);
    if arm==2, assert(isequaln(initialization,arms{1}.Initialization)); end
    channels=owner.Physical.channelStates(); assert(numel(channels)==1);
    s=channels{1};
    assert(isa(s.Obj,'nrCDLChannel')&&s.Obj.SampleDensity==Inf&&s.Obj.MaximumDopplerShift==50&& ...
        s.NumTxAnt==4&&s.NumRxAnt==2&&s.CurrentSampleIndex==0&& ...
        s.Meta.NativeReciprocalFilterInitialization.Applied);
    % Exercise a genuine late registration after an executed, nonzero
    % aggregate history. No model history is copied from this RF/channel.
    prior=.02*exp(1i*reshape(1:37*4,37,4)/19);
    owner.Events.enqueue("gnb_1","declared_original_prefix", ...
        sixgr.phy.waveform.WaveformChunk(prior,0));
    state=owner.advanceSlot(state,current,[]);
    assert(owner.Events.NextSampleIndex==slotSamples&&isequal(initializedRNG,rng));
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,current,'DL',1,1,2,3,30);
    state.CurrentServingIdx(:)=1;
    [user,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(current,state,1,'DL');
    [state,queued,reason,prepared]=sixgr.truth.queueSharedPeriodicCSIRS(state,user,1,2,1,1,1,30);
    assert(queued&&reason=="configured_periodic_csirs_queued_on_shared_physical_stream");
    plan=prepared.Tx.CSIIMResource; c=prepared.Carrier;
    assert(c.NStartGrid==0&&c.NFrame==0&&c.NSlot==1&&c.NSizeGrid>=24&& ...
        plan.Enabled&&plan.Scheduled&&plan.AbsoluteSlot0==1&&plan.Pattern==1&& ...
        plan.ResourceID==3&&plan.NumRE==96&&isequal(plan.PRBs0Based,(0:23).'));
    K=12*double(c.NSizeGrid);
    [sub,sy]=ind2sub([K double(c.SymbolsPerSlot)],plan.PhysicalIndices1Based);
    assert(all(sy==9)&&isequal(sort(sub-1),sort(reshape(12*(0:23)+(4:7).',[],1))), ...
        'test:CSIIMOriginalCoordinates','CSI-IM must use original carrier-relative REs for the declared CRBs.');
    grid=reshape(prepared.Tx.Grid,[],4);
    assert(all(grid(plan.PhysicalIndices1Based,:)==0,'all'));
    resources=prepared.Tx.CSIRSInfo.Resources;
    assert(isequal([resources.ResourceID],[17 29])&&all([resources.NumPorts]==4));
    for resource=reshape(resources,1,[])
        support=unique(mod(double(resource.Indices(:))-1,K*c.SymbolsPerSlot)+1);
        assert(isempty(intersect(support,plan.PhysicalIndices1Based)));
    end
    assert(prepared.ReceiverConfig.phy.csi.reportConfiguration.NumCSIResources==2&& ...
        prepared.ReceiverConfig.phy.csi.reportConfiguration.Ports==4);
    enqueue=owner.Events.originalEnqueueReceipt("gnb_1",owner.Pending(1).Context.ComponentID);
    assert(~enqueue.PhysicalExecutionPerformed&&enqueue.EnqueuedAtSample==slotSamples&& ...
        enqueue.StartSample==slotSamples);
    capture=struct(); callbackCount=0;
    state=owner.advanceSlot(state,current,@receive);
    assert(callbackCount==0&&numel(owner.Pending)==1&&numel(owner.CSIRSTransmissions)==1&& ...
        owner.Events.NextSampleIndex==2*slotSamples);
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,current,'DL',1,1,3,3,30);
    state.CurrentServingIdx(:)=1;
    state=owner.advanceSlot(state,current,@receive);
    assert(callbackCount==1&&isempty(owner.Pending)&&height(state.ControlTrials.CSIRS)==1&& ...
        owner.Events.NextSampleIndex==3*slotSamples&&isequal(initializedRNG,rng));
    completedRows{arm}=state.ControlTrials.CSIRS;
    arms{arm}=struct('Initialization',initialization,'Capture',capture, ...
        'Trace',{owner.Events.ExecutionTrace},'Clock',channelClock(owner), ...
        'Enqueue',enqueue,'RNG',rng,'Row',state.ControlTrials.CSIRS);
    original=arms{arm}; %#ok<NASGU>
    save(fullfile(current.run.rootRunFolder,'original_complete_execution.mat'),'original','current','-v7.3');
    fprintf('SHARED_CSIRS_MULTIPORT_CSIIM_ARM_PASS enabled=%d callback=%d\n',enabled,callbackCount);
end
assertOriginalEquality(arms{1},arms{2});
rows=[completedRows{1};completedRows{2}];
fields=string(rows.Properties.VariableNames);
fields=fields(startsWith(fields,"CSIRSLinearPortModelComparison"));
assert(~isempty(fields)); types=struct();
for name=fields, types.(name)=class(rows.(name)); end
canonicalPath=fullfile(folder,'csirs_trials.csv');
sixgr.util.csvWriteTable(canonicalPath,rows,'PreserveSchema',true,'RoundTripNumericText',true);
canonicalSHA=string(sixgr.util.sha256File(canonicalPath));
readback=sixgr.util.csvReadTable(canonicalPath,'TextType','string','ColumnTypes',types);
tables=sixgr.truth.buildLLSPublicOutputTables(struct('csi_rs_table',readback), ...
    sixgr.truth.llsOutputContract(),struct('logical_run_id',"actual_multiport_CSIIM_component",'run_id',1));
published=tables.csi_rs_runtime_event_table;
publicPath=fullfile(folder,'csi_rs_runtime_event_table.csv');
sixgr.util.csvWriteTable(publicPath,published,'PreserveSchema',true,'RoundTripNumericText',true);
publicRead=sixgr.util.csvReadTable(publicPath,'TextType','string','ColumnTypes',types);
assert(height(published)==2);
for name=fields
    actual=readback.(name); output=publicRead.(name);
    if isstring(rows.(name))
        actual=fillmissing(actual,'constant',""); output=fillmissing(output,'constant',"");
    end
    assert(isequaln(actual,rows.(name))&&isequaln(output,rows.(name)), ...
        'test:CSIIMModelCSV','Original canonical/public comparison changed: %s.',name);
end
assert(canonicalSHA==string(sixgr.util.sha256File(canonicalPath)));
evidence=struct('SourceFolder',string(folder),'OriginalOwnerArms',2,'CanonicalCompletionsPerArm',1, ...
    'OriginalPracticalReceiverCallsPerArm',1,'CanonicalModelScorerCallsPerArm',1, ...
    'EnabledCanonicalModelOFDMDemodulations',6, ...
    'CopiedEvidenceCorruptionAudit',arms{2}.Capture.CorruptionAudit, ...
    'ResourceCount',2,'PortsPerResource',4,'CSIIMRECount',96,'RuntimeSlotsPerArm',3, ...
    'OriginalPhysicalAndReceiverEquality',true,'OriginalUEReportComputed',true, ...
    'ReceivedUCIExecuted',false,'ConfiguredTRSAndTCIRetained',true, ...
    'TRSExecuted',false,'ConnectedDataExecuted',false, ...
    'UniqueNonlinearPortAttributionQualified',false, ...
    'StandardizedAccuracyQualified',false,'StatisticallyQualified',false,'HardwareQualified',false, ...
    'CanonicalCSV',string(canonicalPath),'CanonicalCSVSHA256',canonicalSHA, ...
    'PublicCSV',string(publicPath),'PublicCSVSHA256',string(sixgr.util.sha256File(publicPath)));
save(fullfile(folder,'summary.mat'),'evidence','rows');
clear cleanup
assert(isequal(initialRNG,rng));
ok=true;
fprintf('SHARED_CSIRS_MULTIPORT_CSIIM_PASS resources=2 ports=4 canonical_completions=2 received_UCI=0\n');

    function next=receive(next,items)
        assert(isscalar(items)&&items.Kind=="CSIRS"); item=items;
        p=item.Context.Prepared;
        [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        [desired,source]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,item.Context.DesiredReferencePlane);
        beforeRX=rng; clocks=channelClock(owner);
        [next,row,reception,csi]=sixgr.truth.completeSharedCSIRSReception(next,item);
        callbackCount=callbackCount+1;
        assert(isequal(beforeRX,rng)&&isequaln(clocks,channelClock(owner)));
        capture=struct('TX',tx.readComplete(),'PreRF',pre.readComplete(), ...
            'PostRF',post.readComplete(),'Desired',desired.readComplete(), ...
            'PreRFSHA256',pre.sampleHash(),'ObservationID',string(item.ID), ...
            'H',reception.CSIRSChannelEstimate, ...
            'MeasuredResources',{reception.CSIRSObservation.MeasurementPhysicalResources}, ...
            'DemodulationJSON',reception.PhysicalMeasurementDemodulationReceiptJSON, ...
            'Reception',reception,'CSI',csi,'Row',row,'ModelPlanes',struct());
        if enabled
            for ref=reshape(item.Context.CSIRSPortReferencePlanes,1,[])
                hit=find(string({item.Planes.ReceiverID})==string(ref.PlaneID)); assert(isscalar(hit));
                capture.ModelPlanes.("Resource"+ref.ResourceID)=item.Planes(hit).Observation.readComplete();
            end
        end
        save(fullfile(current.run.rootRunFolder,'original_received_before_audit.mat'),'capture','p','-v7.3');
        assert(row.Observed&&row.Consumed&&row.CSIMeasurementAvailable&& ...
            row.ReceiverWindowID==string(item.ID)&&row.ResourceSetID==9&& ...
            row.CSIReportConfigID==string(p.ReceiverConfig.phy.csi.reportConfiguration.ReportConfigID));
        assertComparison(row,reception,item,enabled);
        if enabled, capture.CorruptionAudit=assertCorruptions(item,reception,desired,source,replay,owner); end
    end
end

function cfg=configuration(folder)
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
d=s.toStruct();
d.channels.model_type="CDL"; d.channels.profile="CDL-C";
d.channels.delay_spread_ns=100; d.channels.per_sample_fading_enabled=true;
d.channels.doppler_source_mode="configured"; d.channels.doppler_hz=50;
d.channels.normalize_channel_outputs=false; d.channels.normalize_path_gains=true;
d.channels.awgn_beam_failure_recovery_enabled=false;
d.channels.awgn_spatial_matrix_dl_real=[]; d.channels.awgn_spatial_matrix_dl_imag=[];
d.channels.shared_identity_awgn_enabled=false;
d.power_and_rf_frontend.modeled_radiated_power.enabled=false;
d.power_and_rf_frontend.tx_spatial_power_enabled=false;
d.power_and_rf_frontend.tx_linear_reference=struct('enabled',true, ...
    'model',"fixed_first_order_pa_identity_dac",'classification',"optional_research_experiment");
% Install the resource/report domain before immutable runtime features are
% constructed. Keep the existing native four-port Type-I rank policy.
% Only CSI is queued by this test. Disable conflicting access transmissions
% before build, but retain the parent's valid configured TRS/TCI context:
% inherited data capability still requires valid connected control policy.
d=declareCSIOnlyScope(d);
d.reference_signals.csi_rs_num_resources=2;
d.mimo.phase07_strict.csi_report.num_csi_resources=2;
d.mimo.phase07_strict.csi_report.number_of_beams=2;
d.reference_signals.csi_rs_resource_set_id=9;
d.reference_signals.csi_rs_resource_ids=[17 29];
d.reference_signals.csi_rs_resource_row_numbers=[4 4];
d.reference_signals.csi_rs_resource_symbol_locations=[3 13];
d.reference_signals.csi_rs_resource_subcarrier_locations=[0 0];
d.reference_signals.csi_rs_resource_rb_offsets=[0 0];
d.reference_signals.csi_rs_resource_num_rbs=[24 24];
% This fixture explicitly authors a four-carrier-slot period over the loaded
% scenario. Synchronize its inherited unit aliases through the production
% layer-authority API; contradictory declarations in one layer still fail.
periodLayer=struct('reference_signals',struct('csi_rs_periodicity_slots',4));
periodAuthority=sixgr.lls6g.config.RSPeriodAuthority.merge(struct(),periodLayer);
d=sixgr.lls6g.config.RSPeriodAuthority.apply(d,periodAuthority);
d.reference_signals.csi_rs_offset_slots=1;
spec=d.reference_signals.csi_rs_precoder_codebook;
for name=string(fieldnames(spec)).'
    if startsWith(name,["beam_indices_port_","polarization_indices_port_","panel_indices_port_"])
        value=spec.(name); assert(isnumeric(value)&&isscalar(value));
        spec.(name)=repmat(value,1,2);
    end
end
d.reference_signals.csi_rs_precoder_codebook=spec;
d.reference_signals.csi_im=struct('enabled',true,'resource_id',3,'pattern',1, ...
    'subcarrier',4,'symbol',8,'starting_rb',0,'num_rbs',24,'period_slots',4,'offset_slots',1);
fprintf('CSIIM_FIXTURE_PREBUILD ssb=%d pbch=%d sib1=%d trs=%d tracking=%d beam_sweep=%d qcl=%d csi=%d resources=%d\n', ...
    d.reference_signals.ssb_enabled,d.reference_signals.pbch_enabled,d.initial_access.sib1.enabled, ...
    d.reference_signals.trs_enabled,d.reference_signals.tracking_rs_enabled,d.mimo.beam_sweep_enabled, ...
    d.mimo.qcl_tci.enabled,d.reference_signals.csi_rs_enabled,d.reference_signals.csi_rs_num_resources);
cfg=sixgr.lls6g.buildInternalConfig(d,folder);
assert(cfg.phy.csirs.period_slots==4&&cfg.phy.csirs.offset_slots==1, ...
    'The explicit CSI fixture calendar must remain four carrier slots, offset one.');
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,30); cfg.run.rootRunFolder=folder;
assert(cfg.phy.csi.reportConfiguration.Ports==4&&cfg.phy.csi.reportConfiguration.NumCSIResources==2);
typed=sixgr.phy.mimo.CSIReportConfiguration(cfg.phy.csi.reportConfiguration, ...
    cfg.phy.csi.reportConfiguration.Epoch);
typed.assertQualifiedWireLayout();
assert(~cfg.phy.ssb.enable&&~cfg.phy.pbch.enable&&~cfg.phy.mib.enable&&~cfg.phy.sib1.enable&& ...
    ~cfg.phy.beamManagement.enabled&&~cfg.run.controlGating.pbchRequired);
assert(cfg.phy.trs.enable&&cfg.phy.pdsch.qclTCI.enabled&& ...
    cfg.phy.pdcch.operatorControl.connected_dci.tci_present&&cfg.runtime.features.trs.Enabled);
for name=["ssb","pbch","sib1","beam_sweep"]
    assert(~cfg.runtime.features.(name).Enabled);
end
for name=["csi_rs","csi_reporting","cqi_reporting","pmi_reporting","ri_reporting","cri_reporting"]
    assert(cfg.runtime.features.(name).Enabled);
end
cfg.phy.csirs.runtimeChannelEstimator='nr_channel_estimate';
cfg.phy.synchronization=struct('maxTimingUncertaintySamples',64);
cfg.phy.rx.cfoCorrectionEnabled=false;
cfg.rf.specification.profile_id='rf_impaired_research'; cfg.rf.pa.enable=true;
cfg.rf.frontend.pa=struct('profile_id','declared_multiport_reference_PA','version','1', ...
    'input_backoff_db',2,'model','memory_polynomial', ...
    'reference_domain','normalized_complex_baseband_full_scale', ...
    'coefficients',[1+.2i .1-.03i;-.08+.015i .02+.006i],'orders',[1 3],'memory_depth',2);
cfg.rf.tx.timingOffsetSamples=3;
cfg.measurements.csiSelectionQuality.Enabled=false; cfg.lls6g.energy_efficiency.enabled=false;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.outputs.rawIQCaptureEnabled=false; cfg.outputs.saveRawWaveforms=false;
cfg.outputs.continuousRawIQCaptureEnabled=false;
end

function d=declareCSIOnlyScope(d)
% The source aliases consumed by buildInternalConfig and its immutable
% operating-authority installer must agree. This does NOT disable CSI beam
% weights/reporting, inject access state, or qualify a connected procedure.
% Configured TRS/TCI remains inherited and valid; neither TRS nor DCI/data
% is transmitted by this explicit three-slot measurement test.
paths=["reference_signals.ssb_enabled","initial_access.ssb.enabled", ...
    "reference_signals.pbch_enabled","initial_access.mib.enabled", ...
    "initial_access.sib1.enabled","phy.sib1.enable", ...
    "mimo.beam_sweep_enabled","control_gating.pbch_required"];
for name=["ssb_required","ssb_burst_required","mib_required","sib1_required", ...
        "cell_search_required","sib1_asn1_required","type0_pdcch_css_required", ...
        "coreset0_from_mib_required","searchspace0_from_mib_required", ...
        "sib1_pdsch_required","sib1_decode_from_waveform_required"]
    paths(end+1)="sib1_and_initial_access."+name; %#ok<AGROW>
end
% Keep inherited compatibility mirrors coherent without creating unrelated
% configuration objects. The builder reads these only as named fallbacks;
% normalization is not rerun and cannot silently restore an inherited flag.
mirrors=["signals_and_channels_common.ssb.enable_flag", ...
    "signals_and_channels_common.pbch.enable_flag", ...
    "signals_and_channels_common.sib1_related_pdcch.enable_flag", ...
    "signals_and_channels_common.sib1_related_pdsch.enable_flag", ...
    "mimo.beam_management_enable","mimo_and_beam_management.beam_sweeping", ...
    "mimo_and_beam_management.runtime_state_machine_enabled", ...
    "mimo_and_beam_management.require_received_tci_for_data", ...
    "initial_access.sib1.coreset0_from_mib_required", ...
    "initial_access.sib1.searchspace0_from_mib_required", ...
    "initial_access.sib1.decode_from_waveform_required"];
for path=mirrors
    if ~isempty(sixgr.util.structGet(d,path,[])), paths(end+1)=path; end %#ok<AGROW>
end
for path=paths
    d=sixgr.util.structSet(d,path,false);
    canonical="canonical_control."+path;
    if ~isempty(sixgr.util.structGet(d,canonical,[]))
        d=sixgr.util.structSet(d,canonical,false);
    end
end
end

function c=channelClock(owner)
states=owner.Physical.channelStates(); assert(numel(states)==1); s=states{1};
c=struct('Event',owner.Events.NextSampleIndex,'Physical',owner.Physical.NextSampleIndex, ...
    'CurrentSampleIndex',s.CurrentSampleIndex,'TotalAppliedSamples',s.TotalAppliedSamples, ...
    'TotalObjectInputSamples',s.TotalObjectInputSamples,'NativeInitialTime',s.Obj.InitialTime, ...
    'NativeSwapped',s.Obj.TransmitAndReceiveSwapped,'Direction',s.Direction);
end

function assertOriginalEquality(a,b)
assert(isequaln(a.Initialization,b.Initialization)&&isequaln(a.Clock,b.Clock)&&isequal(a.RNG,b.RNG));
for name=["TX","PreRF","PostRF","Desired","PreRFSHA256","ObservationID", ...
        "H","MeasuredResources","DemodulationJSON"]
    assert(isequaln(a.Capture.(name),b.Capture.(name)), ...
        'test:CSIIMOriginalPhysicalChanged','Optional recording changed original %s.',name);
end
assert(numel(a.Trace)==numel(b.Trace));
for k=1:numel(a.Trace)
    x=a.Trace{k}.Execution; y=b.Trace{k}.Execution;
    for name=["StartSample","EndSampleExclusive","TX","RX","ExecutedContributors"]
        assert(isequaln(x.(name),y.(name)));
    end
end
for name=["CQI","RI","PMI","CRI","CSIPart1BitsToken","CSIPart2BitsToken", ...
        "CSIPayloadBitLength","CSIPayloadHex","ReferenceMeasuredSINR_dB"]
    assert(isequaln(a.Row.(name),b.Row.(name)), ...
        'test:CSIIMOriginalReportChanged','Optional recording changed actual measured/report field %s.',name);
end
end

function assertComparison(row,reception,item,enabled)
prefix="CSIRSLinearPortModelComparison";
schema=sixgr.truth.emptyCSIRSTrialTable();
names=string(schema.Properties.VariableNames);
for name=names(startsWith(names,prefix))
    assert(ismember(name,string(row.Properties.VariableNames))&& ...
        strcmp(class(row.(name)),class(schema.(name))));
end
assert(row.(prefix+"Available")==enabled,'test:CSIIMModelUnavailable', ...
    'Original model comparison unavailable: %s. Original RX was archived first.',row.(prefix+"ErrorIdentifier"));
assert(~row.(prefix+"UniqueNonlinearPortAttributionQualified")&& ...
    ~row.(prefix+"StandardizedAccuracyQualified")&&~row.(prefix+"HardwareQualified")&& ...
    ~row.(prefix+"CDMDenominatorIndependentlyReferenced")&& ...
    ~row.(prefix+"SINREstimandCompatible")&& ...
    isnan(row.(prefix+"ReportedSINRError_dB"))&&isnan(row.(prefix+"SelectedColumnSINRError_dB")));
measured=reception.CSIRSObservation.MeasurementPhysicalResources;
p=item.Context.Prepared; resources=p.Tx.CSIRSInfo.Resources;
assert(numel(measured)==2&&numel(resources)==2);
if enabled
    token=row.(prefix+"EvidenceJSON"); e=jsondecode(token);
    assert(row.(prefix+"EvidenceSHA256")==string(sixgr.util.sha256Hex(char(token)))&& ...
        row.(prefix+"CDMOperatorMatchedModelAvailable")&&row.(prefix+"ResourceCount")==2&& ...
        string(e.ObservationID)==string(item.ID)&& ...
        string(e.ParentComponentID)==string(item.Context.ComponentID)&& ...
        string(e.OriginalDemodulationReceiptSHA256)== ...
            string(reception.PhysicalMeasurementDemodulationReceiptSHA256)&& ...
        ~e.ReferenceUsedByReceiver&&~e.StandardizedAccuracyQualified&& ...
        ~e.UniqueNonlinearPortAttributionQualified&&~e.HardwareQualified&& ...
        e.AdditionalTimingAcquisitions==0&&e.AdditionalRFExecutions==0&&e.AdditionalChannelExecutions==0&& ...
        e.AdditionalOFDMDemodulationAttempts==6&&e.AdditionalOFDMDemodulations==6);
    comparisons=e.ResourceComparisons;
    if iscell(comparisons), comparisons=vertcat(comparisons{:}); end
    assert(isequal([comparisons.ResourceID],[resources.ResourceID]));
else
    assert(~row.(prefix+"CDMOperatorMatchedModelAvailable")&&row.(prefix+"ResourceCount")==0&& ...
        row.(prefix+"EvidenceJSON")==""&&row.(prefix+"EvidenceSHA256")=="");
end
for k=1:2
    m=measured{k}; im=m.SINR.InterferenceMeasurement;
    original=m.SINR.SignalPowerEstimation; c=original.CDMProjectionReceipt;
    assert(string(m.SINR.Source)=="received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"&& ...
        im.Available&&im.SampleCount==96&& ...
        isequal(im.Plan.PhysicalIndices1Based,p.Tx.CSIIMResource.PhysicalIndices1Based)&& ...
        string(original.CDMProjectionReceiptSHA256)==string(sixgr.util.sha256Hex(char(jsonencode(c))))&& ...
        string(c.ContractVersion)=="sixgr.csirs.original_cdm_projection/v1"&& ...
        c.ReferencePortNumber==3000&&c.ReferencePortCount==4&&c.ReceiveColumnCount==2&& ...
        ~c.OriginalSharedOwnerBound&&~c.ResourceIdentityBound&&~c.WaveformAmplitudeUnitBound&& ...
        ~c.IndependentReferenceAvailable&&~c.StandardizedAccuracyQualified&&~c.ReferenceUsedByReceiver);
    for name=["NSizeGrid","NStartGrid","SubcarrierSpacing","NFrame","NSlot","SymbolsPerSlot"]
        assert(isequal(c.CarrierIdentity.(name),double(p.Carrier.(name))));
    end
    K=12*double(p.Carrier.NSizeGrid); L=double(p.Carrier.SymbolsPerSlot);
    port0=double(resources(k).Indices(:)); port0=port0(port0<=K*L);
    assert(isequal(sort(double(c.TileIndices1Based(:))),sort(port0))&& ...
        c.NormalizationPilotCount==numel(port0)&&c.TileCount*c.TileSize==numel(port0));
    % Recompute only the arithmetic of the ORIGINAL recorded coefficients.
    % No clean-grid channel estimator or new measurement is used here.
    coefficients=complex(c.ProjectedCoefficientsReal,c.ProjectedCoefficientsImag);
    qY=sum(c.ReferenceEnergyPerTile(:).*abs(coefficients).^2,1)/c.NormalizationPilotCount;
    D=double(im.PowerPerReceiveAntenna(:).');
    bias=c.UnitDisturbancePowerBias*D;
    assertMoment(qY,double(original.RawPort3000PowerPerBranch(:).'),numel(port0));
    assertMoment(qY-bias,double(m.SINR.DesiredPowerPerReceiveAntenna(:).'),numel(port0));
    if ~enabled, continue; end
    q=comparisons(k); matched=q.MatchedCDMModelComparison;
    hit=find(string({item.Planes.ReceiverID})==string(q.TargetPlaneID)); assert(isscalar(hit));
    assert(string(q.OriginalTargetInputSHA256)==item.Planes(hit).Observation.sampleHash()&& ...
        ~isempty(q.OriginalCommittedIntervals)&& ...
        matched.Available&&matched.OperatorMatchedModelComparisonAvailable&&matched.ModelOnly&& ...
        matched.OriginalCSIIMSecondMomentReproduced&&~matched.DenominatorIndependentlyReferenced&& ...
        ~matched.IndependentAccuracyQualified&&~matched.UniqueNonlinearPortAttributionQualified&& ...
        ~matched.StandardizedAccuracyQualified&&~matched.StatisticallyQualified&&~matched.HardwareQualified&& ...
        ~matched.ReferenceUsedByReceiver&&~matched.TargetProjectionIsPhysicalREPower&& ...
        matched.AdditionalRFExecutions==0&&matched.AdditionalChannelExecutions==0&& ...
        matched.AdditionalTimingAcquisitions==0&&matched.AdditionalChannelEstimates==0&& ...
        string(matched.OriginalCDMProjectionReceiptSHA256)==string(original.CDMProjectionReceiptSHA256)&& ...
        string(matched.OriginalMeasurementUsedSupportSHA256)==string(c.InputUsedSupportSHA256)&& ...
        string(matched.OriginalReferenceUsedSupportSHA256)==string(c.ReferenceUsedSupportSHA256));
    assertMoment(double(matched.OriginalObservedCSIIMTotalPowerPerReceiveColumn(:).'),D,numel(port0));
    assertMoment(double(matched.OriginalProjectedNoisyPowerPerReceiveColumn(:).'),qY,numel(port0));
    assertMoment(double(matched.OriginalMeasuredSignedPowerPerReceiveColumn(:).'),qY-bias,numel(port0));
    powers=matched.ProjectedPowerPerTermPerReceiveColumn;
    cross=matched.ProjectedSignedCrossPowerPerReceiveColumn;
    assert(isequal(size(powers),[4 2])&&isequal(size(cross),[6 2])&& ...
        isequal(matched.CrossPairIndices1,nchoosek(1:4,2)));
    assertMoment(sum(powers,1)+sum(cross,1),qY,numel(port0),sum(abs(powers),1)+sum(abs(cross),1));
    assertMoment(double(matched.MeasuredMinusTargetPowerPerReceiveColumn(:).'), ...
        double(matched.NonTargetPlusCrossMinusBiasPerReceiveColumn(:).'),numel(port0), ...
        sum(abs(powers),1)+sum(abs(cross),1)+abs(bias));
    imTerms=matched.CSIIMTerms;
    assert(~imTerms.TargetLeakageSubtracted&& ...
        isequal(imTerms.TargetLeakagePowerPerReceiveColumn(:),imTerms.PowerPerTermPerReceiveColumn(1,:).'));
    assertMoment(sum(imTerms.PowerPerTermPerReceiveColumn,1)+ ...
        sum(imTerms.SignedCrossPowerPerReceiveColumn,1),D,im.SampleCount, ...
        sum(abs(imTerms.PowerPerTermPerReceiveColumn),1)+sum(abs(imTerms.SignedCrossPowerPerReceiveColumn),1));
    assert(~q.SINRComparison.SINREstimandCompatible, ...
        'test:CSIIMRawEstimand','A recorded CDM comparison does not qualify the distinct raw target-RE ratio.');
end
if enabled
    selected=reception.CSIRSObservation.MeasurementSelectedResourceOrdinal;
    assert(e.SelectedResourceOrdinal1==selected&&row.(prefix+"SelectedResourceID")==resources(selected).ResourceID);
    chosen=comparisons(selected).MatchedCDMModelComparison;
    assert(row.(prefix+"CDMStatus")==string(chosen.Status));
    for name=["ReportedPowerDifference_dB","SelectedColumnPowerDifference_dB", ...
            "ReportedSINRLogRatioDifference_dB","SelectedColumnSINRLogRatioDifference_dB"]
        assert(isequaln(row.(prefix+"CDM"+name),str2double(string(chosen.NumericTokens.(name)))));
    end
end
end

function audit=assertCorruptions(item,reception,desired,source,replay,owner)
prefix="CSIRSLinearPortModelComparison"; before=rng; clocks=channelClock(owner);
original=reception; trace=owner.Events.ExecutionTrace;
audit=struct('Scope',"copied_invalid_evidence_post_reception_only", ...
    'ScorerCalls',0,'OFDMDemodulationAttempts',0,'OFDMDemodulations',0, ...
    'PracticalReceiverCalls',0,'RFExecutions',0,'ChannelExecutions',0,'TimingAcquisitions',0);
target=find(string({item.Planes.ReceiverID})==item.Context.CSIRSPortReferencePlanes(1).PlaneID);
assert(isscalar(target));
for mutation=1:8
    bad=item; received=reception; id="sixgr:refsig:CSIRSCDMModelReferenceOperands";
    measured=received.CSIRSObservation.MeasurementPhysicalResources;
    c=measured{1}.SINR.SignalPowerEstimation.CDMProjectionReceipt;
    switch mutation
        case 1
            c.ProjectionWeightsReal(1)=c.ProjectionWeightsReal(1)+.125;
        case 2 % Same support population in the wrong recorded tile order.
            assert(size(c.TileIndices1Based,2)>=2);
            c.TileIndices1Based(:,[1 2])=c.TileIndices1Based(:,[2 1]);
        case 3
            c.ProjectedCoefficientsReal(1)=c.ProjectedCoefficientsReal(1)+.25;
        case 4
            c.NormalizationPilotCount=c.NormalizationPilotCount+1;
        case 5 % Re-sealing cannot turn this shared observed denominator
               % into an independently observed or altered second moment.
            measured{1}.SINR.InterferenceMeasurement.Covariance(1)= ...
                measured{1}.SINR.InterferenceMeasurement.Covariance(1)+.25;
            id="sixgr:refsig:CSIRSSINRReferenceOperands";
        case 6 % Replaced samples plus a resealed local segment must still
               % fail against the original committed owner receipt.
            b=item.Planes(target).Observation; x=b.readComplete(); x(1)=x(1)+.01;
            replacement=sixgr.phy.waveform.WaveformObservationBuffer( ...
                b.StartSample,b.EndSampleExclusive,b.SampleRateHz,b.NumReceiveAntennas);
            replacement.append(sixgr.phy.waveform.WaveformChunk(x,b.StartSample),b.SampleRateHz);
            bad.Planes(target).Observation=replacement;
            receipts=bad.Planes(target).Segments{1}.Execution.CSIRSPortReferences;
            hit=find(string({receipts.PlaneID})==bad.Context.CSIRSPortReferencePlanes(1).PlaneID);
            assert(isscalar(hit));
            rows=(receipts(hit).StartSample-b.StartSample+1):(receipts(hit).EndSampleExclusive-b.StartSample);
            receipts(hit).OutputSHA256=sixgr.phy.waveform.WaveformHash.numeric(x(rows,:));
            bad.Planes(target).Segments{1}.Execution.CSIRSPortReferences=receipts;
            id="sixgr:truth:CSIRSLinearModelCommit";
        case 7
            bad.Context.CSIRSPortReferencePlanes=bad.Context.CSIRSPortReferencePlanes([2 1]);
            id="sixgr:truth:CSIRSLinearModelIdentity";
        case 8 % Do not promote the original measurement-only receipt.
            c.OriginalSharedOwnerBound=true;
    end
    measured{1}.SINR.SignalPowerEstimation.CDMProjectionReceipt=c;
    measured{1}.SINR.SignalPowerEstimation.CDMProjectionReceiptSHA256= ...
        string(sixgr.util.sha256Hex(char(jsonencode(c))));
    received.CSIRSObservation.MeasurementPhysicalResources=measured;
    received.CSIRSObservation.MeasurementPhysicalResourcesJSON= ...
        string(jsonencode(sixgr.util.jsonSafeValue(measured)));
    result=sixgr.truth.scoreSharedCSIRSLinearPortModel(bad,received,desired,source,replay,owner);
    recorded=jsondecode(result.(prefix+"EvidenceJSON"));
    audit.ScorerCalls=audit.ScorerCalls+1;
    for pair={"OFDMDemodulationAttempts","AdditionalOFDMDemodulationAttempts"; ...
            "OFDMDemodulations","AdditionalOFDMDemodulations"; ...
            "RFExecutions","AdditionalRFExecutions"; ...
            "ChannelExecutions","AdditionalChannelExecutions"; ...
            "TimingAcquisitions","AdditionalTimingAcquisitions"}.'
        audit.(pair{1})=audit.(pair{1})+recorded.(pair{2});
    end
    assert(~result.(prefix+"Available")&&~result.(prefix+"CDMOperatorMatchedModelAvailable")&& ...
        result.(prefix+"ErrorIdentifier")==id&&result.(prefix+"ResourceCount")==0&& ...
        isnan(result.(prefix+"CDMReportedPowerDifference_dB"))&& ...
        isnan(result.(prefix+"CDMReportedSINRLogRatioDifference_dB")), ...
        'test:CSIIMModelMissingRejection','Mutation %d returned %s, expected %s.', ...
        mutation,result.(prefix+"ErrorIdentifier"),id);
end
assert(isequaln(reception,original)&&isequal(before,rng)&& ...
    isequaln(clocks,channelClock(owner))&&isequaln(trace,owner.Events.ExecutionTrace)&& ...
    audit.ScorerCalls==8&&audit.RFExecutions==0&&audit.ChannelExecutions==0&&audit.TimingAcquisitions==0);
fprintf('SHARED_CSIRS_MULTIPORT_CSIIM_GUARDS_PASS negatives=8 receiver_reexecutions=0\n');
end

function assertMoment(actual,expected,count,scale)
% Forward-error bound for a finite sequence of complex products, sums and
% division. Include absolute cross terms so cancellation does not make the
% acceptance bound depend on a small final residual. No physical tolerance.
assert(isequal(size(actual),size(expected))&&all(isfinite(actual),'all')&&all(isfinite(expected),'all'));
if nargin<4, scale=abs(actual)+abs(expected); end
u=eps('double'); operations=16*double(count)+64;
assert(operations*u<1);
gamma=operations*u/(1-operations*u);
bound=gamma*max(realmin('double'),abs(actual)+abs(expected)+scale);
assert(all(abs(actual-expected)<=bound,'all'),'test:CSIIMProjectionClosure', ...
    'Original recorded projection/energy closure exceeds its arithmetic operation-count bound.');
end
