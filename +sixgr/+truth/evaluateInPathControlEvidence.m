function out = evaluateInPathControlEvidence(cfg, rawTrials, varargin)
%EVALUATEINPATHCONTROLEVIDENCE Evaluate current-run control-bearing rows only.

p = inputParser;
p.addParameter("EnablePDCCH", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("EnablePUCCH", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("EnablePUSCHUCI", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});

rows = repmat(struct("SignalFamily","", "StrictOk",false, ...
    "TrialRows",0, "FailureReason",""), 0, 1);
pdcch = struct();
pucch = struct();
puschUCI = struct();
if logical(p.Results.EnablePDCCH)
    pdcch = sixgr.truth.evaluateInPathComponentEvidence(cfg, rawTrials, "pdcch");
    rows(end+1,1) = localRow("PDCCH", pdcch); %#ok<AGROW>
end
if logical(p.Results.EnablePUCCH)
    pucch = sixgr.truth.evaluateInPathComponentEvidence(cfg, rawTrials, "pucch");
    rows(end+1,1) = localRow("PUCCH", pucch); %#ok<AGROW>
end
if logical(p.Results.EnablePUSCHUCI)
    puschUCI = sixgr.truth.evaluateInPathComponentEvidence(cfg, rawTrials, "pusch_uci");
    rows(end+1,1) = localRow("PUSCH_UCI", puschUCI); %#ok<AGROW>
end
summary = struct2table(rows, "AsArray", true);
ok = ~isempty(summary) && all(logical(summary.StrictOk));
failure = "";
if ~ok && ~isempty(summary)
    bad = summary(~logical(summary.StrictOk),:);
    failure = strjoin(string(bad.SignalFamily) + ":" + ...
        string(bad.FailureReason), "; ");
end
out = struct("Ok",logical(ok), "StrictOk",logical(ok), ...
    "PDCCH",pdcch, "PUCCH",pucch, "PUSCH_UCI",puschUCI, "SummaryTable",summary, ...
    "FailureReason",string(failure), "EvidenceScope","in_path", ...
    "RuntimeEvidenceSource","CoupledTruthRuntime.RawTrials", ...
    "LaunchedSupplementalWaveform",false);
end

function row = localRow(name, result)
artifactName = lower(char(name)) + "_trials";
row = struct("SignalFamily",string(name), ...
    "StrictOk",logical(result.StrictOk), ...
    "TrialRows",height(result.ArtifactTables.(artifactName)), ...
    "FailureReason",string(result.FailureReason));
end
