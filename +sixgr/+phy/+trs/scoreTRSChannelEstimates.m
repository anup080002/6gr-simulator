function ch=scoreTRSChannelEstimates(ch,references,evidence)
% Evaluate after practical estimation. Never fit away channel gain or phase error.
assert(iscell(references) && numel(references)==numel(ch.ChannelEstimates) && ...
    iscell(evidence) && numel(evidence)==numel(references), ...
    'sixgr:phy:trs:MissingIndependentChannelReference','Each received TRS slot needs an independent channel reference.');
for k=1:numel(references)
    e=evidence{k};
    allowedSource=any(e.Source==[ ...
        "applied_channel_gain_truth_shared_NR_path_filter_reference", ...
        "applied_identity_AWGN_operator_TRS_port_reference", ...
        "applied_fixed_matrix_AWGN_operator_TRS_port_reference", ...
        "standalone_awgn_known_noiseless_effective_response"]);
    assert(allowedSource && ...
        ~e.ReceiverEstimatorInput && ~e.GainOrPhaseFitted && e.AdditionalChannelExecutions==0, ...
        'sixgr:phy:trs:InvalidChannelScoringAuthority','Only independently retained executed channel evidence may score NMSE.');
    if ~ch.Table.TRSChannelEstimateAvailable(k), continue; end
    score=sixgr.phy.srs.pilotChannelNMSE(ch.ChannelEstimates{k},references{k},ch.PilotIndices{k});
    ch.Table.NMSE_dB(k)=score.dB;
    ch.Table.NMSEScoringAvailable(k)=true;
    ch.Table.NMSEReferenceSource(k)=e.Source;
    ch.Table.NMSEComparedComplexValues(k)=score.ComparedComplexValueCount;
    ch.Table.ChannelErrorEnergy(k)=score.ErrorEnergy;
    ch.Table.ChannelReferenceEnergy(k)=score.ReferenceEnergy;
    ch.Table.Status(k)="practical_channel_with_independent_NR_channel_NMSE";
end
ch.NMSEScoringAvailable=~isempty(ch.Table) && all(ch.Table.NMSEScoringAvailable);
if ch.NMSEScoringAvailable
    ch.MeanNMSE_dB=10*log10(sum(ch.Table.ChannelErrorEnergy)/sum(ch.Table.ChannelReferenceEnergy));
    sources=unique(string(cellfun(@(x)x.Source,evidence,'UniformOutput',false)),'stable');
    assert(isscalar(sources),'sixgr:phy:trs:MixedChannelScoringAuthority');
    ch.NMSEReferenceSource=sources;
end
ch.ChannelReferenceEvidence=evidence;
end
