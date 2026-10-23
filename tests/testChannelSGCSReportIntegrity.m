function ok=testChannelSGCSReportIntegrity()
% Numerical/export fixtures only; not physical performance qualification.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','validation','channel_sgcs_integrity', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
fprintf('CHANNEL_SGCS_REPORT_EVIDENCE=%s\n',root);
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
manifest=struct('CodeVersion',"test",'CodeDetail',"SGCS_numerical_export_fixture", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
before=rng;
h=[1;1i]; r=[1;-1i];
score=sixgr.phy.rx.squaredGeneralizedCosineSimilarity(h,r);
assert(score.Available && score.Value==0 && isequal(before,rng));
same=sixgr.phy.rx.squaredGeneralizedCosineSimilarity(3i*r,r);
assert(abs(same.Value-1)<1e-14 && ~same.GainOrPhaseFitted);
zero=sixgr.phy.rx.squaredGeneralizedCosineSimilarity(zeros(2,1),r);
assert(~zero.Available && isnan(zero.Value) && zero.EstimateEnergy==0);
reject(@()sixgr.phy.rx.squaredGeneralizedCosineSimilarity([1;NaN],r), ...
    'sixgr:phy:InvalidSGCSPairs');
reject(@()sixgr.phy.rx.squaredGeneralizedCosineSimilarity(h,r.'), ...
    'sixgr:phy:InvalidSGCSPairs');
% Three distinct observation/point identities, with deliberately identical
% condition number. A condition-number surrogate would return one for all.
dl=localTrial(root,"PDSCH",h,r,"sgcs_dl_point1",1,20);
dl=[dl;localTrial(root,"PDSCH",r,r,"sgcs_dl_point2",2,-10)];
ul=localTrial(root,"PUSCH",[1;0],r,"sgcs_ul_point1",1,20);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'),dl,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'ul_pusch_trials.csv'),ul,'PreserveSchema',true);
out=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
    manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
rows=out.CategoryRows(out.CategoryRows.MetricKey=="sgcs" & ...
    out.CategoryRows.Statistic=="paired_vector_similarity",:);
assert(height(rows)==3 && all(rows.CountsTowardCoverage), ...
    'test:SGCSNotMeasured','Report must publish three independently paired observations, not a condition-number score.');
joint=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'channel_sgcs_observations.csv'),'TextType','string');
assert(height(joint)==3 && numel(unique(joint.ChannelEstimateObservationID))==3);
assert(joint.ChannelSGCS(joint.ChannelEstimateObservationID=="sgcs_dl_point1")==0);
assert(abs(joint.ChannelSGCS(joint.ChannelEstimateObservationID=="sgcs_dl_point2")-1)<1e-14);
assert(abs(joint.ChannelSGCS(joint.ChannelEstimateObservationID=="sgcs_ul_point1")-.5)<1e-14);
assert(isequal(sort(joint.SweepPointIndex),[1;1;2]) && ...
    isequal(sort(joint.ConfiguredSNR_dB),[-10;20;20]));
% No data-derived metric can be rescued by a condition number alone.
missing=table(1,1,20,0,'VariableNames',{'Slot','UEIndex','ConfiguredSNR_dB','ConditionNumber_dB'});
assert(isempty(sixgr.report.collectChannelSGCSEvidence(root,missing,table())));
% Empty/missing old data is distinguishable from a declared corrupted source.
bad=dl(1,:); bad.ChannelEstimateResourcesCSVSHA256=string(repmat('0',1,64));
reject(@()sixgr.report.collectChannelSGCSEvidence(root,bad,table()), ...
    'sixgr:report:SGCSChecksum');
bad=dl(1,:); bad.ChannelEstimateObservationID="another_observation";
reject(@()sixgr.report.collectChannelSGCSEvidence(root,bad,table()), ...
    'sixgr:report:SGCSObservationIdentity');
bad=dl(1,:); bad.ChannelEstimateComparedValues=3;
reject(@()sixgr.report.collectChannelSGCSEvidence(root,bad,table()), ...
    'sixgr:report:SGCSPopulation');
bad=dl(1,:); bad.ChannelSGCS=.7;
reject(@()sixgr.report.collectChannelSGCSEvidence(root,bad,table()), ...
    'sixgr:report:SGCSOperandClosure');
bad=dl(1,:); bad.ChannelEstimateResourcesCSV="../another_run/channels.csv";
reject(@()sixgr.report.collectChannelSGCSEvidence(root,bad,table()), ...
    'sixgr:report:SGCSRunScope');
% Zero-vector estimates are actual observations, but SGCS is undefined.
z=localTrial(root,"PDSCH",zeros(2,1),r,"sgcs_zero",3,0);
zeroRows=sixgr.report.collectChannelSGCSEvidence(root,z,table());
assert(height(zeroRows)==1 && isnan(zeroRows.ChannelSGCS) && ...
    ~zeroRows.ChannelSGCSAvailable && zeroRows.ChannelSGCSStatus=="undefined_zero_vector_energy");
fprintf('CHANNEL_SGCS_REPORT_INTEGRITY_PASS measured_pairs=3 corruption_rejected=1 points_preserved=1\n');
ok=true;
end

function T=localTrial(root,channel,h,r,id,point,snr)
context=struct('Channel',channel,'Slot',41,'UEIndex',1, ...
    'ConfiguredSNR_dB',snr,'ChannelEstimateSource',"numerical_fixture_not_PHY_execution", ...
    'ChannelReferenceSource',"independent_numerical_fixture",'ChannelReferencePlane',"test_pilot_grid");
[resources,score]=sixgr.report.buildReceiverChannelEstimateTable(h,r,[1;2],context);
resources.ChannelEstimateObservationID=repmat(id,2,1);
relative=fullfile('channel_estimation','csv',id+'.csv');
sixgr.util.csvWriteTable(fullfile(root,relative),resources,'PreserveSchema',true,'RoundTripNumericText',true);
T=table(41,1,snr,point,17,0,id,string(relative), ...
    string(sixgr.util.sha256File(fullfile(root,relative))), ...
    "test_pilot_grid",2,"measured_and_independently_scored_after_reception", ...
    'VariableNames',{'Slot','UEIndex','ConfiguredSNR_dB','SweepPointIndex','Seed', ...
    'ConditionNumber_dB','ChannelEstimateObservationID','ChannelEstimateResourcesCSV', ...
    'ChannelEstimateResourcesCSVSHA256','ChannelEstimateReferencePlane', ...
    'ChannelEstimateComparedValues','ChannelEstimateCaptureStatus'});
for field=string(fieldnames(score)).'
    if startsWith(field,"ChannelSGCS"), T.(field)=score.(field); end
end
end

function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s',id,ex.identifier); return; end
error('test:SGCSExpectedRejection','Expected %s',id);
end
