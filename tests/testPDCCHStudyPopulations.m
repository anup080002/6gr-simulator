function ok = testPDCCHStudyPopulations()
% Executed H0/H1 grid observations, not statistical detector qualification.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','pdcch_6gr_study.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.ctrl6gr.NoiseOnlyTrialsPerPoint == 1);
cfg.ctrl6gr.StudyAggregationLevels = 4;
cfg.ctrl6gr.StudySNRdB = [0 25];
cfg.ctrl6gr.SignalPresentTrialsPerPoint = 2;
cfg.ctrl6gr.NoiseOnlyTrialsPerPoint = 3;
out = sixgr.ctrl.runPDCCHStudyLLS(cfg,'WriteOutputs',false);
t = out.PDCCHTrials;
h0 = ~t.SignalPresent; h1 = t.SignalPresent;
assert(sum(h0)==6 && sum(h1)==4);
assert(all(t.TXGridEnergy(h0)==0) && all(t.RXGridEnergy(h0)>0));
assert(all(t.TXGridEnergy(h1)>0));
assert(all(t.UsedCCECount(h0)==0) && all(t.UsedCCECount(h1)==4));
assert(all(t.FalseAlarmFlag(h0)==t.DCICrcPass(h0)));
assert(all(~t.MissedDetectionFlag(h0)));
assert(all(~t.PDCCHPayloadMatch(h0)));
assert(all(t.Status(h0 & ~t.FalseAlarmFlag)=="PASS"));
assert(all(isnan(t.NMSEChannelEst)));
assert(all(isfinite(t.PilotReconstructionResidualRatio(h1))));
assert(all(isnan(t.PostEqEVM(h0))));
assert(all(isfinite(t.ComputeLatency_ms) & t.ComputeLatency_ms>=0));
assert(all(t.StatisticalQualification=="not_evaluated_population_only"));
summary = out.SummaryByScenario;
assert(all(summary.SignalPresentTrialCount==2 & summary.NoiseOnlyTrialCount==3));
assert(all(summary.ConfidenceLevel==0.95));
assert(all(summary.FalseAlarmCILower<=summary.FalseAlarmProbability & ...
    summary.FalseAlarmCIUpper>=summary.FalseAlarmProbability));
assert(all(summary.FalseAlarmCIUpper>0),'Zero observed events cannot imply zero uncertainty.');
for index=1:height(summary)
    selected = t.SNRdB==summary.SNRdB(index);
    assert(summary.FalseAlarmProbability(index)==mean(t.FalseAlarmFlag(selected & h0)));
    assert(summary.MissProbability(index)==mean(t.MissedDetectionFlag(selected & h1)));
end
% Adding H0 observations must not alter H1 realizations or contaminate BLER.
cfg.ctrl6gr.NoiseOnlyTrialsPerPoint = 0;
reference = sixgr.ctrl.runPDCCHStudyLLS(cfg,'WriteOutputs',false);
assert(all(isnan(reference.SummaryByScenario.FalseAlarmProbability)));
assert(all(isnan(reference.SummaryByScenario.FalseAlarmCIUpper)));
assert(isequaln(summary.DCIErrorRate,reference.SummaryByScenario.DCIErrorRate));
fields = {'SNRdB','RandomSubstream','RXGridEnergy','TXGridEnergy', ...
    'DCICrcPass','PDCCHPayloadMatch','EstimatedSINR_dB','PostEqEVM'};
assert(isequaln(t(h1,fields),reference.PDCCHTrials(:,fields)));
localDecoderIndependence(cfg);
cfg.ctrl6gr.SignalPresentTrialsPerPoint = 0;
try
    sixgr.ctrl.ControlChannelConfig(cfg);
    error('test:MissingPopulationGuard','Empty populations must be rejected.');
catch exception
    assert(string(exception.identifier)=="sixgr:ctrl:ControlChannelConfig:EmptyPopulations");
end
fprintf('PDCCH_STUDY_POPULATIONS_PASS: 4 H1 and 6 H0 observations; no qualification claim.\n');
ok = true;
end

function localDecoderIndependence(cfg)
ctrl = sixgr.ctrl.ControlChannelConfig(cfg);
payload = sixgr.ctrl.ControlPayloadBuilder(ctrl,'Seed',321);
crc = sixgr.ctrl.CRCAttachAndScramble(payload.InformationBits,ctrl);
K = numel(crc.BitsWithCRC); E = 432;
mother = nrPolarEncode(crc.BitsWithCRC,E,9,false);
bits = nrRateMatchPolar(mother,K,E,false);
context = struct('SlotNumber',1,'SearchSpaceID',2);
scrambled = sixgr.ctrl.PayloadScrambler(bits,ctrl,context);
modulated = sixgr.ctrl.PDCCHModulator(scrambled.Bits,ctrl);
poison = struct('KWithCRC',1,'PolarEncodedLength',32,'RateMatchedLength',1,'ListLength',1);
a = sixgr.ctrl.PDCCHDecoder(modulated.Symbols,0.001,struct(),ctrl,context);
b = sixgr.ctrl.PDCCHDecoder(modulated.Symbols,0.001,poison,ctrl,context);
assert(a.CRCPass && b.CRCPass && isequal(a.DecodedBits,payload.InformationBits));
assert(isequal(a.DecodedBits,b.DecodedBits) && isequal(a.LLR,b.LLR));
assert(a.ReceiveHypothesis.KWithCRC==K && a.ReceiveHypothesis.RateMatchedLength==E);
end
