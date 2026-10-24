function varargout=sixgr_ldpc_decode_batch_kernel(varargin) %#ok<STOUT,INUSD>
%SIXGR_LDPC_DECODE_BATCH_KERNEL Retired one-bit algorithm/parity-head ABI.
% Keeping a loud compatibility boundary prevents old scripts from silently
% substituting BP for LBP/OMS or reporting one check as complete CB evidence.
error('sixgr:phy:RetiredLDPCBatchABI', ...
    ['Use sixgr.phy.phycode.decodeLDPCConfigured or the explicit v2 kernel. ' ...
     'The v1 binary is not a qualified implementation of this contract.']);
end
