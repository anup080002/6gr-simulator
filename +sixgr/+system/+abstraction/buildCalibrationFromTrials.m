function receipt=buildCalibrationFromTrials(spec,policy,outputFile)
%BUILDCALIBRATIONFROMTRIALS Package retained independent waveform populations.
% No default curve, fitted beta, CRC, trial count or missing grid is invented.
% spec.Curves supplies physically keyed, externally fitted mappings and axes.
% spec.Sources names retained raw CSV files relative to outputFile.
arguments
    spec (1,1) struct
    policy (1,1) struct
    outputFile (1,1) string
end
assert(~isfile(outputFile),'sixgr:abstraction:CalibrationOutputExists','Do not overwrite a frozen calibration.');
assert(isfield(spec,'SourceClassification') && ...
    string(spec.SourceClassification)=="executed_waveform_calibration" && ...
    all(isfield(spec,{'CalibrationID','Curves','Sources'})) && ...
    istable(spec.Sources) && ~isempty(spec.Curves), ...
    'sixgr:abstraction:CalibrationSchema','Require a waveform specification, fitted curve templates and retained fit/validation sources.');
calibration=spec; calibration.Schema="sixgr.calibrated_sls_link/v1";
allRows=table();
for k=1:height(spec.Sources)
    src=spec.Sources(k,:);
    path=fullfile(fileparts(outputFile),src.RelativePath);
    assert(isfile(path) && strcmpi(sixgr.csi.studyFileSHA256(path),src.SHA256), ...
        'sixgr:abstraction:CalibrationDigest','Missing or changed retained source.');
    raw=readtable(path,'TextType','string','VariableNamingRule','preserve');
    required=["CurveID","GridPointIndex","TrialID","AttemptIndex","CRCError", ...
        "PriorAttemptsFailed","WaveformExecuted","CalibrationKeySHA256"];
    assert(all(ismember(required,string(raw.Properties.VariableNames))), ...
        'sixgr:abstraction:CalibrationRawSchema','Missing actual waveform population columns.');
    raw=raw(:,required); raw.Role=repmat(string(src.Role),height(raw),1);
    allRows=[allRows;raw]; %#ok<AGROW>
end
for k=1:numel(spec.Curves)
    c=spec.Curves(k);
    assert(all(isfield(c,{'CurveID','Key','RVSequence','SINRAxes_dB','BetaLinear'})), ...
        'sixgr:abstraction:CalibrationSchema','Curve template is incomplete.');
    shape=cellfun(@numel,c.SINRAxes_dB);
    if isscalar(shape), shape=[shape 1]; end
    for role=["fit","validation"]
        r=allRows(string(allRows.CurveID)==string(c.CurveID) & allRows.Role==role,:);
        index=double(r.GridPointIndex);
        assert(~isempty(index) && all(isfinite(index)) && all(index==fix(index)) && ...
            all(index>=1 & index<=prod(shape)) && all(ismember(double(r.CRCError),[0 1])), ...
            'sixgr:abstraction:CalibrationPopulation','Every curve needs finite retained conditional populations.');
        n=reshape(accumarray(index,1,[prod(shape) 1]),shape);
        e=reshape(accumarray(index,double(r.CRCError),[prod(shape) 1]),shape);
        prefix=""; if role=="validation", prefix="Validation"; end
        c.(prefix+"TrialCount")=n; c.(prefix+"ErrorCount")=e;
    end
    sixgr.system.abstraction.validateBLERCurve(c,policy);
    for f=string(fieldnames(c)).', calibration.Curves(k).(f)=c.(f); end
end
% Reconcile every raw row/hash/count before writing any accepted package.
sixgr.system.abstraction.validateCalibrationSources(calibration,outputFile);
identities=arrayfun(@(c) string(jsonencode(c.Key))+"|"+string(jsonencode(c.RVSequence)),calibration.Curves);
assert(numel(unique(identities))==numel(identities), ...
    'sixgr:abstraction:DuplicateCalibration','Duplicate physical-key/RV curve ownership.');
save(outputFile,'calibration','-v7.3');
receipt=struct('CalibrationFile',outputFile,'SHA256',sixgr.csi.studyFileSHA256(outputFile), ...
    'CurveCount',numel(calibration.Curves),'RawTrialRows',height(allRows), ...
    'SourceClassification',"executed_waveform_calibration", ...
    'StatisticalPolicyPassed',true,'PrimaryStudyAccepted',false);
end
