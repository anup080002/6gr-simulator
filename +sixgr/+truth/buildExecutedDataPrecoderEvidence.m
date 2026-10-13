function [weights,patterns]=buildExecutedDataPrecoderEvidence(owner,prepared,ue)
% Applied data weights, never a scalar-PMI reconstruction or receiver oracle.
weights=table(); patterns=table();
cfg=prepared.ReceiverConfig;
if ~logical(sixgr.util.structGet(cfg,'outputs.antennaPatternSamplesEnabled',false)), return; end
identity=sixgr.truth.preparedDataTransmissionIdentity(prepared,ue);
records=owner.DataTransmissions;
hit=arrayfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,records);
assert(nnz(hit)==1 && isequaln(records(hit).Identity,identity) && ...
    records(hit).CommittedAtSample<=owner.Events.NextSampleIndex, ...
    'sixgr:truth:PrecoderTransmissionNotExecuted', ...
    'Prepared or requested weights alone are not evidence of a started transmission.');
if prepared.Direction=="DL"
    antenna=cfg.lls6g.userContext.RuntimeServingBSAntenna;
else
    antenna=cfg.lls6g.userContext.RuntimeUEAntenna;
end
projection=records(hit).WaveformToElementMatrix;
assert(size(projection,1)==prepared.NumPhysicalTransmitAntennas, ...
    'sixgr:truth:AppliedPrecoderPhysicalDomainMismatch', ...
    'The executed mapping must address every physical transmitter column.');
[weights,patterns]=sixgr.report.buildAppliedDataPrecoderTables( ...
    prepared.Tx,projection,antenna,identity,cfg, ...
    "executed_data_precoder_mapping_shared_transmission_started");
end
