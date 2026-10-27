function out=exportCompactCausalStageEvidence(runFolder,cfg,rawTrials)
% Reuse final strict reducers on actual completed rows before heavy reports.
% This publication is not a final run verdict or additional PHY execution.
layout=sixgr.report.resultLayout(runFolder);
dl=sixgr.util.structGet(rawTrials,'DL',table());
ul=sixgr.util.structGet(rawTrials,'UL',table());
controlPath=fullfile(layout.ControlCSVDir,'pdcch_trials.csv');
control=table();
if isfile(controlPath), control=sixgr.util.csvReadTable(controlPath,'TextType','string'); end
gate=sixgr.truth.buildPDCCHGrantBindingEvidence(control,cfg,dl,ul);
out=struct('PDCCHGrantBindingEvidencePath',string(fullfile(layout.ReportCSVDir,'pdcch_grant_binding_evidence.csv')), ...
    'PrecoderEvidencePath',string(fullfile(layout.BeamformingCSVDir,'precoder_evidence.csv')));
sixgr.util.csvWriteTable(out.PDCCHGrantBindingEvidencePath,gate.Rows,'PreserveSchema',true,'RoundTripNumericText',true);
sixgr.util.jsonWrite(fullfile(layout.ReportDir,'json','pdcch_grant_binding_evidence.json'),gate.Summary);
mimo=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,struct('DL',dl,'UL',ul), ...
    'RunId',string(sixgr.util.structGet(cfg,'run.runTag',"")), ...
    'ScenarioName',string(sixgr.util.structGet(cfg,'run.scenarioID',"")), ...
    'PublicationScope','precoder_only');
sixgr.util.csvWriteTable(out.PrecoderEvidencePath,mimo.PrecoderEvidence,'PreserveSchema',true,'RoundTripNumericText',true);
out.Binding=gate;
out.PrecoderEvidence=mimo.PrecoderEvidence;
end
