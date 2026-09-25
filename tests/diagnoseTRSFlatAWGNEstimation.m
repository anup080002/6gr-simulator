function results=diagnoseTRSFlatAWGNEstimation(capturePath,outputFolder)
% Retained shared-IQ comparison of the production opt-in AWGN estimator.
% Only practically acquired grids and known TRS pilots enter the fit.
% The independent applied-channel reference is used afterwards for scoring.
setup6GRSimToolkit('Verbose',false);
c=load(capturePath,'p','det','captures','replay');
p=c.p; det=c.det;
assert(~isempty(det.SlotDetections) && all([det.SlotDetections.Detected]), ...
    'test:TRSNotAcquired','Retain acquisition failures; do not use true timing.');
original=sixgr.phy.trs.estimateTRSChannel(struct(),p.StrictConfig,p.Tx,det);
assert(original.EstimateAvailable,'test:TRSNoOriginalEstimate');
fits=cell(numel(det.SlotDetections),1); estimates=fits;
for k=1:numel(fits)
    d=det.SlotDetections(k);
    grid=d.RxGrid; K=size(grid,1); L=size(grid,2); R=size(grid,3);
    ind=double(d.ReferenceIndices(:)); ref=d.ReferenceSymbols(:);
    received=reshape(grid,K*L,R);
    fit=sixgr.phy.rx.estimateFlatAWGNPilotChannel(received(ind,:),ref);
    estimates{k}=repmat(reshape(fit.GainPerReceiveBranch,1,1,R),K,L,1);
    fits{k}=fit;
end
% Neither the references nor replay/channel truth above entered estimation.
[references,evidence]=sixgr.truth.sharedTRSReferenceGrids(p,c.captures,c.replay,det);
assert(all(cellfun(@(e)contains(e.Source,'AWGN'),evidence)), ...
    'test:TRSFlatCandidateRequiresAWGN','This diagnostic cannot qualify a fading shortcut.');
original=sixgr.phy.trs.scoreTRSChannelEstimates(original,references,evidence);
candidateCfg=p.StrictConfig;
candidateCfg.RuntimeChannelEstimator='flat_static_awgn_ls';
% Older captures predate endpoint IDs in replay. Recover only endpoint
% identity from the retained capture, never coefficients or sample values.
receiverReplay=c.replay;
receiverReplay.ReceiverID=c.captures{1}.RX;
receiverReplay.TransmitterID=c.captures{1}.TX;
candidate=sixgr.phy.trs.estimateTRSChannel( ...
    struct('ReceivedExecutionEvidence',receiverReplay),candidateCfg,p.Tx,det);
assert(candidate.EstimateAvailable,'test:TRSProductionFitUnavailable');
for k=1:numel(estimates)
    assert(max(abs(candidate.ChannelEstimates{k}(:)-estimates{k}(:)))<1e-12, ...
        'test:TRSProductionFitMismatch','Production receiver must agree with independent pilot LS.');
end
candidate=sixgr.phy.trs.scoreTRSChannelEstimates(candidate,references,evidence);
rows=struct([]);
for k=1:numel(fits)
    fit=fits{k};
    row=struct('Slot',det.SlotDetections(k).Slot, ...
        'PilotRECount',fit.PilotCount,'ReceiveBranches',numel(fit.GainPerReceiveBranch), ...
        'OriginalNMSE_dB',original.Table.NMSE_dB(k), ...
        'CandidateNMSE_dB',candidate.Table.NMSE_dB(k), ...
        'OriginalNoiseVariance',original.Table.NoiseEstimate(k), ...
        'CandidateNoiseVariance',fit.NoiseVariance, ...
        'ScoringReferenceUsedByEstimator',false, ...
        'EstimatorInput',"practically_acquired_grid_and_known_TRS_pilots", ...
        'Scope',"production_receiver_replay_not_full_scenario_acceptance", ...
        'CapturePath',string(capturePath));
    rows=[rows;row]; %#ok<AGROW>
end
results=struct2table(rows);
assert(~isfile(fullfile(outputFolder,'trs_flat_candidate.csv')), ...
    'test:PreservePreviousTRSDiagnostic','Choose a new diagnostic output folder.');
if ~isfolder(outputFolder), mkdir(outputFolder); end
writetable(results,fullfile(outputFolder,'trs_flat_candidate.csv'));
save(fullfile(outputFolder,'trs_flat_candidate.mat'), ...
    'results','fits','original','candidate','evidence');
disp(results);
fprintf('TRS_FLAT_PRODUCTION_REPLAY_COMPLETE slots=%d full_scenario_verified=0 evidence=%s\n',height(results),outputFolder);
end
