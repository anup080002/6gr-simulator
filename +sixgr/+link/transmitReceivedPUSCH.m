function [tx,info]=transmitReceivedPUSCH(installed,assignment,bits,uci)
% UE new-TB transmission from accepted DCI and UE-owned payload only.
% No scheduler PHYGrant, transmitter object, TBS or coding layout is input.
allocation=sixgr.phy.pdcch.connectedDataAllocation(installed,assignment);
assert(assignment.Direction=="UL" && assignment.ULSCHIndicator==1, ...
    'sixgr:link:ReceivedULSCHRequired','This path requires a received UL-SCH assignment.');
assert(~isempty(bits) && numel(bits)==allocation.NominalTBSBits, ...
    'sixgr:link:ReceivedULTBSizeMismatch', ...
    'UE new-TB payload length must equal the TBS derived from received control.');
cfg=allocation.Config;
if isfield(cfg.phy,'canonicalGrant'), cfg.phy=rmfield(cfg.phy,'canonicalGrant'); end
if isfield(cfg.phy.pusch,'srsDecision'), cfg.phy.pusch=rmfield(cfg.phy.pusch,'srsDecision'); end
args={'TransportBlockBits',bits};
if isfield(allocation,'ResearchTransport')
    args=[args {'ResearchTransport',allocation.ResearchTransport}];
end
if ~isempty(uci)
    % Zero wire bits still carry the received Type-2 DAI procedure identity.
    % PUSCH_Tx decides whether coding is needed; do not erase that binding.
    args=[args {'UCIPayload',uci}];
    if uci.hasPayload()
        args=[args {'InitialIMCSPerCodeword',assignment.MCS}];
    end
end
[tx,info]=sixgr.phy.ul.PUSCH_Tx(cfg,args{:});
assert(tx.PrecodeInfo.AuthoritativeDCIDecisionUsed && ...
    ~tx.PrecodeInfo.AuthoritativeSRSDecisionUsed && ...
    tx.TransportBlockSize==allocation.NominalTBSBits, ...
    'sixgr:link:ReceivedULTransmissionAuthorityMismatch', ...
    'Actual UE transmission must retain decoded-control authority and independently sized TB.');
tx.TransmissionAuthority="received_dci_and_ue_new_tb_payload";
tx.ReceivedDCIAssignmentDigest=assignment.AssignmentDigest;
info.TransmissionAuthority=tx.TransmissionAuthority;
info.ReceivedDCIAssignmentDigest=assignment.AssignmentDigest;
end
