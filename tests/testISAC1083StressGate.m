function ok=testISAC1083StressGate()
%TESTISAC1083STRESSGATE Reduced real-chain WFig29-WFig36 gate.
[cfg,~]=sixgr.isac.loadJointConfig( ...
    "configs/isac/joint_isac_tdoc_master.yaml");
cfg.validation.stress.screening.h0TrialsPerReceiver=2;
cfg.validation.stress.screening.targetTrialsPerPoint=1;
cfg.validation.stress.screening.pdschTransportBlocksPerPoint=1;
cfg.validation.stress.screening.pdschSNRDb=15;
cfg.validation.stress.intercellRelativePowerDb=-20;
cfg.validation.stress.selfInterferenceResidualDb=-60;
cfg.validation.stress.punctureRatesPercent=[0 20];
cfg.validation.stress.relocationResidualPhaseDeg=[0 20];
cfg.validation.stress.complexityRepetitions=3;
root=string(tempname); mkdir(root); cleanup=onCleanup(@()localRemove(root)); %#ok<NASGU>
path=fullfile(root,"stress_gate.json"); sixgr.util.jsonWrite(path,cfg);
result=sixgr.isac.run1083Stress(path,"OutputRoot",root,"RunId","stress_gate");
d=result.Data;
assert(all(d.PDSCHTrials.ReservedRE>0)&&all(isfinite(d.PDSCH.EVMRMS)));
assert(all(d.PDSCHTrials.ISACReferenceGridTransmitted));
assert(all(d.PDSCHTrials.ISACReferenceGridRE>0));
assert(all(d.PDSCHTrials.ISACReferenceGridRE==d.PDSCHTrials.ReservedRE));
assert(all(strlength(d.PDSCHTrials.ISACReferenceGridSHA256)==64));
assert(max(abs(d.PDSCHTrials.MeasuredSNRdB-d.PDSCHTrials.TargetSNRdB))<.1);
evmImpliedSINR=-20*log10(d.PDSCHTrials.EqualizedSymbolEVMRMS);
assert(max(abs(d.PDSCHTrials.PostEqSINRdB-evmImpliedSINR))<3);
assert(all(d.PDSCHTrials.TargetSNRDomain== ...
    "transmit_pdsch_data_re_es_to_receiver_grid_noise_pre_channel_gain"));
assert(all(d.PDSCHTrials.PostEqSINRDomain== ...
    "receiver_layer_symbol_after_channel_estimation_and_mmse_equalization"));
assert(all(d.PDSCHTrials.ExecutedCarrierProfile=="FR3_7GHz_100MHz_30kHz"));
assert(all(d.PDSCHTrials.ExecutedFrequencyHz==7e9));
assert(all(d.PDSCHTrials.ExecutedBandwidthHz==100e6));
assert(all(d.PDSCHTrials.SharedResourcePolicy== ...
    "sensing_restricted_to_pdsch_allocation"));
assert(all(strlength(d.PDSCHTrials.ConfigSHA256)==64));
assert(all(d.PDSCHTrials.ConfigSHA256~=d.PDSCHTrials.FullPHYAnchorConfigSHA256));
assert(all(ismember(["random_isolated","contiguous_time", ...
    "tdd_driven_missing_occasions"],unique(d.Puncture.PunctureProfile))));
assert(numel(unique(d.Puncture.ReceiverW3StateRule))==2);
assert(any(d.Relocation.RelocationClass=="R0_unknown"&d.Relocation.ReplacementObservations>0));
assert(any(d.Relocation.RelocationClass=="R1_exact"& ...
    d.Relocation.ReferenceCoherentGain>.999));
assert(all(ismember(["W1-A","W1-B"],d.Randomization.RandomizationProfile)));
assert(all(d.InterferenceCalibration.H0Trials==2));
assert(all(d.Intercell.EstimatorSampleCount<=d.Intercell.Trials));
assert(all(d.SelfInterference.EstimatorSampleCount<=d.SelfInterference.Trials));
assert(all(d.Intercell.EstimatorMetricCondition=="conditioned_on_correct_detection"));
for stem=sixgr.isac.validationFigureContract().FigureStem(13:20).'
    assert(exist(fullfile(result.RunFolder,"figures",stem+".png"),"file")==2);
end
fprintf("testISAC1083StressGate: PASS (%d PDSCH TB, %d puncture rows)\n", ...
    height(d.PDSCHTrials),height(d.Puncture));
ok=true;
end

function localRemove(path)
if exist(path,"dir")==7, rmdir(path,"s"); end
end
