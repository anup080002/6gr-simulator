function T=exportSharedDataChannelEstimate(root,T,snapshot,prepared,referenceSource,referenceEvidence,varargin)
% Post-reception publication only; never changes decoded bits or feedback.
assert(istable(T) && height(T)==1 && isfolder(root) && ...
    ismember('ChannelObservationID',T.Properties.VariableNames), ...
    'sixgr:truth:PUSCHChannelExportIdentity','One actual received trial and its captured channel identity are required.');
if isa(referenceSource,'sixgr.phy.waveform.WaveformObservationBuffer')
    [reference,evidence]=sixgr.truth.sharedDataScoringWaveformReference( ...
        snapshot,prepared,referenceSource,referenceEvidence);
else
    assert(numel(varargin)==1, ...
        'sixgr:truth:MissingDataChannelProjection', ...
        'Legacy coefficient scoring requires the executed waveform-to-element projection.');
    [reference,evidence]=sixgr.truth.sharedDataChannelReference( ...
        snapshot,prepared,referenceSource,referenceEvidence,varargin{1});
end
channel="PUSCH"; if prepared.Direction=="DL", channel="PDSCH"; end
context=struct('Channel',channel,'Slot',double(T.Slot), ...
    'UEIndex',double(T.UEIndex),'ConfiguredSNR_dB',double(T.ConfiguredSNR_dB), ...
    'ChannelEstimateSource',snapshot.Source,'ChannelReferenceSource',evidence.Source, ...
    'ChannelReferencePlane',evidence.ReferencePlane);
[resources,score]=sixgr.report.buildReceiverChannelEstimateTable( ...
    snapshot,reference,snapshot.PilotIndices,context);
resources.ChannelObservationID=repmat(string(T.ChannelObservationID),height(resources),1);
resources.ReferenceRFImpairmentsIncluded=repmat(logical(evidence.RFImpairmentsIncluded),height(resources),1);
% Preserve the exact scored complex reference as well as Hest. The compact
% snapshot and aggregate score alone cannot reconstruct the reference REs.
% This is post-reception archival evidence, never receiver estimator input.
payload=struct('Contract',"scored_data_channel_resource_archive/v1", ...
    'Snapshot',snapshot,'ReferenceEvidence',evidence,'Score',score, ...
    'Resources',resources);
digest=sixgr.channel.ChannelFactory.runtimeNumericArraySHA256( ...
    [resources.HReal resources.HImag resources.ReferenceHReal resources.ReferenceHImag]);
identityHash=sixgr.phy.waveform.WaveformHash.bytes(string(T.ChannelObservationID)+"|"+string(digest));
stem=lower(channel)+"_"+string(identityHash);
relative=fullfile('channel_estimation','csv',stem+".csv");
matRelative=fullfile('channel_estimation','mat',stem+".mat");
csvPath=fullfile(root,relative); matPath=fullfile(root,matRelative);
assert(~isfile(csvPath) && ~isfile(matPath), ...
    'sixgr:truth:DuplicatePUSCHChannelPublication','Never overwrite retained receiver measurements.');
sixgr.util.csvWriteTable(csvPath,resources,'PreserveSchema',true,'RoundTripNumericText',true);
payload.ResourcesCSVSHA256=sixgr.phy.waveform.WaveformHash.file(csvPath);
sixgr.util.matSave(matPath,payload,'UseArtifactStore',false);
saved=sixgr.util.csvReadTable(csvPath,'TextType','string');
assert(height(saved)==score.ComparedComplexValueCount && ...
    abs(sum(saved.ChannelErrorEnergy)-score.ErrorEnergy)<=128*eps(max(1,score.ErrorEnergy)) && ...
    abs(sum(saved.ReferenceChannelEnergy)-score.ReferenceEnergy)<=128*eps(max(1,score.ReferenceEnergy)), ...
    'sixgr:truth:PUSCHChannelCSVClosure','Saved pilot resources must reproduce the actual independent NMSE energies.');
T.NMSE_dB=score.dB;
T.NMSESource=evidence.Source;
T.ChannelEstimateCaptureStatus="measured_and_independently_scored_after_reception";
T.ChannelEstimateResourcesCSV=string(relative);
T.ChannelEstimateResourcesCSVSHA256=sixgr.phy.waveform.WaveformHash.file(csvPath);
T.ChannelEstimateMATFile=string(matRelative);
T.ChannelEstimateMATFileSHA256=sixgr.phy.waveform.WaveformHash.file(matPath);
T.ChannelEstimateReferencePlane=evidence.ReferencePlane;
T.ChannelEstimateReferenceRFImpairmentsIncluded=logical(evidence.RFImpairmentsIncluded);
T.ChannelEstimateReferenceUsedByReceiver=false;
T.ChannelEstimateComparedValues=score.ComparedComplexValueCount;
end
