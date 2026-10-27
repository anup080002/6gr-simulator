function T = buildPrecoderEvidence(rankT)
rows = repmat(struct("RunId","", "TrialId",NaN, "Direction","", "PrecoderId","", ...
    "PMI","", "AppliedPrecoderMatrixSHA256","", "EvidenceType","", ...
    "PrecoderSource","", "PrecodingActive",false, "SourceRowsHash","", ...
    "Status","", "FailureReason",""), height(rankT), 1);
for i = 1:height(rankT)
    rows(i).RunId = string(rankT.RunId(i));
    rows(i).TrialId = double(rankT.TrialId(i));
    rows(i).Direction = string(rankT.Direction(i));
    pmi = strtrim(string(rankT.PrecoderId(i)));
    matrixHash = lower(strtrim(string(rankT.AppliedPrecoderMatrixSHA256(i))));
    pmiAvailable = localUsableText(pmi);
    matrixAvailable = ~ismissing(matrixHash) && ...
        ~isempty(regexp(char(matrixHash), '^[0-9a-f]{64}$', 'once')); %#ok<RGXP1>
    rows(i).PMI = string(localTernary(pmiAvailable, pmi, ""));
    rows(i).AppliedPrecoderMatrixSHA256 = ...
        string(localTernary(matrixAvailable, matrixHash, ""));
    if matrixAvailable
        rows(i).PrecoderId = "matrix_sha256:" + matrixHash;
        rows(i).EvidenceType = string(localTernary(pmiAvailable, ...
            "pmi_and_applied_matrix", "applied_matrix"));
        rows(i).PrecoderSource = ...
            "air_interface_trial_applied_precoder_matrix_sha256";
    elseif pmiAvailable
        rows(i).PrecoderId = "pmi:" + pmi;
        rows(i).EvidenceType = "pmi";
        rows(i).PrecoderSource = "air_interface_trial_applied_pmi";
    else
        rows(i).PrecoderId = "";
        rows(i).EvidenceType = "missing";
        rows(i).PrecoderSource = "air_interface_trial_precoder_fields";
    end
    rows(i).PrecodingActive = pmiAvailable || matrixAvailable;
    rows(i).SourceRowsHash = string(rankT.SourceRowsHash(i));
    rows(i).Status = string(localTernary(rows(i).PrecodingActive || double(rankT.ConfiguredLayers(i)) <= 1, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(rows(i).Status == "pass", "", "multi_layer_precoder_evidence_missing"));
end
T = struct2table(rows);
end


function tf = localUsableText(s)
s = lower(strtrim(string(s)));
tf = ~ismissing(s) && strlength(s) > 0 && ...
    ~ismember(s, ["nan","<missing>","missing","none","unavailable","not_available"]) && ...
    ~startsWith(s, ["not_recorded_by_active_","not_emitted_by_active_", ...
        "field_not_emitted_by_active_"]);
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
