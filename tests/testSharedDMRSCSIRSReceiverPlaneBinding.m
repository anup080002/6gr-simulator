function [ok,checks,pairs]=testSharedDMRSCSIRSReceiverPlaneBinding(runRoot,applicationFolder,outputRoot)
% Retained ACTUAL v1 pair replay and value-copy negatives. No new PHY, RF,
% receiver, gain compensation or reconstructed owner. Supply the original
% run and its completed application folder; never rewrite the archive.
% v2 producer execution remains a separate live-owner physical regression.
assert(nargin>=2 && isfolder(runRoot) && isfolder(applicationFolder), ...
    'test:PairedReceiverPlanesSourceRequired','Supply an original run and completed application folder.');
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
receiverMAT=fullfile(applicationFolder,'received_csi_later_pdsch_receiver.mat');
applicationMAT=fullfile(applicationFolder,'received_csi_later_application.mat');
assert(isfile(receiverMAT) && isfile(applicationMAT), ...
    'test:PairedReceiverPlanesSourceRequired','Retain both original application and receiver MAT files.');
receiver=load(receiverMAT,'trial'); application=load(applicationMAT,'completedEvidence');
assert(isfield(receiver,'trial') && istable(receiver.trial) && height(receiver.trial)==1 && ...
    isfield(application,'completedEvidence'),'test:PairedReceiverPlanesSourceRequired', ...
    'Load the actual finalized trial and original value-only completed evidence.');
trial=receiver.trial; evidence=application.completedEvidence;
assert(all(ismember({'DMRSCSIRSComparisonAvailable','DMRSCSIRSComparisonMATFile', ...
    'DMRSCSIRSComparisonCSV'},trial.Properties.VariableNames)) && trial.DMRSCSIRSComparisonAvailable, ...
    'test:PairedReceiverPlanesSourceRequired','Require an actually published same-capture comparison.');
matPath=fullfile(runRoot,string(trial.DMRSCSIRSComparisonMATFile));
csvPath=fullfile(runRoot,string(trial.DMRSCSIRSComparisonCSV));
sourcePaths=[string(receiverMAT);string(applicationMAT);string(matPath);string(csvPath)];
sourceHashes=arrayfun(@(p)string(sixgr.phy.waveform.WaveformHash.file(p)),sourcePaths);
archive=load(matPath);
assert(archive.Contract=="same_execution_paired_DMRS_CSI_RS_archive/v1", ...
    'test:PairedReceiverPlanesSourceRequired','This regression is the unchanged historical-v1 bridge.');
selected=arrayfun(@(c)isfield(c.Score,'Available') && c.Score.Available,archive.Comparisons);
assert(any(selected) && string(evidence.PostRFSampleSHA256)~=string(evidence.ReceiverInput.ReceiverObservationSHA256), ...
    'test:PairedReceiverPlanesSourceRequired','Use original distinct post-RF/decoder planes, not an identity/no-AGC surrogate.');
if nargin<3 || strlength(string(outputRoot))==0, outputRoot=tempname(fullfile(pwd,'logs')); end
assert(~isfolder(outputRoot) && ~isfile(outputRoot),'test:PairedReceiverPlanesOutputExists','Use a new diagnostic folder.');
mkdir(outputRoot);
rows=repmat(struct('Check',"",'Passed',false,'ObservedErrorID',"",'Detail',"",'Stack',""),0,1);
pairs=table();
runCase("original_completed_projection",@projectOriginal,"");
runCase("original_pair_exact_arithmetic_and_two_planes",@collectOriginal,"");
runCase("declared_equal_hash_legacy_without_capsule",@equalHashCompatibility,"");
runCase("declared_equal_hash_wrong_window", ...
    @()equalHashCompatibility("ReceiverWindowID","another_window"),"sixgr:report:PairedChannelOperandClosure");
runCase("declared_equal_hash_wrong_tx_identity", ...
    @()equalHashCompatibility("DataTransmissionIdentity.TransmissionID","another_tx"), ...
    "sixgr:report:PairedChannelReceiverPlaneBinding");

id="sixgr:report:PairedChannelReceiverPlaneBinding";
changed=removevars(trial,{'CompletedCSIApplicationEvidenceJSON','CompletedCSIApplicationEvidenceSHA256'});
runCase("missing_original_capsule",@()collect(changed),id);
changed=trial; changed.CompletedCSIApplicationEvidenceJSON="";
runCase("empty_original_capsule",@()collect(changed),id);
changed=trial; changed.CompletedCSIApplicationEvidenceSHA256=repmat('0',1,64);
runCase("forged_capsule_checksum",@()collect(changed),id);

% Mutations below deliberately recompute the capsule checksum. Rejection
% must therefore come from the original receiver/archive identity binding,
% not merely from an inconsistent JSON checksum. Original files stay intact.
probe("window","ReceiverWindowID","another_window");
probe("receiver_endpoint","ReceiverID","another_receiver");
probe("transmitter_endpoint","TransmitterID","another_transmitter");
probe("raw_sample_hash","PostRFSampleSHA256",repmat('0',1,64));
probe("transmitter_sample_hash","TXSampleSHA256",repmat('0',1,64));
probe("receiver_sample_hash","ReceiverInput.ReceiverObservationSHA256",repmat('0',1,64));
probe("receiver_hash_plane","ReceiverInput.ReceiverObservationHashPlane","post_rf_not_decoder_input");
probe("receiver_hash_serialization","ReceiverInput.ReceiverObservationHashSerialization","another_serialization");
probe("receiver_start","ReceiverInput.ObservationStartSample",evidence.ReceiverInput.ObservationStartSample+1);
probe("receiver_end","ReceiverInput.ObservationEndSampleExclusive",evidence.ReceiverInput.ObservationEndSampleExclusive+1);
probe("receiver_sample_rate","ReceiverInput.ObservationSampleRateHz",evidence.ReceiverInput.ObservationSampleRateHz+1);
probe("receiver_completion","ReceiverInput.ObservationCompletionTime_s",evidence.ReceiverInput.ObservationCompletionTime_s+1);
probe("receiver_coverage","ReceiverInput.ObservationCoverageSource","planned_not_received");
probe("receiver_runtime_use","ReceiverInput.RuntimeStageWaveformsUsed",false);
probe("physical_epoch","ReceiverClockEpoch",evidence.ReceiverClockEpoch+1);
probe("receiver_clock_domain","ReceiverClockDomain","another_clock");
probe("future_completion","CompletedAtSample",evidence.ReceiverInput.ObservationEndSampleExclusive-1);
probe("future_control","ReceivedControl.AvailableAtSample",evidence.ReceiverInput.ObservationEndSampleExclusive+1);
probe("transmission_id","TransmissionIdentity.TransmissionID",repmat('0',1,64));
probe("physical_grant_id","TransmissionIdentity.PHYGrantContextId","another_grant");
probe("transmission_direction","TransmissionIdentity.Direction","UL");
probe("transmission_start","TransmissionIdentity.StartSample",evidence.TransmissionIdentity.StartSample+1);
probe("transmission_end","TransmissionIdentity.EndSampleExclusive",evidence.TransmissionIdentity.EndSampleExclusive+1);
probe("transmission_sample_rate","TransmissionIdentity.SampleRateHz",evidence.TransmissionIdentity.SampleRateHz+1);
probe("transmission_ue","TransmissionIdentity.UEIndex",evidence.TransmissionIdentity.UEIndex+1);
probe("transmission_rnti","TransmissionIdentity.RNTI",evidence.TransmissionIdentity.RNTI+1);
probe("preparation_population","PreparedSourcePopulationSHA256",repmat('0',1,64));
probe("not_completed","WaveformApplicationVerified",false);
probe("extra_phy_claim","AdditionalPHYExecutions",1);

changed=trial; changed.DMRSCSIRSComparisonCSVSHA256=repmat('0',1,64);
runCase("corrupt_resource_csv_checksum",@()collect(changed),"sixgr:report:PairedChannelArchiveChecksum");
changed=trial; changed.ReceiverObservationSHA256="another_decoder_capture";
runCase("relabeled_final_receiver_row",@()collect(changed),"sixgr:report:PairedChannelSourceIdentity");
changed=trial; changed.ObservationStartSample=changed.ObservationStartSample+1;
runCase("relabeled_final_receiver_bounds",@()collect(changed),"sixgr:report:PairedChannelSourceIdentity");

assert(isequaln(receiver.trial,trial) && isequaln(application.completedEvidence,evidence) && ...
    isequal(sourceHashes,arrayfun(@(p)string(sixgr.phy.waveform.WaveformHash.file(p)),sourcePaths)), ...
    'test:PairedReceiverPlanesOriginalChanged','No original source or evidence may be modified.');
checks=struct2table(rows);
scope=struct('SourcePaths',sourcePaths,'SourceSHA256',sourceHashes, ...
    'OriginalCompletedEvidenceSHA256',string(evidence.EvidenceSHA256), ...
    'OriginalComparedValues',sum(arrayfun(@(c)c.Score.ComparedValues,archive.Comparisons(selected))), ...
    'AdditionalPHYExecutions',0,'OriginalOwnerReexecuted',false,'V2ProducerExecuted',false, ...
    'EqualHashCompatibilityScope',"declared_value_only_fixture_not_actual_equal_hash_reception", ...
    'FullScenarioQualified',false);
save(fullfile(outputRoot,'paired_receiver_plane_checks.mat'),'checks','pairs','scope');
sixgr.util.csvWriteTable(fullfile(outputRoot,'paired_receiver_plane_checks.csv'),checks,'PreserveSchema',true);
fprintf('SHARED_PAIR_PLANES checks=%d passed=%d original_values=%d additional_PHY=0 output=%s\n', ...
    height(checks),nnz(checks.Passed),scope.OriginalComparedValues,string(outputRoot));
assert(all(checks.Passed),'test:PairedReceiverPlanesFailed','Failed boundary checks: %s', ...
    strjoin(checks.Check(~checks.Passed),', '));
ok=true;

    function projectOriginal()
        bound=sixgr.truth.bindCompletedCSIApplicationEvidence(trial,evidence);
        assert(isequaln(bound(:,trial.Properties.VariableNames),trial), ...
            'test:PairedReceiverPlanesProjection','Original completed-application projection must remain exact.');
    end
    function collectOriginal()
        pairs=collect(trial);
        assert(height(pairs)==nnz(selected),'test:PairedReceiverPlanesPopulation','Do not lose or duplicate original available resources.');
        original=archive.Comparisons(selected);
        for q=1:numel(original)
            c=original(q); hit=find(pairs.CSIRSResourceID==c.ResourceID);
            assert(isscalar(hit) && pairs.ComparedValues(hit)==c.Score.ComparedValues && ...
                isequaln(pairs.DMRSNMSELinear(hit),c.Score.DMRSNMSELinear) && ...
                isequaln(pairs.CSIRSNMSELinear(hit),c.Score.CSIRSNMSELinear) && ...
                isequaln(pairs.DeltaNMSE_dB(hit),c.Score.DeltaNMSE_dB) && ...
                pairs.PostRFSampleSHA256(hit)==string(evidence.PostRFSampleSHA256) && ...
                pairs.ReceiverObservationSHA256(hit)==string(evidence.ReceiverInput.ReceiverObservationSHA256) && ...
                pairs.ReceiverPlaneBindingSHA256(hit)==string(evidence.EvidenceSHA256) && ...
                pairs.ReceiverPlaneBindingSource(hit)=="historical_v1_original_completed_application_capsule", ...
                'test:PairedReceiverPlanesExactReplay','Retain every original value and separately named plane.');
        end
    end
    function out=collect(value)
        out=sixgr.report.collectSharedDMRSCSIRSPairs(runRoot,value);
    end
    function equalHashCompatibility(varargin)
        % A separately labelled scratch schema fixture, NOT an actual
        % equal-hash reception and never a rewrite of the original archive.
        % Original arithmetic operands are retained; only the declared
        % raw-plane hash is made equal to the already archived input hash.
        fixture=archive;
        fixture.TestFixtureScope="declared_equal_plane_hash_compatibility_only_not_physical_evidence";
        for q=1:numel(fixture.Comparisons)
            if isempty(fieldnames(fixture.Comparisons(q).Operands)), continue; end
            fixture.Comparisons(q).Evidence.ReceiverObservationSHA256=fixture.Identity.ReceiverObservationSHA256;
            if ~isempty(varargin)
                fixture.Comparisons(q).Evidence=setValue(fixture.Comparisons(q).Evidence, ...
                    split(string(varargin{1}),'.'),varargin{2});
            end
        end
        folder=tempname(outputRoot); mkdir(folder);
        targetMAT=fullfile(folder,string(trial.DMRSCSIRSComparisonMATFile));
        targetCSV=fullfile(folder,string(trial.DMRSCSIRSComparisonCSV));
        mkdir(fileparts(targetMAT)); mkdir(fileparts(targetCSV));
        copyfile(csvPath,targetCSV); save(targetMAT,'-struct','fixture');
        fixtureRow=removevars(trial,{'CompletedCSIApplicationEvidenceJSON','CompletedCSIApplicationEvidenceSHA256'});
        fixtureRow.DMRSCSIRSComparisonMATFileSHA256=string(sixgr.phy.waveform.WaveformHash.file(targetMAT));
        result=sixgr.report.collectSharedDMRSCSIRSPairs(folder,fixtureRow);
        assert(height(result)==nnz(selected) && all(result.ReceiverPlaneBindingSHA256=="") && ...
            all(result.ReceiverPlaneBindingSource=="historical_v1_identical_canonical_sample_bytes_not_AGC_state"), ...
            'test:PairedReceiverPlanesEqualCompatibility','Preserve exact-byte compatibility without inferring the AGC state.');
    end
    function probe(name,path,value)
        changed=trial; payload=jsondecode(char(trial.CompletedCSIApplicationEvidenceJSON));
        payload=setValue(payload,split(path,'.'),value);
        token=string(jsonencode(payload));
        changed.CompletedCSIApplicationEvidenceJSON=token;
        changed.CompletedCSIApplicationEvidenceSHA256=string(sixgr.phy.waveform.WaveformHash.bytes(token));
        runCase("forged_"+name,@()collect(changed),id);
    end
    function runCase(name,action,expectedID)
        record=struct('Check',name,'Passed',false,'ObservedErrorID',"",'Detail',"",'Stack',"");
        try
            action(); record.Passed=strlength(expectedID)==0;
            if ~record.Passed, record.ObservedErrorID="test:PairedReceiverPlanesMissingRejection"; end
        catch failure
            record.ObservedErrorID=string(failure.identifier); record.Detail=string(failure.message);
            record.Stack=string(getReport(failure,'extended','hyperlinks','off'));
            record.Passed=strlength(expectedID)>0 && record.ObservedErrorID==expectedID;
        end
        rows(end+1,1)=record;
        fprintf('PAIRED_PLANE_CHECK name=%s pass=%d observed=%s\n',name,record.Passed,record.ObservedErrorID);
    end
end

function input=setValue(input,path,value)
name=char(path(1));
if numel(path)==1, input.(name)=value;
else, input.(name)=setValue(input.(name),path(2:end),value);
end
end
