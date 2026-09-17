function path=calibrateAWGNAdaptation(configPath)
% Actual independent RV0 TBs; no synthetic BLER curve or universal thresholds.
c=sixgr.lls6g.config.loadScenarioConfig(configPath); s=c.toStruct(); p=s.research_adaptation;
path=string(p.calibration_file);
assert(~isfile(path),'sixgr:research:CalibrationAlreadyExists','Preserve existing calibration; choose a new calibration_file.');
assert(string(s.research_link.channel)=="identity_awgn" && ...
    string(s.research_receiver.channel_estimation)=="perfect_identity_awgn", ...
    'sixgr:research:CalibrationScope','This calibration supports perfect identity-AWGN CSI only.');
folder=fileparts(path); if ~isfolder(folder), mkdir(folder); end
sixgr.util.jsonWrite(fullfile(folder,'resolved_config.json'),s);
metaFolder=fullfile(folder,'meta'); mkdir(metaFolder);
mkdir(fullfile(metaFolder,'input_configs')); mkdir(fullfile(metaFolder,'executed_sources'));
sixgr.lls6g.config.writeYAML(fullfile(metaFolder,'resolved_config.yaml'),s);
sixgr.util.jsonWrite(fullfile(metaFolder,'schema_validation_report.json'),struct('Passed',true));
sixgr.util.jsonWrite(fullfile(metaFolder,'environment_summary.json'), ...
    struct('MATLAB',version,'Computer',computer,'Toolboxes',ver));
sixgr.util.jsonWrite(fullfile(metaFolder,'seeds.json'),struct('Seed',s.simulation.random_seed,'Generator',"twister"));
for k=1:numel(c.SourceFiles)
    [~,name,ext]=fileparts(c.SourceFiles(k));
    copyfile(c.SourceFiles(k),fullfile(metaFolder,'input_configs',sprintf('%03d_%s%s',k,name,ext)));
end
sources=[string(mfilename('fullpath'))+".m", ...
    string(which('sixgr.phy.research.SharedChannelLink')), ...
    string(which('sixgr.phy.research.AWGNLinkAdaptation'))];
sourceEvidence=struct([]);
for k=1:numel(sources)
    [~,name,ext]=fileparts(sources(k));
    copyfile(sources(k),fullfile(metaFolder,'executed_sources',name+ext));
    sourceEvidence(k).Path=sources(k); %#ok<AGROW>
    sourceEvidence(k).SHA256=sixgr.util.sha256File(sources(k)); %#ok<AGROW>
end
sixgr.util.jsonWrite(fullfile(metaFolder,'executed_source_hashes.json'),sourceEvidence);
[~,commit]=system('git rev-parse HEAD'); [~,dirty]=system('git status --porcelain');
codecHash=sixgr.util.sha256File(which('sixgr.phy.research.SharedChannelLink'));
sixgr.util.jsonWrite(fullfile(folder,'provenance.json'),struct('CodecSHA256',codecHash, ...
    'CalibrationDriverSHA256',sixgr.util.sha256File(mfilename('fullpath')+".m"), ...
    'MATLAB',version,'Seed',s.simulation.random_seed,'Source',"actual_coded_research_calibration", ...
    'GitCommit',strtrim(string(commit)),'GitDirty',strlength(strtrim(string(dirty)))>0, ...
    'ExecutionScope',"independent_initial_RV0_attempts_no_HARQ_feedback", ...
    'ThresholdRole',"implementation_calibration_not_universal_3gpp_requirement"));
progress=struct('Status',"running",'TrialsCompleted',0, ...
    'ExpectedTrials',2*numel(p.candidate_layers)*numel(p.calibration_snr_db)*p.calibration_trials_per_point, ...
    'IntegratedAdaptationQualified',false,'ThroughputQualified',false);
sixgr.util.jsonWrite(fullfile(metaFolder,'manifest.json'),progress);
try
state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister'); rows=struct([]);
frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
for d=["DL","UL"]
    section="research_"+lower(d); slot=[];
    for k=0:s.simulation.n_slots-1
        if d=="DL", eligible=frame.IsDLAllocation(k,s.(section).symbol_allocation);
        else, eligible=frame.IsULAllocation(k,s.(section).symbol_allocation); end
        if eligible, slot=k; break; end
    end
    assert(~isempty(slot),'sixgr:research:CalibrationDirectionMissing','Data horizon must contain both directions.');
    for candidate=1:numel(p.candidate_layers)
        sc=sixgr.phy.research.AWGNLinkAdaptation.candidate(s,d,candidate);
        sc.(section).harq_enabled=false; sc.(section).rv=0;
        hash=sixgr.phy.research.AWGNLinkAdaptation.profileHash(sc,d);
        a=sixgr.phy.research.SharedChannelLink.allocation(sc,slot,d);
        for snr=reshape(p.calibration_snr_db,1,[])
            for trial=1:p.calibration_trials_per_point
                trialClock=tic;
                tb=int8(randi([0 1],a.TransportBlockSize,1));
                tx=sixgr.phy.research.SharedChannelLink.transmit(sc,slot,tb,d);
                nvGrid=s.research_awgn_mimo.reference_data_re_power/10^(snr/10);
                nvSample=nvGrid/tx.OFDM.SampleToGridNoiseVarianceGain;
                wave=tx.Waveform+sqrt(nvSample/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
                rx=sixgr.phy.research.SharedChannelLink.receive(sc,slot,wave,d);
                exact=isequal(rx.TransportBlock,tb);
                assert(~rx.CRCPass || exact,'sixgr:research:UndetectedPayloadError','CRC pass must imply exact payload for calibration.');
                row=struct('TrialIndex',numel(rows)+1,'Direction',d,'Candidate',candidate, ...
                    'ProfileHash',hash,'CodecSHA256',codecHash,'ReferenceSNRdB',snr, ...
                    'MeasuredLayerSINRdB',10*log10(1/(a.NumLayers*rx.NoiseVariance)), ...
                    'MeasuredNoiseVariance',rx.NoiseVariance,'InjectedGridNoiseVariance',nvGrid, ...
                    'TBSBits',numel(tb),'NumLayers',a.NumLayers,'Modulation',a.Modulation, ...
                    'CRCPass',logical(rx.CRCPass),'TBExact',exact, ...
                    'ExecutionSeconds',toc(trialClock), ...
                    'Source',"actual_coded_research_calibration");
                if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
                sixgr.util.csvWriteTable(path,struct2table(rows));
                fprintf('ADAPTATION_CALIBRATION %s candidate=%d reference=%g trial=%d/%d CRC=%d exact=%d seconds=%.3f\n', ...
                    d,candidate,snr,trial,p.calibration_trials_per_point,rx.CRCPass,exact,row.ExecutionSeconds);
                clear tx rx wave
            end
            progress.TrialsCompleted=numel(rows);
            sixgr.util.jsonWrite(fullfile(metaFolder,'manifest.json'),progress);
        end
    end
end
progress.Status="completed"; progress.TrialsCompleted=numel(rows);
sixgr.util.jsonWrite(fullfile(metaFolder,'manifest.json'),progress);
fprintf('ADAPTATION_CALIBRATION_COMPLETE rows=%d path=%s\n',numel(rows),path);
catch cause
    progress.Status="failed"; progress.ErrorIdentifier=string(cause.identifier);
    progress.ErrorMessage=string(cause.message);
    if exist('rows','var'), progress.TrialsCompleted=numel(rows); end
    sixgr.util.jsonWrite(fullfile(metaFolder,'manifest.json'),progress);
    rethrow(cause);
end
end
