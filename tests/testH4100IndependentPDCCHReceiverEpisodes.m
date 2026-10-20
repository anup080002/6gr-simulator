function ok=testH4100IndependentPDCCHReceiverEpisodes()
% Three actual installed H4 episodes. Contract mutations below are NOT
% additional physical trials. Never put this development evidence into a
% continuous scenario or a statistical qualification population.
setup6GRSimToolkit('Verbose',false);
policyFile='simulator/configs/validation/h4_100_installed_pdcch_development.yaml';
p=sixgr.lls6g.config.readConfigFile(policyFile);
assert(p.schema_version==1 && string(p.research_class)=="optional_research_experiment" && ...
    string(p.dci_field_basis)=="installed_schema_minima_with_explicit_overrides");
source=sixgr.lls6g.config.loadScenarioConfig(p.scenario_path);
folder=fullfile(pwd,'results','lls','h4_installed_pdcch', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'test:EvidenceExists'); mkdir(folder);
files=[string(mfilename('fullpath'))+".m",string(policyFile), ...
    "+sixgr/+link/runIndependentPDCCHReceiverEpisode.m", ...
    "+sixgr/+link/scoreIndependentPDCCHReceiverEpisode.m", ...
    "+sixgr/+link/prepareSharedPDCCHTransmission.m", ...
    "+sixgr/+phy/+dl/PDCCH_Rx.m","+sixgr/+phy/+dl/PDCCH_Tx.m", ...
    "+sixgr/+channel/ChannelFactory.m","+sixgr/+rf/+runtime/RFImpairmentStream.m", ...
    "+sixgr/+phy/+pdcch/applyMMSECSIWeighting.m"];
files=[files(:);source.SourceFiles(:)];
hashes=arrayfun(@(f)string(sixgr.util.sha256File(f)),files);
save(fullfile(folder,'sources.mat'),'files','hashes');
copyfile(policyFile,fullfile(folder,'episode_design.yaml'));
mkdir(fullfile(folder,'input_configs'));
for k=1:numel(source.SourceFiles)
    [~,name,ext]=fileparts(source.SourceFiles(k));
    destination=fullfile(folder,'input_configs',sprintf('%03d_',k)+name+ext);
    copyfile(source.SourceFiles(k),destination);
    assert(strcmp(sixgr.util.sha256File(destination),sixgr.util.sha256File(source.SourceFiles(k))));
end
sixgr.util.jsonWrite(fullfile(folder,'resolved_scenario.json'),source.toStruct());
allEvents=table();
for k=1:numel(p.cases)
    c=p.cases(k); data=source.toStruct();
    for path=string(p.scenario_seed_paths(:)).'
        assert(source.has(path) && isnumeric(source.get(path)) && isscalar(source.get(path)));
        data=sixgr.util.structSet(data,path,c.channel_seed);
    end
    sixgr.lls6g.config.validateScenarioConfig(data,'Context',p.profile_id);
    seeded=sixgr.lls6g.config.ScenarioConfig(data,'SourceFiles',source.SourceFiles, ...
        'ConfigPath',source.ConfigPath,'Kind',source.Kind, ...
        'ConfigHash',sixgr.lls6g.config.hashResolvedScenario(data));
    cfg=sixgr.lls6g.buildInternalConfig(seeded,folder);
    assert(cfg.phy.fc_Hz==4e9 && cfg.phy.carrier.NSizeGrid==273 && ...
        cfg.phy.nTxAnt==64 && cfg.phy.nRxAnt==4 && sixgr.channel.resolveConcreteProfile(cfg)=="CDL-C");
    cfg=sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,p.ue_index,1);
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,p.absolute_slot0+1);
    carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
    cfg.lls6g.userContext.RuntimeSlotStartTime_s= ...
        sixgr.phy.frame.slotStartSample(carrier,p.absolute_slot0,ofdm.SampleRate)/ofdm.SampleRate;
    d=struct('EpisodeID',string(c.id),'UEIndex',p.ue_index,'ServingCell',p.serving_cell, ...
        'ChannelSeed',c.channel_seed,'NoiseSeed',c.noise_seed,'GuardSamples',p.guard_samples, ...
        'SignalPresent',c.signal_present,'AbsoluteSlot0',p.absolute_slot0,'TimingBoundary',string(p.timing_boundary));
    prepared=struct([]); expected=int8([]);
    if c.signal_present
        context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,c.transmitter.dci_format);
        schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
        fields=struct();
        for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
        for name=string(fieldnames(c.transmitter.fields)).'
            assert(isfield(fields,name),'test:UnknownAuthoredDCIField','Unknown field %s.',name);
            fields.(name)=c.transmitter.fields.(name);
        end
        authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
        prepared=sixgr.link.prepareSharedPDCCHTransmission(cfg,'DCIBits',authored.Bits, ...
            'RNTI',context.Data.RNTIValue);
        expected=authored.Bits;
    else
        % Reject invalid boundaries before constructing an output folder.
        bad=d; bad.SignalPresent=true;
        rejectExecution(cfg,prepared,bad,fullfile(folder,'bad_missing_tx'));
        rejectExecution(cfg,struct(),d,fullfile(folder,'bad_hidden_tx'));
        bad=d; bad.TimingBoundary="injected_alignment";
        rejectExecution(cfg,prepared,bad,fullfile(folder,'bad_timing'));
        bad=d; bad.UEIndex=2;
        rejectExecution(cfg,prepared,bad,fullfile(folder,'bad_owner'));
        changed=cfg; changed.phy.pdcch.blindSearch=false;
        rejectExecution(changed,prepared,d,fullfile(folder,'bad_known_candidate'));
    end
    out=sixgr.link.runIndependentPDCCHReceiverEpisode(cfg,prepared,d,fullfile(folder,string(c.id)));
    assert(out.Execution.RxDimensions==4 && out.Execution.ReceiverCompleted && ...
        out.ReceiverInfo.ReceiverConfiguredMonitoring && out.ReceiverInfo.BlindSearch && ...
        out.ReceiverInfo.NumCandidatesTried>1 && ...
        isempty(out.ReceiverInfo.ExpectedDCIBits) && out.ReceiverInfo.DCIBitsCompared==0 && ...
        all(out.ReceiverInfo.CandidateResults.LLRCount>0) && ...
        ~out.Execution.PrecedingSharedClockHistoryExecuted && ...
        out.Events.IndependentWaveformCount==1 && ~out.Events.HypothesesAreIndependentTrials && ...
        ~out.Events.StatisticallyQualified && ~out.Events.ScenarioAccepted);
    assert(out.RXReplay.ADCQuantizationApplied && out.RXReplay.PhaseNoiseApplied && ...
        out.RXReplay.TimingOffsetApplied && all(out.RFMeasurements.RunId==string(c.id)));
    if c.signal_present
        assert(out.Execution.TxDimensions==64 && out.Execution.DesiredChannelExecuted && ...
            out.Events.ExactPayloadRecovered==1 && out.Events.MissedPayloadEpisode==0 && ...
            out.Receiver.DecodedDCI.Format==string(c.transmitter.dci_format), ...
            'test:H4InstalledPDCCHMiss','Actual installed H1 failed; preserve it without threshold/seed tuning.');
        poisoned=1-expected;
        scored=sixgr.link.scoreIndependentPDCCHReceiverEpisode(out.Receiver,out.ReceiverInfo,poisoned,out.Execution);
        assert(scored.MissedPayloadEpisode==1 && scored.WrongPayloadAcceptanceEpisode==1);
    else
        assert(out.Execution.TxDimensions==0 && ~out.Execution.TransmitterExecuted && ...
            ~out.Execution.DesiredChannelExecuted && isempty(fieldnames(out.TXReplay)) && ...
            isempty(fieldnames(out.ChannelReplay)) && ...
            ~isfile(fullfile(folder,string(c.id),'transmitter_reference.mat')) && ...
            out.Events.FalseCRCEpisode==0 && out.Events.FalseContextAcceptanceEpisode==0, ...
            'test:H4InstalledPDCCHFalseAcceptance','Retain actual H0 false acceptance without tuning.');
        checkScoringContracts(out);
    end
    allEvents=[allEvents;out.Events]; %#ok<AGROW>
    sixgr.util.csvWriteTable(fullfile(folder,'receiver_episodes.csv'),allEvents,'PreserveSchema',true);
    clear out prepared
end
assert(isequal(hashes,arrayfun(@(f)string(sixgr.util.sha256File(f)),files)), ...
    'test:SourceChangedDuringExecution');
receipt=struct('Completed',true,'PhysicalEpisodes',height(allEvents), ...
    'Scope',string(p.scope),'ScenarioAccepted',false,'StatisticallyQualified',false, ...
    'SourceFiles',files,'SourceSHA256',hashes,'OutputFolder',string(folder));
sixgr.util.jsonWrite(fullfile(folder,'receipt.json'),receipt);
disp(allEvents);
fprintf('H4_INSTALLED_PDCCH_EPISODES_PASS folder=%s statistical_qualification=0\n',folder);
ok=true;
end

function rejectExecution(cfg,prepared,design,folder)
try
    sixgr.link.runIndependentPDCCHReceiverEpisode(cfg,prepared,design,folder);
catch err
    assert(strcmp(err.identifier,'sixgr:link:InvalidPDCCHReceiverEpisode'),err.getReport());
    assert(~isfolder(folder)); return;
end
error('test:InvalidPDCCHExecutionAccepted','Invalid boundary was accepted.');
end

function checkScoringContracts(out)
rx=out.Receiver; info=out.ReceiverInfo; e=out.Execution;
bad=info; bad.CandidateResults=info.CandidateResults([],:); rejectScore(rx,bad,e);
bad=info; bad.CandidateResults.DecodeAttempted(1)=false; rejectScore(rx,bad,e);
bad=info; bad.ExpectedDCIBits=int8([0;1]); rejectScore(rx,bad,e);
bad=e; bad.ReceiverCompleted=false; rejectScore(rx,info,bad);
bad=e; bad.ReceiverOracleUsed=true; rejectScore(rx,info,bad);
bad=info; bad.CandidateResults(2,:)=bad.CandidateResults(1,:); rejectScore(rx,bad,e);
bad=info; bad.CandidateResults.CRCOK=double(bad.CandidateResults.CRCOK);
bad.CandidateResults.CRCOK(1)=NaN; rejectScore(rx,bad,e);
% Explicit scoring-only fixture: a measured CRC pass that fails contextual
% parsing still counts as an H0 false CRC event. It is not a physical trial.
bad=info; bad.CandidateResults.CRCOK(1)=true; bad.CandidateResults.ErrFlag(1)=0;
bad.CRCValidHypothesisCount=1;
scored=sixgr.link.scoreIndependentPDCCHReceiverEpisode(rx,bad,int8([]),e);
assert(scored.FalseCRCEpisode==1 && scored.FalseContextAcceptanceEpisode==0 && ...
    scored.IndependentWaveformCount==1);
end

function rejectScore(rx,info,e)
try
    sixgr.link.scoreIndependentPDCCHReceiverEpisode(rx,info,int8([]),e);
catch err
    assert(strcmp(err.identifier,'sixgr:link:UnmeasuredPDCCHReceiverEpisode'),err.getReport()); return;
end
error('test:UnmeasuredPDCCHAccepted','Incomplete/invalid receive evidence was scored.');
end
