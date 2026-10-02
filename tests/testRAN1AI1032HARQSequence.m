function ok=testRAN1AI1032HARQSequence(gridPRBs)
% Actual waveform checks; no statistical BLER qualification claim.
if nargin<1, gridPRBs=6; end
study=sixgr.studies.ran1ai1032.loadStudyConfig();
study.lls.execution.grid_prbs=gridPRBs;
study.lls.execution.rf_branch='ideal_debug';
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study);
C=plan.CasePlan;
C=C(C.ExperimentID=="F1" & C.ChannelProfile=="AWGN" & ...
    C.AntennaCaseID=="mimo_4x4_r1_r4" & C.EntryID=="B27" & C.Rank==1,:);
assert(height(C)==1);
seeds=[103241 103242 103243 103244];
bad=study; bad.harq.calibration.channel_evolution='correlated';
reject(@()sixgr.studies.ran1ai1032.executeF1HARQSequence(bad,C,[-20 -20 40 40],seeds), ...
    'sixgr:ran1ai1032:HARQCalibrationPolicy');
reject(@()sixgr.studies.ran1ai1032.executeF1HARQSequence(study,C,[-20 -20 40 40],[1 1 2 3]), ...
    'sixgr:ran1ai1032:HARQCalibrationHistory');
out=sixgr.studies.ran1ai1032.executeF1HARQSequence(study,C,[-20 -20 40 40],seeds);
T=out.TrialTable;
assert(height(T)>=3 && ~T.CRCPass(1) && ~T.CRCPass(2));
assert(all(T.PriorAttemptsFailed) && all(T.WaveformExecuted));
assert(all(T.HARQSoftCombiningApplied(2:end)) && all(T.HARQSoftCombiningPositionAware(2:end)));
assert(numel(unique(T.TransportBlockSHA256))==1 && all(T.TBSize_bits==T.TBSize_bits(1)));
rv=[0 2 3 1]; assert(isequal(T.RV.',rv(1:height(T))));
assert(out.Delivered && out.UniqueDeliveredBits==T.TBSize_bits(1));
first=sixgr.studies.ran1ai1032.executeF1HARQSequence(study,C,[40 -20 -20 -20],seeds);
assert(first.AttemptsExecuted==1 && first.Delivered);
assert(~first.TrialTable.HARQSoftCombiningApplied && ~first.PrimaryStudyAccepted);
ok=true;
fprintf('F1_HARQ_SEQUENCE_PASS PRBs=%d waveform_attempts=%d statistical_qualification=0\n',gridPRBs,height(T)+1);
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'%s: %s',ME.identifier,ME.message); return; end
error('test:ExpectedError','Expected %s.',id);
end
