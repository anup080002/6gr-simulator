function ok=testPBCHAccessEpisodeAccounting()
% Declared reporting fixtures, not an RF qualification population.
setup6GRSimToolkit('Verbose',false);
root=string(tempname); mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
T=table(repmat("run",8,1),repmat("execution",8,1), ...
    ones(8,1),ones(8,1),repelem([1;21],4),repmat(20,8,1), ...
    repmat((0:3)',2,1),repmat([1;0;0;0],2,1),zeros(8,1), ...
    repmat([1;0;0;0],2,1),ones(8,1),repmat(4,8,1), ...
    repmat("configured_active_ss_burst_set",8,1), ...
    repmat("coupled_receiver_measured_single_received_ssb_pbch_burst",8,1), ...
    'VariableNames',{'RunID','ExecutionID','UEIndex','ServingCell','Slot', ...
    'SNR_dB','SSBIndex','SelectedBeamFlag','SelectedSSBIndex','SIB1StrictOk', ...
    'SSBBurstSweepCoverageComplete','SSBBurstSweepExpectedCandidateCount', ...
    'SSBBurstSweepScope','SelectionSource'});
sixgr.analytics.generateMeasuredSINRCurves(root,'episode_accounting', ...
    'TrialData',struct('dl',table(),'ul',table(),'pbch',T), ...
    'ScenarioConfig',struct(),'WriteKPISummary',true,'UpdateAnchorKPIs',true);
A=readtable(fullfile(root,'air_interface','csv','link_anchor_kpis.csv'));
a=A(strcmpi(string(A.Case),'CellSearch_MIB_SIB1'),:);
assert(a.TrialCount==2 && a.PassCount==2 && a.FailCount==0 && a.Ok, ...
    'sixgr:test:PBCHCandidatePopulationUsedAsAccess', ...
    'Two selected access episodes must not become eight required candidate decodes.');
P=readtable(fullfile(root,'reports','csv','pbch_access_episode_reconciliation.csv'));
assert(sum(P.CandidateTrialCount)==8 && sum(P.CandidateStrictFailureCount)==6, ...
    'Nonselected physical candidate failures must remain visible.');
unknown=T; unknown.SIB1StrictOk(1)=NaN;
sixgr.analytics.generateMeasuredSINRCurves(root,'unknown_selected_result', ...
    'TrialData',struct('dl',table(),'ul',table(),'pbch',unknown), ...
    'ScenarioConfig',struct(),'WriteKPISummary',true,'UpdateAnchorKPIs',true);
A=readtable(fullfile(root,'air_interface','csv','link_anchor_kpis.csv'));
a=A(strcmpi(string(A.Case),'CellSearch_MIB_SIB1'),:);
assert(a.PassCount==1 && a.FailCount==1 && ~a.Ok, ...
    'An unknown selected SIB1 result must not become true through logical(NaN).');
% A good unselected candidate cannot rescue the failed selected candidate.
T.SIB1StrictOk(1)=0; T.SIB1StrictOk(2)=1;
[P,mask]=sixgr.analytics.summarizePBCHAccessEpisodes(T,T.SIB1StrictOk==1);
assert(~P.AccessSuccess(1) && P.AccessSuccess(2) && nnz(mask)==2);
% Unknown result, duplicate/no selection, wrong selected identity, missing
% candidate and incomplete coverage must not become a successful episode.
for k=1:7
    bad=T; bad.SIB1StrictOk(1)=1;
    switch k
        case 1, bad.SIB1StrictOk(1)=NaN;
        case 2, bad.SelectedBeamFlag(2)=1;
        case 3, bad.SelectedBeamFlag(1)=0;
        case 4, bad.SelectedSSBIndex(1:4)=2;
        case 5, bad(4,:)=[];
        case 6, bad.SSBBurstSweepCoverageComplete(1:4)=0;
        case 7, bad.SelectionSource(1)="";
    end
    P=sixgr.analytics.summarizePBCHAccessEpisodes(bad,bad.SIB1StrictOk==1);
    assert(~P.AccessSuccess(1) && P.AccessSuccess(2), ...
        'sixgr:test:PBCHAccessFailOpen','Invalid selected episode passed case %d.',k);
end
% Same slot in two UEs must remain independent, as must two SNR points.
both=[T;T]; both.UEIndex(9:16)=2;
P=sixgr.analytics.summarizePBCHAccessEpisodes(both,both.SIB1StrictOk==1);
assert(height(P)==4 && nnz(P.AccessSuccess)==2);
both.UEIndex(:)=1; both.SNR_dB(9:16)=30;
P=sixgr.analytics.summarizePBCHAccessEpisodes(both,both.SIB1StrictOk==1);
assert(height(P)==4 && nnz(P.AccessSuccess)==2);
ok=true;
end
