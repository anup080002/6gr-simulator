function [row,selectionReference]=exportSharedCSIRSChannelEstimate(root,row,prepared,reception,source,captures)
% Persist exact paired pilot operands only after practical CSI computation.
selectionReference=struct();
if nargout>1
    [metrics,resources,evidence,selectionReference]=sixgr.truth.scoreSharedCSIRSChannel(prepared,reception,source,captures);
else
    [metrics,resources,evidence]=sixgr.truth.scoreSharedCSIRSChannel(prepared,reception,source,captures);
end
for name=string(fieldnames(metrics)).', row.(name)=metrics.(name); end
if isempty(resources), return; end
resources.UEIndex(:)=row.UEIndex;
resources.CellID=repmat(row.CellID,height(resources),1);
if ismember('SweepPointIndex',row.Properties.VariableNames)
    resources.SweepPointIndex=repmat(row.SweepPointIndex,height(resources),1);
end
values=[resources.ResourceID resources.SubcarrierIndex0 resources.SymbolIndex0 ...
    resources.RxBranchIndex0 resources.ReferencePortIndex0 ...
    resources.HReal resources.HImag resources.ReferenceHReal resources.ReferenceHImag];
digest=sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(values);
point="not_bound";
if ismember('SweepPointIndex',row.Properties.VariableNames), point=string(row.SweepPointIndex); end
identity=sixgr.phy.waveform.WaveformHash.bytes("csirs_nominal_channel/v1|"+ ...
    string(row.UEIndex)+"|"+string(row.CellID)+"|"+string(row.Slot)+"|"+point+"|"+string(digest));
row.CSIChannelEstimateObservationID="csirs_"+identity;
resources.CSIChannelEstimateObservationID=repmat(row.CSIChannelEstimateObservationID,height(resources),1);
relative=fullfile('channel_estimation','csv',"csirs_"+identity+".csv");
matRelative=fullfile('channel_estimation','mat',"csirs_"+identity+".mat");
csvPath=fullfile(root,relative); matPath=fullfile(root,matRelative);
assert(~isfile(csvPath) && ~isfile(matPath),'sixgr:truth:DuplicateCSIRSChannelPublication', ...
    'Never overwrite retained receiver measurements.');
sixgr.util.csvWriteTable(csvPath,resources,'PreserveSchema',true,'RoundTripNumericText',true);
payload=struct('Contract',"scored_CSI_RS_nominal_channel_resources/v1", ...
    'Resources',resources,'Metrics',metrics,'ReferenceEvidence',evidence, ...
    'ResourcesCSVSHA256',sixgr.phy.waveform.WaveformHash.file(csvPath));
sixgr.util.matSave(matPath,payload,'UseArtifactStore',false);
saved=sixgr.util.csvReadTable(csvPath,'TextType','string');
assert(height(saved)==height(resources) && ...
    all(saved.CSIChannelEstimateObservationID==row.CSIChannelEstimateObservationID) && ...
    isequaln(saved.HReal,resources.HReal) && isequaln(saved.HImag,resources.HImag) && ...
    isequaln(saved.ReferenceHReal,resources.ReferenceHReal) && ...
    isequaln(saved.ReferenceHImag,resources.ReferenceHImag) && ...
    abs(sum(saved.ChannelErrorEnergy)-metrics.ChannelNMSEErrorEnergy)<=128*eps(max(1,metrics.ChannelNMSEErrorEnergy)) && ...
    abs(sum(saved.ReferenceChannelEnergy)-metrics.ChannelNMSEReferenceEnergy)<=128*eps(max(1,metrics.ChannelNMSEReferenceEnergy)), ...
    'sixgr:truth:CSIRSChannelCSVClosure','Saved operands must reproduce every independent scored pilot/port.');
row.ChannelEstimateResourcesCSV=string(relative);
row.ChannelEstimateResourcesCSVSHA256=payload.ResourcesCSVSHA256;
row.ChannelEstimateMATFile=string(matRelative);
row.ChannelEstimateMATFileSHA256=sixgr.phy.waveform.WaveformHash.file(matPath);
end
