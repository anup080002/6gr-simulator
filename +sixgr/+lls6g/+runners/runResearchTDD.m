function out=runResearchTDD(scfg,outputDir,runTag)
%RUNRESEARCHTDD Coded shared channels on one continuous TDD lab clock.
% This deliberately distinct runner does not claim initial access, control,
% feedback, RF impairments, acquired timing or a standardized 6G air interface.
s=scfg.toStruct();
sixgr.lls6g.config.validateScenarioConfig(s);
p=s.research_link;
catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
assert(all(isfield(p,fieldnames(catalog.sections.research_link.parameters))), ...
    'sixgr:research:IncompleteLinkConfig','Every research_link policy must be explicit.');
assert(string(s.meta.research_class)=="optional_research_experiment" && ...
    string(s.scenario.runner_profile)=="research_tdd_link" && ...
    string(s.simulation.link_direction)=="both" && s.research_dl.enabled && s.research_ul.enabled, ...
    'sixgr:research:ExplicitLinkScopeRequired','Select the bidirectional research TDD lab profile.');
physical=string(p.channel)=="physical_cdl";
fixedPorts=isfield(s,'research_awgn_mimo');
assert(~fixedPorts || ~physical,'sixgr:research:AWGNPortsRequireIdentity', ...
    'research_awgn_mimo applies only to the identity-AWGN channel.');
harqEnabled=logical(s.harq.enabled);
adaptationEnabled=isfield(s,'research_adaptation') && s.research_adaptation.enabled;
assert(~adaptationEnabled || (harqEnabled && fixedPorts && ~physical), ...
    'sixgr:research:AdaptationRequiresHARQ','Research adaptation requires ideal HARQ on fixed-port identity AWGN.');
assert(all([logical(s.research_dl.harq_enabled),logical(s.research_ul.harq_enabled)]==harqEnabled), ...
    'sixgr:research:HARQPolicyMismatch','Global and DL/UL research HARQ enablement must agree.');
if harqEnabled
    assert(isfield(s,'research_harq') && string(s.research_harq.feedback_mode)=="ideal_delayed" && ~physical, ...
        'sixgr:research:UnsupportedHARQTransport','Research HARQ currently supports explicitly ideal-delayed feedback on identity AWGN.');
end
validChannel=(~physical && string(p.channel)=="identity_awgn" && ...
    string(s.channels.model_type)=="AWGN" && ...
    string(p.noise_reference)=="unit_constellation_per_port_after_precoding") || ...
    (physical && string(s.channels.model_type)=="CDL" && ...
    string(p.noise_reference)=="unit_constellation_per_layer_before_channel");
assert(validChannel && ...
    ~s.channels.pathloss_enabled && ~s.channels.shadow_fading_enabled && ...
    string(p.timing)=="preconfigured_slot_boundary" && string(p.rf)=="ideal_no_impairments", ...
    'sixgr:research:UnsupportedLinkPolicy','Use identity AWGN or explicit physical CDL, ideal RF, configured timing and the matching noise reference.');
disabled=["reference_signals.ssb_enabled","reference_signals.pbch_enabled", ...
    "reference_signals.csi_rs_enabled","reference_signals.srs_enabled", ...
    "reference_signals.trs_enabled","reference_signals.tracking_rs_enabled", ...
    "reference_signals.ptrs_enabled","reference_signals.csi_reporting_enabled", ...
    "initial_access.enabled","random_access.enabled","control.pdcch_enabled", ...
    "control.pucch_enabled","control.blind_search_enabled","harq.enabled", ...
    "users.enabled","ai_ml.enabled","energy_efficiency.enabled", ...
    "impairments.cfo_enabled","impairments.phase_noise_enabled", ...
    "impairments.iq_imbalance_enabled","impairments.pa_nonlinearity_enabled", ...
    "impairments.timing_offset_enabled"];
if harqEnabled, disabled(disabled=="harq.enabled")=[]; end
for field=disabled
    assert(~logical(scfg.get(field,false)),'sixgr:research:UnsupportedEnabledBlock', ...
        '%s must be disabled for this preconfigured lab profile.',field);
end
assert(~p.export_keysight || p.capture_iq,'sixgr:research:CaptureRequired', ...
    'research_link.export_keysight requires capture_iq.');
assert(string(scfg.get('output.backend','filesystem'))=="filesystem", ...
    'sixgr:research:FilesystemRequired','Research lab artifacts currently require output.backend=filesystem.');
assert(~s.simulation.reference_sweep_enabled && ~s.simulation.adaptive_sweep_enabled, ...
    'sixgr:research:SinglePointOnly','Single-run profile executes simulation.snr_db only.');
frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
assert(frame.DuplexMode=="TDD",'sixgr:research:TDDRequired','TDD is required.');
if physical
    spatial=sixgr.phy.research.PhysicalArrayLink.build(s,frame.SampleRate_Hz);
    % Avoid concatenating a 64-element high-rate capture in laptop memory.
    assert(~p.capture_iq,'sixgr:research:SpatialCaptureNotImplemented', ...
        'physical_cdl currently exports CSV/PNG and array evidence; disable capture_iq.');
end
if harqEnabled
    sessions={sixgr.phy.research.IdealDelayedHARQ(s,"DL"),sixgr.phy.research.IdealDelayedHARQ(s,"UL")};
end
if adaptationEnabled
    controllers={sixgr.phy.research.AWGNLinkAdaptation(s,"DL"),sixgr.phy.research.AWGNLinkAdaptation(s,"UL")};
end
if strlength(string(runTag))==0, runTag=string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')); end
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9_.-]+$','once')) && ...
    ~any(string(runTag)==[".",".."]),'sixgr:research:InvalidRunTag','Use a simple run tag.');
root=fullfile(outputDir,'lls',char(scfg.ScenarioID),char(runTag));
assert(~isfolder(root),'sixgr:research:RunAlreadyExists','Refusing to overwrite %s.',root);
mkdir(root); mkdir(fullfile(root,'meta')); mkdir(fullfile(root,'meta','input_configs'));
sixgr.util.jsonWrite(fullfile(root,'meta','resolved_config.json'),s);
sixgr.lls6g.config.writeYAML(fullfile(root,'meta','resolved_config.yaml'),s);
for k=1:numel(scfg.SourceFiles)
    [~,name,ext]=fileparts(scfg.SourceFiles(k));
    copyfile(scfg.SourceFiles(k),fullfile(root,'meta','input_configs',sprintf('%03d_%s%s',k,name,ext)));
end
[~,commit]=system('git rev-parse HEAD'); [~,dirty]=system('git status --porcelain');
meta=struct('Status',"running",'ResultOk',false,'ResearchClass',string(s.meta.research_class), ...
    'StandardNR',false,'ExecutionBackend',"actual_coded_research_TDD_waveform", ...
    'ApproximationMode',"none",'ChannelModel',string(p.channel), ...
    'ConfigHash',scfg.ConfigHash,'SourceFiles',scfg.SourceFiles, ...
    'GitCommit',strtrim(string(commit)),'GitDirty',strlength(strtrim(string(dirty)))>0, ...
    'DisabledBlocks',disabled,'TimingSource',string(p.timing), ...
    'RFPolicy',string(p.rf),'NoiseReference',string(p.noise_reference), ...
    'ConfiguredReferenceSNRdB',s.simulation.snr_db,'NoiseFreeTX',true, ...
    'StatisticalQualification',false,'InstrumentImportVerified',false, ...
    'PowerUnits',"normalized_baseband_not_dBm",'CenterFrequencyUse',"RF_metadata_no_passband_upconversion", ...
    'DataAllocationAuthority',"research_dl_and_research_ul", ...
    'InactiveLegacyDataSections',["modulation","coding","mimo"], ...
    'HorizonAuthority',"simulation.n_slots_and_actual_OFDM_sample_count");
meta.HARQEnabled=harqEnabled;
meta.LinkAdaptationEnabled=adaptationEnabled;
meta.AcceptanceScope="payload_delivery_not_throughput_target_or_statistical_BLER_qualification";
if fixedPorts, meta.FixedPhysicalAWGNPorts=s.research_awgn_mimo; end
if harqEnabled
    meta.HARQFeedbackMode="ideal_error_free_delayed_receiver_CRC_no_control_waveform";
    meta.ApproximationMode="ideal_delayed_HARQ_feedback_actual_coded_data_waveforms";
    meta.HARQPolicy=s.research_harq;
    meta.HARQDrainPolicy="feedback_only_no_new_data_or_retransmissions_after_configured_data_horizon";
end
if adaptationEnabled
    meta.LinkAdaptationInput="ideal_delayed_received_DMRS_noise_with_perfect_identity_channel_no_CSI_report_waveform";
    meta.LinkAdaptationPolicy="coded_calibrated_ILLA_rank_QAM_selection_plus_first_transmission_CRC_OLLA";
    meta.AdaptationTargetFirstTransmissionBLER=s.research_adaptation.target_bler;
    meta.CalibrationSHA256=controllers{1}.CalibrationSHA256;
    meta.ApproximationMode="ideal_delayed_HARQ_and_measurement_feedback_actual_coded_data_waveforms";
    copyfile(s.research_adaptation.calibration_file,fullfile(root,'meta','adaptation_calibration.csv'));
end
if physical
    meta.PhysicalArray=spatial.Manifest;
    meta.CenterFrequencyUse="CDL_carrier_and_array_wavelength_no_passband_upconversion";
    meta.WaveformScope="independent_static_CDL_bursts_on_configured_TDD_clock";
    sixgr.phy.research.PhysicalArrayLink.export(root,spatial);
end
sourcePaths=[string(mfilename('fullpath'))+".m", ...
    string(which('sixgr.phy.research.SharedChannelLink')), ...
    string(which('sixgr.phy.research.IdealDelayedHARQ')), ...
    string(which('sixgr.phy.research.AWGNLinkAdaptation')), ...
    string(which('sixgr.phy.research.exportLabIQ')), ...
    string(which('sixgr.phy.research.PhysicalArrayLink'))];
sourceEvidence=struct([]);
mkdir(fullfile(root,'meta','executed_sources'));
for k=1:numel(sourcePaths)
    [~,name,ext]=fileparts(sourcePaths(k));
    copyfile(sourcePaths(k),fullfile(root,'meta','executed_sources',name+ext));
    sourceEvidence(k).Path=sourcePaths(k); %#ok<AGROW>
    sourceEvidence(k).SHA256=sixgr.util.sha256File(sourcePaths(k)); %#ok<AGROW>
end
sixgr.util.jsonWrite(fullfile(root,'meta','executed_source_hashes.json'),sourceEvidence);
sixgr.util.jsonWrite(fullfile(root,'meta','manifest.json'),meta);
sixgr.util.jsonWrite(fullfile(root,'meta','schema_validation_report.json'),struct('Passed',true));
sixgr.util.jsonWrite(fullfile(root,'meta','environment_summary.json'), ...
    struct('MATLAB',version,'Computer',computer,'Toolboxes',ver));
sixgr.util.jsonWrite(fullfile(root,'meta','seeds.json'),struct('Seed',s.simulation.random_seed,'Generator',"twister"));
state=rng; restore=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
directions=["DL","UL"]; n=s.simulation.n_slots;
dataSlots=n;
if harqEnabled, n=n+s.research_harq.feedback_drain_slots; end
txParts=cell(n,2); rxParts=cell(n,2); trials=struct([]); timeline=struct([]); cursor=0;
layerTrials=struct([]);
try
    for slot=0:n-1
        if harqEnabled
            for d=1:2, sessions{d}.advance(slot); end
        end
        if adaptationEnabled
            for d=1:2
                controllers{d}.advance(sessions{d}.Feedback,slot);
                if ~isempty(controllers{d}.Updates)
                    sixgr.util.csvWriteTable(fullfile(root,'adaptation','csv',lower(directions(d))+"_olla_updates.csv"), ...
                        struct2table(controllers{d}.Updates));
                end
            end
        end
        carrier=nrCarrierConfig('NSizeGrid',frame.NRB,'SubcarrierSpacing',frame.SCSkHz, ...
            'CyclicPrefix',char(frame.CyclicPrefix),'NSlot',mod(slot,frame.SlotsPerFrame), ...
            'NFrame',mod(floor(slot/frame.SlotsPerFrame),1024));
        [silent,ofdm]=sixgr.phy.waveform.ofdmModulate(carrier,nrResourceGrid(carrier), ...
            'Nfft',frame.FFTSize,'SampleRate',frame.SampleRate_Hz,'Windowing',s.waveform.windowing_samples);
        count=size(silent,1); stop=cursor+count;
        active=[frame.IsDLAllocation(slot,s.research_dl.symbol_allocation), ...
            frame.IsULAllocation(slot,s.research_ul.symbol_allocation)];
        eligible=active;
        if slot>=dataSlots, active(:)=false; end
        assert(~all(active),'sixgr:research:TDDOverlap','Full-slot DL/UL allocations overlap.');
        for d=1:2
            direction=directions(d); ch=s.("research_"+lower(direction));
            clean=complex(zeros(count,ch.num_layers));
            % Unit-energy constellation and unit-total-power precoder imply
            % expected data-RE power 1/L per port. No received metric is set.
            referencePower=1/ch.num_layers;
            if fixedPorts
                clean=complex(zeros(count,s.research_awgn_mimo.physical_ports));
                referencePower=s.research_awgn_mimo.reference_data_re_power;
            end
            nvGrid=referencePower/10^(s.simulation.snr_db/10);
            nvSample=nvGrid/ofdm.SampleToGridNoiseVarianceGain;
            if active(d)
                if harqEnabled
                    proposed=s; allowNew=true;
                    if adaptationEnabled
                        [proposed,allowNew,decision]=controllers{d}.select(s,slot);
                        sixgr.util.csvWriteTable(fullfile(root,'adaptation','csv',lower(direction)+"_decisions.csv"), ...
                            struct2table(controllers{d}.Decisions),'PreserveSchema',true);
                    end
                    [plan,tb,attemptConfig]=sessions{d}.reserve(proposed,slot,allowNew);
                    active(d)=~isempty(fieldnames(plan));
                else
                    attemptConfig=s;
                end
            end
            if active(d)
                a=sixgr.phy.research.SharedChannelLink.allocation(attemptConfig,slot,direction);
                if harqEnabled
                    tx=sixgr.phy.research.SharedChannelLink.transmit(attemptConfig,slot,tb,direction,'HARQKey',plan.HARQKey);
                    sessions{d}.transmitted(plan,tx);
                else
                    tb=int8(randi([0 1],a.TransportBlockSize,1));
                    tx=sixgr.phy.research.SharedChannelLink.transmit(attemptConfig,slot,tb,direction);
                end
                clean=tx.Waveform;
                assert(size(clean,1)==count,'sixgr:research:ClockMismatch','TX slot sample clock differs.');
            end
            signal=clean;
            if physical
                if active(d)
                    [signal,physicalTX,arrayEvidence]=sixgr.phy.research.PhysicalArrayLink.apply(spatial,d,clean);
                    clear physicalTX
                else
                    signal=complex(zeros(count,spatial.RxElements(d)));
                end
            end
            noise=sqrt(nvSample/2)*(randn(size(signal))+1j*randn(size(signal)));
            noisy=signal+noise;
            if p.capture_iq, txParts{slot+1,d}=clean; rxParts{slot+1,d}=noisy; end
            if active(d)
                receiveOptions={};
                if harqEnabled, receiveOptions=sessions{d}.receiveOptions(plan); end
                rx=sixgr.phy.research.SharedChannelLink.receive(attemptConfig,slot,noisy,direction,receiveOptions{:});
                if harqEnabled, sessions{d}.received(plan,rx); end
                bitErrors=sum(rx.TransportBlock~=tb);
                evm=sqrt(mean(abs(rx.EqualizedSymbols(:)-tx.LayerSymbols(:)).^2)/mean(abs(tx.LayerSymbols(:)).^2));
                portGrid=reshape(tx.Grid,[],a.NumPhysicalPorts);
                dataPortPower=abs(portGrid(a.DataIndices(:,1),:)).^2;
                row=struct('Direction',direction,'AbsoluteSlot',slot,'TBID',direction+"_"+slot, ...
                    'StartSample',cursor,'StopSampleExclusive',stop, ...
                    'TBSBits',numel(tb),'CodedBits',a.G,'Qm',a.Qm,'Layers',a.NumLayers, ...
                    'TargetCodeRate',a.TargetCodeRate,'CRCPass',logical(rx.CRCPass), ...
                    'TBExact',bitErrors==0,'BitErrors',bitErrors,'BER',bitErrors/numel(tb), ...
                    'CodedBER',mean(int8(rx.CodewordLLR<0)~=tx.Codeword), ...
                    'EVMRMS',evm,'ReferenceErrorSINRdB',-20*log10(evm), ...
                    'ConfiguredReferenceSNRdB',s.simulation.snr_db, ...
                    'NoiseReferenceDataREPower',referencePower, ...
                    'ExpectedDataREPowerPerPort',1/a.NumPhysicalPorts, ...
                    'MeasuredTXDataREPower',mean(dataPortPower,'all'), ...
                    'MeasuredTXTotalDataREPower',mean(sum(dataPortPower,2)), ...
                    'InjectedSampleNoiseVariance',nvSample,'ExpectedGridNoiseVariance',nvGrid, ...
                    'MeasuredDMRSNoiseVariance',rx.NoiseVariance, ...
                    'Source',"actual_coded_research_waveform",'StandardNR',false);
                row.PhysicalTxElements=size(clean,2);
                if adaptationEnabled
                    row.ProposedNewDataCandidate=decision.NewDataCandidate;
                    row.OLLAMarginDb=decision.OLLAMarginDb;
                    row.AdaptationMeasurementSlot=decision.MeasurementSlot;
                    row.NewDataBootstrap=decision.BootstrapUsed && ~plan.HARQ.IsRetransmission;
                end
                row.ChannelEstimateSource=rx.ChannelEstimateSource;
                row.PerfectCSI=rx.PerfectCSI;
                row.LDPCBaseGraph=double(a.CodingLayout.BaseGraph);
                if harqEnabled
                    row.TBID=plan.HARQKey;
                    row.HARQProcessId=plan.HARQ.HarqID;
                    row.HARQAttemptIndex=plan.HARQ.HARQRound+1;
                    row.RV=plan.HARQ.RV;
                    row.IsRetransmission=logical(plan.HARQ.IsRetransmission);
                    row.HARQCombiningApplied=rx.HARQCombiningApplied;
                    row.FeedbackAvailableSlot=slot+s.research_harq.feedback_delay_slots;
                    row.FeedbackMode="ideal_delayed_receiver_CRC";
                end
                row.PhysicalRxElements=size(noisy,2);
                row.MeasuredInjectedSampleNoiseVariance=mean(abs(noise).^2,'all');
                if physical
                    names=fieldnames(arrayEvidence);
                    for field=1:numel(names), row.(names{field})=arrayEvidence.(names{field}); end
                end
                for layer=1:a.NumLayers
                    layerEVM=sqrt(mean(abs(rx.EqualizedSymbols(:,layer)-tx.LayerSymbols(:,layer)).^2)/ ...
                        mean(abs(tx.LayerSymbols(:,layer)).^2));
                    lr=struct('Direction',direction,'AbsoluteSlot',slot,'Layer',layer, ...
                        'EVMRMS',layerEVM,'ReferenceErrorSINRdB',-20*log10(layerEVM), ...
                        'Source',"decoded_waveform_equalized_symbols_against_transmitted_reference");
                    if isempty(layerTrials), layerTrials=lr; else, layerTrials(end+1)=lr; end %#ok<AGROW>
                end
                if isempty(trials), trials=row; else, trials(end+1)=row; end %#ok<AGROW>
                fprintf('RESEARCH_TDD slot=%d %s CRC=%d TBbits=%d EVM=%g\n',slot,direction,rx.CRCPass,numel(tb),evm);
                % Persist real rows incrementally; a later failure cannot erase them.
                sixgr.util.csvWriteTable(fullfile(root,'reports','csv','trials.csv'),struct2table(trials));
                sixgr.util.csvWriteTable(fullfile(root,'reports','csv','layer_measurements.csv'),struct2table(layerTrials));
                clear rx tx
            end
        end
        tick=struct('AbsoluteSlot',slot,'StartSample',cursor, ...
            'StopSampleExclusive',stop,'DLActive',active(1),'ULActive',active(2));
        tick.DLEligible=eligible(1); tick.ULEligible=eligible(2);
        tick.FeedbackDrainSlot=slot>=dataSlots;
        if isempty(timeline), timeline=tick; else, timeline(end+1)=tick; end %#ok<AGROW>
        cursor=stop;
    end
    T=struct2table(trials); horizon=cursor/frame.SampleRate_Hz;
    assert(all(T.TBExact(T.CRCPass)),'sixgr:research:UndetectedPayloadError', ...
        'A CRC-passing decoded payload differed from its transmitted TB; do not count it as successful truth.');
    summaries=struct([]);
    for d=1:2
        rows=T.Direction==directions(d); good=rows & T.CRCPass & T.TBExact;
        assert(any(rows),'sixgr:research:UnexecutedDirection','Configured horizon must execute both DL and UL.');
        summary=struct('Direction',directions(d),'TransportBlocks',sum(rows), ...
            'SuccessfulUniqueTBs',sum(good),'BLER',1-sum(good)/sum(rows), ...
            'DeliveredUniqueBits',sum(T.TBSBits(good)),'HorizonSeconds',horizon, ...
            'GoodputBitsPerSecond',sum(T.TBSBits(good))/horizon, ...
            'BER',sum(T.BitErrors(rows))/sum(T.TBSBits(rows)), ...
            'Source',"actual_coded_research_waveform",'StandardNR',false);
        if harqEnabled
            ledger=sessions{d}.Entity.getDeliveryLedger();
            delivered=logical(ledger.FirstSuccessDelivery);
            assert(numel(unique(ledger.TransportBlockId(delivered)))==sum(delivered), ...
                'sixgr:research:DuplicateGoodput','Each HARQ TB may contribute payload exactly once.');
            summary.TransmissionAttempts=sum(rows);
            summary.TransportBlocks=sum(rows & ~T.IsRetransmission);
            summary.SuccessfulUniqueTBs=sum(delivered);
            summary.DeliveredUniqueBits=sum(ledger.CountedGoodputBits);
            summary.GoodputBitsPerSecond=summary.DeliveredUniqueBits/horizon;
            summary.BLER=1-summary.SuccessfulUniqueTBs/summary.TransportBlocks;
            summary.FirstTransmissionBLER=mean(~T.CRCPass(rows & ~T.IsRetransmission));
            summary.AttemptBLER=mean(~T.CRCPass(rows));
            summary.BERPopulation="decoded_bits_across_transmission_attempts";
            summary.PendingTransportBlocks=sessions{d}.pendingCount();
            summary.DroppedTransportBlocks=sessions{d}.Entity.Stats.Drop;
            summary.FeedbackMode="ideal_delayed_receiver_CRC";
            sixgr.util.csvWriteTable(fullfile(root,'harq','csv',lower(directions(d))+"_delivery_ledger.csv"),ledger);
            if ~isempty(sessions{d}.Feedback)
                sixgr.util.csvWriteTable(fullfile(root,'harq','csv',lower(directions(d))+"_feedback.csv"),struct2table(sessions{d}.Feedback));
            end
        end
        if adaptationEnabled
            ctl=controllers{d};
            summary.LinkAdaptationTargetBLER=s.research_adaptation.target_bler;
            summary.OLLAFirstAttemptUpdates=numel(ctl.Updates);
            summary.NewDataOutageDecisions=sum(~[ctl.Decisions.AllowNewTB]);
            sixgr.util.csvWriteTable(fullfile(root,'adaptation','csv',lower(directions(d))+"_decisions.csv"),struct2table(ctl.Decisions));
            if ~isempty(ctl.Updates)
                sixgr.util.csvWriteTable(fullfile(root,'adaptation','csv',lower(directions(d))+"_olla_updates.csv"),struct2table(ctl.Updates));
            end
        end
        if isempty(summaries), summaries=summary; else, summaries(d)=summary; end %#ok<AGROW>
    end
    S=struct2table(summaries);
    sixgr.util.csvWriteTable(fullfile(root,'reports','csv','summary.csv'),S);
    sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv','timeline.csv'),struct2table(timeline));
    iq=struct([]);
    if p.capture_iq
        for d=1:2
            for point=["TX","RX"]
                if point=="TX"
                    wave=vertcat(txParts{:,d}); txParts(:,d)={[]};
                else
                    wave=vertcat(rxParts{:,d}); rxParts(:,d)={[]};
                end
                receipt=sixgr.phy.research.exportLabIQ(root,wave,frame.SampleRate_Hz, ...
                    s.frequency.center_frequency_hz,directions(d),point,p.export_keysight);
                if isempty(iq), iq=receipt(:); else, iq=[iq;receipt(:)]; end %#ok<AGROW>
                clear wave
            end
        end
        sixgr.util.csvWriteTable(fullfile(root,'waveform','iq_manifest.csv'),struct2table(iq));
    end
    if p.save_plots
        folder=fullfile(root,'reports','image'); mkdir(folder);
        fig=figure('Visible','off'); closeFig=onCleanup(@()close(fig)); %#ok<NASGU>
        bar(categorical(S.Direction),S.GoodputBitsPerSecond/1e9);
        ylabel('Delivered unique TB Gbit/s over full TDD horizon');
        title('Research lab observation; not statistical qualification');
        exportgraphics(fig,fullfile(folder,'tdd_goodput.png'));
    end
    passed=all(T.CRCPass & T.TBExact);
    if harqEnabled
        passed=all(S.SuccessfulUniqueTBs==S.TransportBlocks) && ...
            all(S.PendingTransportBlocks==0 & S.DroppedTransportBlocks==0);
    end
    meta.Status="completed"; meta.ResultOk=passed; meta.SampleCount=cursor;
    meta.HorizonSeconds=horizon; meta.SampleRateHz=frame.SampleRate_Hz;
    meta.SuccessfulTransportBlocks=sum(T.CRCPass & T.TBExact);
    meta.ExecutedTransportBlocks=height(T);
    if harqEnabled
        meta.TransmissionAttempts=height(T);
        meta.SuccessfulTransportBlocks=sum(S.SuccessfulUniqueTBs);
        meta.ExecutedTransportBlocks=sum(S.TransportBlocks);
        meta.PendingTransportBlocks=sum(S.PendingTransportBlocks);
        meta.DroppedTransportBlocks=sum(S.DroppedTransportBlocks);
    end
    sixgr.util.jsonWrite(fullfile(root,'meta','manifest.json'),meta);
    sixgr.util.writeTextFile(fullfile(root,'reports','README.md'), ...
        "# Research TDD lab observation"+newline+newline+ ...
        "See summary.csv and trials.csv. Throughput uses the complete sample-clock horizon. "+ ...
        "Configured SNR is a pre-channel noise reference, not forced measured SINR. "+ ...
        "See manifest.json for the executed channel and physical-array policy. "+ ...
        "Initial access/control waveforms and RF impairments did not execute. "+ ...
        "Any HARQ feedback is the explicitly declared ideal delayed receiver-CRC model. "+ ...
        "This is neither statistical BLER qualification nor a best-throughput search."+newline);
    out=struct('RunFolder',string(root),'ResultOk',passed,'Ok',passed,'Config',scfg, ...
        'SummaryTable',S,'TrialTable',T,'Manifest',meta);
    assert(~p.require_all_tb_success || passed,'sixgr:research:TBFailure', ...
        'Research run completed with failed transport blocks; evidence is preserved at %s.',root);
catch ME
    meta.Status="failed"; meta.ResultOk=false; meta.ErrorIdentifier=string(ME.identifier);
    meta.ErrorMessage=string(ME.message);
    sixgr.util.jsonWrite(fullfile(root,'meta','manifest.json'),meta);
    rethrow(ME);
end
end
