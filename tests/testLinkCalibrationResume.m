function ok=testLinkCalibrationResume()
% Tiny real-waveform storage/resume regression, deliberately not qualified.
folder=fullfile(pwd,'logs',"link_calibration_resume_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); path=fullfile(folder,'contract_campaign.json');
p=sixgr.lls6g.config.readConfigFile('configs/calibration/nr_dl_ul_harq_baseline.yaml');
if iscell(p.cases), p.cases=vertcat(p.cases{:}); end
for k=1:numel(p.cases)
    p.cases(k).config=char(java.io.File(fullfile(pwd,'configs','calibration',p.cases(k).config)).getCanonicalPath());
end
p.research_class='optional_research_experiment'; p.campaign_id='physical_resume_contract_only';
p.reference_snr_axis_db=[30 35]; p.target_snr_axis_db=[25 30 35]; p.rv_sequence=0;
p.populations=struct('reference',1,'reference_validation',1,'fit',1,'validation',1); p.episodes_per_invocation=1;
sixgr.util.jsonWrite(path,p);
a=run_link_calibration(path,folder,'resume'); assert(a.EpisodesCommitted==1 && ~a.AllEpisodesComplete && a.EpisodesPlanned==20);
b=run_link_calibration(path,folder,'resume'); assert(b.EpisodesCommitted==2 && b.EpisodesThisInvocation==1);
files=dir(fullfile(b.RunFolder,'episodes','episode_*.mat')); assert(numel(files)==2);
first=load(fullfile(files(1).folder,files(1).name),'episode');
second=load(fullfile(files(2).folder,files(2).name),'episode');
assert(first.episode.Attempts(1).NoiseSeed~=second.episode.Attempts(1).NoiseSeed);
features=sixgr.calibration.readFeatureRows(b.RunFolder,first.episode.CaseID,"reference",1,"contract_only");
assert(height(features)==2 && features.NoiseSeed(1)==first.episode.Attempts(1).NoiseSeed);
assert(isequal(features.SINRHistory{1}{1},first.episode.Attempts(1).SINRLinear), ...
    'Streamed fitting features must preserve every actual per-RE value.');
assert(isempty(sixgr.calibration.readFeatureRows(b.RunFolder,"missing_case","reference",1,"contract_only")));
status=jsondecode(fileread(fullfile(b.RunFolder,'fitting_status.json')));
assert(string(status.Status)=="pending_fixed_population_collection" && ~status.PrimaryStudyAccepted);
audit=readtable(fullfile(b.RunFolder,'conditional_population_audit.csv'),'TextType','string');
assert(sum(audit.Role=="reference")==4 && sum(audit.Role=="reference_validation")==4 && ...
    sum(audit.Role=="fit")==6 && sum(audit.Role=="validation")==6, ...
    'Audit must preserve independent reference and target grid sizes.');
plan=readtable(fullfile(b.RunFolder,'conditional_population_plan.csv'),'TextType','string');
assert(~any(ismember(plan.PilotRole,["validation","reference_validation"])), ...
    'Population design cannot consume held-out validation outcomes.');
sources=readtable(fullfile(b.RunFolder,'sources.csv'),'TextType','string');
assert(any(endsWith(sources.Path,"core_parameter_catalog.yaml")), ...
    'Frozen source identity must include the defaults used by the PHY builder.');
% Check row-to-episode provenance using two independently seeded AWGN roles.
c=run_link_calibration(path,folder,'resume');
d=run_link_calibration(path,folder,'resume');
assert(c.EpisodesCommitted==3 && d.EpisodesCommitted==4);
frozen=load(fullfile(d.RunFolder,'campaign.mat'),'cases','p');
caseCfg=frozen.cases(1).Config; physical=caseCfg.pdsch;
sourceKey=struct('Direction',first.episode.Direction, ...
    'Modulation',string(physical.modulation),'MCSTable',string(physical.mcsTable), ...
    'MCSIndex',double(physical.mcsIndex),'TargetCodeRate',double(physical.targetCodeRate), ...
    'Rank',double(physical.numberLayers),'TBSBits',double(first.episode.Attempts(1).TBSBits), ...
    'SCS_kHz',double(caseCfg.carrier.subcarrierSpacingKHz), ...
    'ChannelProfile',string(frozen.p.target_channel.model), ...
    'TxPorts',double(caseCfg.channel.txAntennas),'RxPorts',double(caseCfg.channel.rxAntennas), ...
    'RFProfileID',"ideal_rf_no_impairments",'ReceiverType',"lmmse");
curveID="physical_source_contract_only";
fitRows=sixgr.calibration.exportReferenceTrialRows(d.RunFolder, ...
    first.episode.CaseID,"reference",1,curveID,sourceKey);
heldRows=sixgr.calibration.exportReferenceTrialRows(d.RunFolder, ...
    first.episode.CaseID,"reference_validation",1,curveID,sourceKey);
assert(height(fitRows)==2 && height(heldRows)==2 && ...
    ~any(fitRows.PriorAttemptsFailed) && ~any(heldRows.PriorAttemptsFailed));
fitFile=fullfile(d.RunFolder,'source_fit_contract.csv');
heldFile=fullfile(d.RunFolder,'source_validation_contract.csv');
writetable(fitRows,fitFile); writetable(heldRows,heldFile);
sourceNames=["source_fit_contract.csv";"source_validation_contract.csv"];
sourceSHA=[sixgr.csi.studyFileSHA256(fitFile);sixgr.csi.studyFileSHA256(heldFile)];
data=struct('SourceClassification',"executed_waveform_calibration", ...
    'Sources',table(["fit";"validation"],sourceNames,sourceSHA, ...
    repmat("production_waveform_decode",2,1), ...
    'VariableNames',{'Role','RelativePath','SHA256','ExecutionBackend'}), ...
    'Curves',struct('CurveID',curveID,'Key',sourceKey,'RVSequence',0, ...
    'SINRAxes_dB',{{[30;35]}}, ...
    'TrialCount',accumarray(fitRows.GridPointIndex,1,[2 1]), ...
    'ErrorCount',accumarray(fitRows.GridPointIndex,double(fitRows.CRCError),[2 1]), ...
    'ValidationTrialCount',accumarray(heldRows.GridPointIndex,1,[2 1]), ...
    'ValidationErrorCount',accumarray(heldRows.GridPointIndex,double(heldRows.CRCError),[2 1])));
proofPath=fullfile(d.RunFolder,'unqualified_source_contract.mat');
sixgr.system.abstraction.validateCalibrationSources(data,proofPath);
badRF=data; badRF.Curves.Key.RFProfileID="assumed_impaired_rf";
reject(@()sixgr.system.abstraction.validateCalibrationSources(badRF,proofPath), ...
    'sixgr:abstraction:CalibrationKey');
badEqualizer=data; badEqualizer.Curves.Key.ReceiverType="zf";
reject(@()sixgr.system.abstraction.validateCalibrationSources(badEqualizer,proofPath), ...
    'sixgr:abstraction:CalibrationKey');
poisoned=fitRows; poisoned.GridPointIndex(1)=3-poisoned.GridPointIndex(1);
writetable(poisoned,fitFile);
bad=data; bad.Sources.SHA256(1)=sixgr.csi.studyFileSHA256(fitFile);
reject(@()sixgr.system.abstraction.validateCalibrationSources(bad,proofPath), ...
    'sixgr:abstraction:CalibrationRawSchema');
% Changing a scientific field cannot append data to a frozen population.
p.seed_base=p.seed_base+1; sixgr.util.jsonWrite(path,p);
reject(@()run_link_calibration(path,folder,'resume'),'sixgr:calibration:ResumeIdentity');
corrupt=fullfile(folder,'corrupt_episode.mat'); copyfile(fullfile(files(1).folder,files(1).name),corrupt);
copyfile(string(fullfile(files(1).folder,files(1).name))+".sha256.json",string(corrupt)+".sha256.json");
invalid=1; save(corrupt,'invalid');
reject(@()sixgr.calibration.verifyEpisodeFile(corrupt),'sixgr:calibration:EpisodeDigest');
ok=true; fprintf('LINK_CALIBRATION_RESUME_PASS folder=%s qualification=0\n',folder);
end
function reject(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==id,'%s: %s',ME.identifier,ME.message); return; end
error('test:ExpectedFailure','Expected %s',id);
end
