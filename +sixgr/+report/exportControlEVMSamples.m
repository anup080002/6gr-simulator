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
    case "trs_trials", file="trs_evm_samples.csv"; allowed="TRS"; direction="DL";
    otherwise, return;
end
if isempty(trials)||~any(ismember(["ControlEVMSamplesJSON","ControlEVMSamplesMATFile"], ...
        string(trials.Properties.VariableNames))), return; end
if ~sixgr.util.persistenceEnabled(), return; end
for k=1:height(trials)
    sixgr.report.readControlEVMPairs(trials(k,:),trialPath,true);
end
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
% Retain one trial's numeric pairs, not every trial expanded into repeated
% metadata strings. Publish one complete CSV, with bounded serialization.
writer=sixgr.util.CSVTableStream(target,true);
cleanup=onCleanup(@()delete(writer)); %#ok<NASGU>
for k=1:height(trials)
    records=sixgr.report.readControlEVMPairs(trials(k,:),trialPath);
    if isempty(records), continue; end
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
        for first=1:writer.ChunkRows:size(numbers,1)
        selected=first:min(size(numbers,1),first+writer.ChunkRows-1);
        n=numel(selected);
        T=array2table(numbers(selected,:),'VariableNames', ...
            {'SampleIndex','ReferenceReal','ReferenceImag','MeasuredReal','MeasuredImag'});
        for field=["SignalName","ObservationID","EVMDefinition","AlignmentSource", ...
                "ReferenceSource","MeasurementDomain","PortRole"]
            T.(field)=repmat(string(e.(field)),n,1);
        end
        T.PortIndex=repmat(double(e.PortIndex),n,1);
        if isfield(e,'ReferencePlane')
            T.ReferencePlane=repmat(string(e.ReferencePlane),n,1);
        end
        T.ReceiverUsesScoringReference=false(n,1); T.GainOrPhaseFitted=false(n,1);
        % A pre/post-TX pair retains PA backoff and every other configured
        % gain. It is not a gain-normalized standards modulation-EVM test.
        T.StandardizedModulationEVMQualified=false(n,1);
        if string(e.MeasurementDomain)=="transmitter_resource_elements"
            T.MeasurementClaim=repmat("raw_gain_inclusive_TX_pair_error_not_standardized_modulation_EVM",n,1);
            T.AmplitudeReferenceTreatment=repmat("pre_TX_RF_amplitude_no_PA_backoff_or_gain_removal",n,1);
        elseif string(e.MeasurementDomain)=="received_resource_elements"
            assert(string(e.SignalName)=="TRS" && ...
                string(e.ReferenceSource)=="same_executed_desired_link_received_pilot_grid", ...
                'sixgr:report:ControlEVMPairAuthority','Received-grid TRS EVM needs its independent same-execution reference.');
            T.MeasurementClaim=repmat("received_pilot_grid_pair_error_not_equalized_or_RF_conformance",n,1);
            T.AmplitudeReferenceTreatment=repmat("same_execution_desired_pilot_grid_no_gain_phase_fit",n,1);
        else
            T.MeasurementClaim=repmat("receiver_paired_symbol_error_not_RF_conformance",n,1);
            T.AmplitudeReferenceTreatment=repmat("retained_reference_and_receiver_equalization",n,1);
        end
        for field=["SweepPointIndex","ConfiguredSNR_dB","SNR_dB","Direction","UEIndex", ...
                "CellID","ServingCell","Frame","Slot","RuntimeSlot","ObservationStartSample", ...
                "ObservationEndSampleExclusive","ObservationSampleRateHz"]
            if ismember(field,string(trials.Properties.VariableNames))
                T.(field)=repmat(trials.(field)(k,:),n,1);
            end
        end
        T=localBindPairedClock(T,e,n);
        assert(ismember('Direction',T.Properties.VariableNames)&&all(string(T.Direction)==direction) && ...
            ismember('UEIndex',T.Properties.VariableNames) && all(isfinite(T.UEIndex)), ...
            'sixgr:report:ControlEVMPairTrialIdentity','Actual direction and UE are required.');
        T.SourceTrialRow=repmat(k,n,1);
        T.SourceTrialFile=repmat(string(name)+".csv",n,1);
        writer.append(T);
        end
    end
end
if writer.RowsWritten==0, return; end
output=target;
% Do not cache a failed database mirror as a successful publication.
warningID='sixgr:util:csvWriteTable:ArtifactStoreMirrorFailed';
warningState=warning('query',warningID);
restoreWarning=onCleanup(@() warning(warningState)); %#ok<NASGU>
warning('error',warningID);
writer.finish();
publications(key)=struct('SourceHash',sourceHash,'SinkHash',sinkHash, ...
    'FileHash',sixgr.util.sha256File(output));
rewritten=true;
end

function T=localBindPairedClock(T,e,n)
% Keep the parent receiver observation distinct from a TX measurement.
% Old retained pairs without a clock cannot acquire one from the RX trial.
fields=["ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"];
for field=fields
    if ~ismember(field,string(T.Properties.VariableNames)), T.(field)=nan(n,1); end
    T.("SourceTrial"+field)=T.(field);
end
T.TransmitStartSample=nan(n,1);
T.MeasurementClockDomain=repmat("source_trial_receiver_observation_clock",n,1);
if string(e.MeasurementDomain)~="transmitter_resource_elements", return; end
required=[fields,"TransmitStartSample","MeasurementClockDomain"];
present=isfield(e,cellstr(required));
if ~any(present)
    for field=fields, T.(field)=nan(n,1); end
    T.MeasurementClockDomain(:)="unavailable_legacy_TX_capture_clock_not_retained";
    return;
end
assert(all(present),'sixgr:report:ControlEVMPairClock', ...
    'A declared paired TX clock must be complete, not replaced by its RX parent.');
for field=[fields,"TransmitStartSample"]
    value=e.(field);
    assert(isnumeric(value) && isscalar(value) && isfinite(value), ...
        'sixgr:report:ControlEVMPairClock','Paired TX clock values must be finite scalars.');
    T.(field)=repmat(double(value),n,1);
end
samples=double([e.ObservationStartSample,e.ObservationEndSampleExclusive,e.TransmitStartSample]);
assert(all(samples>=0 & samples==fix(samples)) && samples(2)>samples(1) && ...
    e.ObservationSampleRateHz>0 && isscalar(string(e.MeasurementClockDomain)) && ...
    string(e.MeasurementClockDomain)=="physical_absolute_sample_clock_zero_based", ...
    'sixgr:report:ControlEVMPairClock','Invalid retained TX capture clock.');
T.MeasurementClockDomain(:)=string(e.MeasurementClockDomain);
end
