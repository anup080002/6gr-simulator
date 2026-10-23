function ok=testSharedScoringWaveformArtifact()
% Artifact-contract fixtures only: no PHY performance or study result rows.
% The integration test uses actual TRS samples; this bounded test isolates
% byte/content validation and both supported MAT serialization formats.
setup6GRSimToolkit('Verbose',false);
root=string(tempname); mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s'));
for format=["-v7","-v7.3"]
    folder=fullfile(root,erase(format,'-')); mkdir(folder);
    waveform=complex(reshape((1:256)/257,64,4),reshape((256:-1:1)/259,64,4));
    [manifest,row,evidence,matPath,csvPath]=writeFixture(folder,waveform,format);
    hashes=pairHashes(matPath,csvPath);
    verified=sixgr.truth.validateSharedScoringWaveformArtifact( ...
        folder,manifest,row,evidence,waveform);
    assert(verified.ExpectedValuesCompared && ...
        verified.WaveformSHA256==manifest.WaveformSHA256 && ...
        verified.MATFileSHA256==hashes(1) && verified.SegmentsCSVSHA256==hashes(2) && ...
        isequal(hashes,pairHashes(matPath,csvPath)) && ...
        verified.ArrayReadEvidence.FullArrayLoaded==(format=="-v7"));
    original=load(matPath);
    for kind=["sample","shape","class","manifest","evidence","CSV", ...
            "missingMAT","missingCSV"]
        % Restore only this test-owned fixture between independent cases.
        save(matPath,'-struct','original',char(format));
        writetable(row,csvPath);
        damaged=original;
        switch kind
            case "sample"
                damaged.DesiredLinkWaveform(1)=damaged.DesiredLinkWaveform(1)+1;
            case "shape"
                damaged.DesiredLinkWaveform=damaged.DesiredLinkWaveform.';
            case "class"
                damaged.DesiredLinkWaveform=single(damaged.DesiredLinkWaveform);
            case "manifest"
                wrong=manifest; wrong.SampleRateHz=wrong.SampleRateHz+1;
                damaged.ManifestJSON=string(jsonencode(wrong));
            case "evidence"
                damaged.Evidence.LinkID="not_the_executed_link";
            case "CSV"
                wrongRow=row; wrongRow.ReceiveBranchCount=3;
                writetable(wrongRow,csvPath);
            case "missingMAT"
                delete(matPath);
            case "missingCSV"
                delete(csvPath);
        end
        if any(kind==["sample","shape","class","manifest","evidence"])
            save(matPath,'-struct','damaged',char(format));
        end
        before=pairHashes(matPath,csvPath);
        expectFailure(@()sixgr.truth.validateSharedScoringWaveformArtifact( ...
            folder,manifest,row,evidence,waveform));
        assert(isequal(before,pairHashes(matPath,csvPath)), ...
            'Validation must not rewrite corruption or complete an interrupted publication.');
    end
    save(matPath,'-struct','original',char(format));
    writetable(row,csvPath);
    changedExpected=waveform; changedExpected(end)=changedExpected(end)+1;
    expectFailure(@()sixgr.truth.validateSharedScoringWaveformArtifact( ...
        folder,manifest,row,evidence,changedExpected));
    proxy=manifest; proxy.Source="synthetic";
    expectFailure(@()sixgr.truth.validateSharedScoringWaveformArtifact( ...
        folder,proxy,row,evidence,waveform));
    foreign=row; foreign.WaveformMATFile="../outside.mat";
    expectFailure(@()sixgr.truth.validateSharedScoringWaveformArtifact( ...
        folder,manifest,foreign,evidence,waveform));
end
% Exceed one hash-read block to exercise exact column-major traversal, not
% a full-array read disguised as a streaming validation.
folder=fullfile(root,'multiblock'); mkdir(folder);
values=reshape(1:(2049*513),2049,513);
waveform=complex(single(values/1048576),single(-values/2097152));
[manifest,row,evidence]=writeFixture(folder,waveform,"-v7.3");
verified=sixgr.truth.validateSharedScoringWaveformArtifact( ...
    folder,manifest,row,evidence,waveform);
read=verified.ArrayReadEvidence;
assert(~read.FullArrayLoaded && read.BlocksRead>2 && ...
    read.MaxBlockElements<=read.ReadBudgetElements && ...
    read.ElementCount==numel(waveform) && read.Class=="single");
fprintf('SHARED_SCORING_ARTIFACT_PASS formats=2 negative_cases=22 multiblock=1 not_PHY_qualification=1\n');
ok=true;
end

function [manifest,row,evidence,matPath,csvPath]=writeFixture(root,waveform,format)
first=123; stop=first+size(waveform,1); rate=122880000;
evidence=struct('Source',"actual_executed_link_contribution", ...
    'Scope',"effective_pilot_response_includes_actual_tx_rf_not_isolated_pure_channel_matrix", ...
    'LinkID',"declared_unit_fixture_link",'TransmitterID',"test_tx",'ReceiverID',"test_rx", ...
    'StartSample',first,'EndSampleExclusive',stop,'ReceiverEstimatorInput',false, ...
    'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0, ...
    'TestFixtureRole',"artifact_contract_only_no_PHY_execution_or_performance_claim");
waveformHash=sixgr.phy.waveform.WaveformHash.runtimeArray(waveform);
manifest=struct('Contract',"actual_shared_effective_link_waveform/v1", ...
    'Representation',"complete_sample_indexed_desired_link_IQ_not_path_gain_tensor", ...
    'Source',evidence.Source,'Scope',evidence.Scope,'LinkID',evidence.LinkID, ...
    'TransmitterID',evidence.TransmitterID,'ReceiverID',evidence.ReceiverID, ...
    'SampleRateHz',rate,'StartSample',first,'EndSampleExclusive',stop, ...
    'WaveformSHA256',waveformHash,'ReceiverEstimatorInput',false, ...
    'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0);
id="effch_"+sixgr.phy.waveform.WaveformHash.bytes( ...
    evidence.LinkID+"|"+string(first)+"|"+string(stop)+"|"+waveformHash);
matRelative=string(fullfile('channel','mat',id+".mat"));
matPath=fullfile(root,matRelative);
csvPath=fullfile(root,'channel','csv',id+"_segments.csv");
mkdir(fileparts(matPath)); mkdir(fileparts(csvPath));
payload=struct('ManifestJSON',string(jsonencode(manifest)), ...
    'DesiredLinkWaveform',waveform,'Evidence',evidence);
save(matPath,'-struct','payload',char(format));
row=table(id,evidence.LinkID,evidence.TransmitterID,evidence.ReceiverID, ...
    first,stop,rate,size(waveform,1),size(waveform,2),waveformHash,matRelative, ...
    false,0,0,'VariableNames',{'ChannelObservationID','LinkID','TransmitterID', ...
    'ReceiverID','StartSample','EndSampleExclusive','SampleRateHz','TimeSampleCount', ...
    'ReceiveBranchCount','WaveformSHA256','WaveformMATFile','ReceiverEstimatorInput', ...
    'AdditionalChannelExecutions','AdditionalRFExecutions'});
writetable(row,csvPath);
end

function hashes=pairHashes(matPath,csvPath)
hashes=strings(1,2); files=[string(matPath),string(csvPath)];
for n=1:2
    if isfile(files(n)), hashes(n)=sixgr.phy.waveform.WaveformHash.file(files(n)); end
end
end

function expectFailure(action)
try
    action();
catch cause
    assert(any(string(cause.identifier)==[ ...
        "sixgr:truth:InvalidSharedScoringArtifact", ...
        "sixgr:truth:IncompleteSharedScoringArtifacts"]), ...
        'Unexpected validation failure: %s',cause.identifier);
    return;
end
error('test:ScoringArtifactAcceptedCorruption','Expected immutable artifact validation to reject this case.');
end
