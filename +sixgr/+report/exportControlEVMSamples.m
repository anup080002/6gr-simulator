function [output,rewritten]=exportControlEVMSamples(trialPath,trials)
% Expand retained, independently paired samples from real completed trials.
% No detector-score conversion, nearest-symbol decisions or synthesized REs.
output="";
rewritten=false;
[folder,name]=fileparts(trialPath);
switch string(name)
    case "pbch_trials", file="ssb_evm_samples.csv"; allowed=["PBCH","PSS","SSS","PBCH-DMRS"]; direction="DL";
    case "prach_trials", file="prach_evm_samples.csv"; allowed="PRACH"; direction="UL";
    case "csi_rs_trials", file="csi_rs_evm_samples.csv"; allowed="CSI-RS"; direction="DL";
    otherwise, return;
end
if isempty(trials)||~ismember('ControlEVMSamplesJSON',trials.Properties.VariableNames), return; end
if ~sixgr.util.persistenceEnabled(), return; end
% A full-band TX sample table can be hundreds of MB. Repeated live polls
% must not reserialize it when neither evidence nor sink has changed. Cache
% digests only (not IQ/tables), and verify the actual file bytes on a hit.
% A modified/deleted destination or a new DB run must publish again.
persistent publications
if isempty(publications), publications=containers.Map('KeyType','char','ValueType','any'); end
target=string(java.io.File(fullfile(folder,file)).getCanonicalPath());
sourceHash=sixgr.util.sha256Hex(jsonencode(trials));
sink=sixgr.db.artifactStore('get_state');
sinkIdentity=struct('Active',sixgr.db.isArtifactStoreActive(), ...
    'RunID',sink.RunID,'RunUUID',sink.RunUUID,'RunFolder',sink.RunFolder);
sinkHash=sixgr.util.sha256Hex(sinkIdentity);
key=char(target);
if isKey(publications,key) && isfile(target)
    old=publications(key);
    if old.SourceHash==sourceHash && old.SinkHash==sinkHash && ...
            old.FileHash==sixgr.util.sha256File(target)
        output=target;
        return;
    end
end
parts={};
for k=1:height(trials)
    token=string(trials.ControlEVMSamplesJSON(k));
    if ismissing(token)||strlength(token)==0, continue; end
    records=jsondecode(token);
    assert(isstruct(records),'sixgr:report:ControlEVMPairSchema','Expected retained paired-sample records.');
    for e=reshape(records,1,[])
        assert(ismember(string(e.SignalName),allowed)&&~e.ReceiverUsesScoringReference && ...
            ~e.GainOrPhaseFitted && string(e.EVMDefinition)=="reference_normalized_paired_symbol_evm" && ...
            ~any(contains(lower(string(e.ReferenceSource)),["decision","same_sample"])), ...
            'sixgr:report:ControlEVMPairAuthority','Independent post-reception reference required.');
        numbers=[e.SampleIndex(:),e.ReferenceReal(:),e.ReferenceImag(:),e.MeasuredReal(:),e.MeasuredImag(:)];
        assert(size(numbers,2)==5 && ~isempty(numbers) && all(isfinite(numbers),'all') && ...
            all(numbers(:,1)>=0 & numbers(:,1)==fix(numbers(:,1))) && ...
            numel(unique(numbers(:,1)))==size(numbers,1) && sum(numbers(:,2).^2+numbers(:,3).^2)>0, ...
            'sixgr:report:ControlEVMPairSamples','Paired samples require unique RE/sequence identity and positive reference energy.');
        n=size(numbers,1);
        T=array2table(numbers,'VariableNames', ...
            {'SampleIndex','ReferenceReal','ReferenceImag','MeasuredReal','MeasuredImag'});
        for field=["SignalName","ObservationID","EVMDefinition","AlignmentSource", ...
                "ReferenceSource","MeasurementDomain","PortRole"]
            T.(field)=repmat(string(e.(field)),n,1);
        end
        T.PortIndex=repmat(double(e.PortIndex),n,1);
        T.ReceiverUsesScoringReference=false(n,1); T.GainOrPhaseFitted=false(n,1);
        for field=["SweepPointIndex","ConfiguredSNR_dB","SNR_dB","Direction","UEIndex", ...
                "CellID","ServingCell","Frame","Slot","RuntimeSlot","ObservationStartSample", ...
                "ObservationEndSampleExclusive","ObservationSampleRateHz"]
            if ismember(field,string(trials.Properties.VariableNames))
                T.(field)=repmat(trials.(field)(k,:),n,1);
            end
        end
        assert(ismember('Direction',T.Properties.VariableNames)&&all(string(T.Direction)==direction) && ...
            ismember('UEIndex',T.Properties.VariableNames) && all(isfinite(T.UEIndex)), ...
            'sixgr:report:ControlEVMPairTrialIdentity','Actual direction and UE are required.');
        T.SourceTrialRow=repmat(k,n,1);
        T.SourceTrialFile=repmat(string(name)+".csv",n,1);
        parts{end+1}=T; %#ok<AGROW>
    end
end
if isempty(parts), return; end
output=target;
% Do not cache a failed database mirror as a successful publication.
warningID='sixgr:util:csvWriteTable:ArtifactStoreMirrorFailed';
warningState=warning('query',warningID);
restoreWarning=onCleanup(@() warning(warningState)); %#ok<NASGU>
warning('error',warningID);
sixgr.util.csvWriteTable(output,vertcat(parts{:}),'PreserveSchema',true,'RoundTripNumericText',true);
publications(key)=struct('SourceHash',sourceHash,'SinkHash',sinkHash, ...
    'FileHash',sixgr.util.sha256File(output));
rewritten=true;
end
