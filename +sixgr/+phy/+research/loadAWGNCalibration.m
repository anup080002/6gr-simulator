function library=loadAWGNCalibration(s,direction)
% Reconcile immutable actual-PHY datasets by executed profile, not row index.
% Confidence gates apply separately to each dataset/point: never pool files.
direction=upper(string(direction)); p=s.research_adaptation;
files=string(p.calibration_file);
if isfield(p,'calibration_files'), files=[files;string(p.calibration_files(:))]; end
files=files(:); count=numel(p.candidate_layers);
library=struct('ThresholdDb',Inf(1,count),'SourceFiles',files, ...
    'SourceSHA256',strings(numel(files),1),'SHA256',"",'Evidence',struct([]));
profiles=strings(1,count); matched=false(1,count);
for k=1:count
    sc=sixgr.phy.research.AWGNLinkAdaptation.candidate(s,direction,k);
    profiles(k)=sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(sc,direction);
end
codecHash=sixgr.util.sha256File(which('sixgr.phy.research.SharedChannelLink'));
required=["TrialIndex","Direction","Candidate","ProfileHash","CodecSHA256", ...
    "ReferenceSNRdB","MeasuredLayerSINRdB","CRCPass","TBExact","Source"];
for f=1:numel(files)
    file=files(f); folder=fileparts(file);
    assert(isfile(file),'sixgr:research:MissingAdaptationCalibration', ...
        'Generate actual coded calibration first: %s.',file);
    hash=sixgr.util.sha256File(file);
    assert(~any(library.SourceSHA256==hash),'sixgr:research:DuplicateCalibrationEvidence', ...
        'The same calibration content cannot be supplied more than once.');
    library.SourceSHA256(f)=hash;
    provenanceFile=fullfile(folder,'provenance.json');
    configFile=fullfile(folder,'resolved_config.json');
    assert(isfile(provenanceFile) && isfile(configFile), ...
        'sixgr:research:MissingCalibrationProvenance','Calibration environment and executed input are required.');
    provenance=jsondecode(fileread(provenanceFile));
    assert(isfield(provenance,'MATLAB') && string(provenance.MATLAB)==string(version), ...
        'sixgr:research:CalibrationEnvironmentMismatch','Regenerate calibration on this MATLAB version.');
    saved=jsondecode(fileread(configFile));
    manifestFile=fullfile(folder,'meta','manifest.json');
    if isfile(manifestFile)
        manifest=jsondecode(fileread(manifestFile));
        assert(string(manifest.Status)=="completed", ...
            'sixgr:research:IncompleteCalibration','Do not consume a running, failed or interrupted calibration.');
    end
    T=readtable(file,'TextType','string');
    assert(all(ismember(required,string(T.Properties.VariableNames))), ...
        'sixgr:research:InvalidAdaptationCalibration','Calibration columns are incomplete.');
    assert(height(T)>0 && numel(unique(T.TrialIndex))==height(T) && ...
        all(isfinite(T.TrialIndex) & T.TrialIndex>=1 & T.TrialIndex==fix(T.TrialIndex)) && ...
        all(ismember(T.Direction,["DL","UL"])) && ...
        all(isfinite(T.Candidate) & T.Candidate>=1 & T.Candidate==fix(T.Candidate)) && ...
        all(T.Candidate<=numel(saved.research_adaptation.candidate_layers)) && ...
        all(T.Source=="actual_coded_research_calibration") && all(T.CodecSHA256==codecHash) && ...
        all(ismember(T.CRCPass,[0 1])) && all(ismember(T.TBExact,[0 1])) && ...
        all(T.TBExact(logical(T.CRCPass))) && ...
        all(isfinite(T.ReferenceSNRdB)) && all(isfinite(T.MeasuredLayerSINRdB)), ...
        'sixgr:research:InvalidAdaptationCalibration','Calibration needs finite current-code CRC and exact-payload evidence.');
    % Validate all original rows, including modes not in the current menu.
    for d=["DL","UL"]
        for original=reshape(unique(T.Candidate(T.Direction==d)),1,[])
            rows=T.Direction==d & T.Candidate==original;
            sc=sixgr.phy.research.AWGNLinkAdaptation.candidate(saved,d,original);
            assert(all(T.ProfileHash(rows)==sixgr.phy.research.AWGNLinkAdaptation.profileHash(sc,d)), ...
                'sixgr:research:CalibrationProfileMismatch','Rows do not match their saved executed candidate.');
            if d~=direction, continue; end
            compatible=find(profiles==sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(sc,d));
            matched(compatible)=true;
            for k=reshape(compatible,1,[])
                for point=reshape(unique(T.ReferenceSNRdB(rows)),1,[])
                    at=rows & T.ReferenceSNRdB==point;
                    n=sum(at); errors=sum(~logical(T.CRCPass(at)));
                    if errors==n, bound=1; else, bound=betaincinv(p.calibration_confidence,errors+1,n-errors); end
                    eligible=n>=p.calibration_trials_per_point && bound<=p.target_bler;
                    measured=10*log10(mean(10.^(T.MeasuredLayerSINRdB(at)/10)));
                    if eligible, library.ThresholdDb(k)=min(library.ThresholdDb(k),measured); end
                    row=struct('Direction',direction,'Candidate',k,'OriginalCandidate',original, ...
                        'SourceFile',file,'SourceSHA256',hash,'ReferenceSNRdB',point, ...
                        'Trials',n,'CRCFailures',errors,'BLERUpperBound',bound, ...
                        'Confidence',p.calibration_confidence,'Eligible',eligible, ...
                        'MeasuredLayerSINRdB',measured,'Source',"pointwise_calibration_gate_not_integrated_BLER");
                    if isempty(library.Evidence), library.Evidence=row; else, library.Evidence(end+1)=row; end
                end
            end
        end
    end
end
assert(all(matched),'sixgr:research:CalibrationProfileMismatch', ...
    'Every requested candidate needs evidence for its actual physical profile. Missing candidate indices: %s.', ...
    mat2str(find(~matched)));
assert(any(isfinite(library.ThresholdDb)),'sixgr:research:UnqualifiedAdaptationCandidates', ...
    'No candidate meets the configured pointwise binomial upper-bound gate.');
assert(isfinite(library.ThresholdDb(p.bootstrap_candidate)), ...
    'sixgr:research:UnqualifiedBootstrap','The bootstrap candidate needs coded calibration support.');
if numel(files)==1
    library.SHA256=library.SourceSHA256(1);
else
    library.SHA256=sixgr.phy.rsla.RSLAUtil.hash(struct('CalibrationSHA256',library.SourceSHA256));
end
end
