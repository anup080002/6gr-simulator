function [decCB,actNumIter,finalParityChecks,receipt]=ldpcDecode(llr,bgn,maxNumIter,algorithm,varargin)
%LDPCDECODE Exact native policy; complete final checks-by-code-block matrix.
% Omitted algorithm preserves the native Belief Propagation default. Decoder
% choice is implementation policy. TB acceptance remains the caller's CRC.
if nargin<3 || isempty(maxNumIter), maxNumIter=12; end
if nargin<4 || isempty(algorithm), algorithm='Belief propagation'; end
[decCB,actNumIter,finalParityChecks,receipt]= ...
    sixgr.phy.phycode.decodeLDPCExact(llr,bgn,maxNumIter, ...
    'Algorithm',algorithm,varargin{:});
end
