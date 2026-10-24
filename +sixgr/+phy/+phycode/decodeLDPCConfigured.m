function [bits,iterations,parity,receipt]=decodeLDPCConfigured(llr,bgn,maxIter,policy,useBatch)
%DECODELDPCCONFIGURED Exact policy on native matrix or versioned batch path.
% The obsolete one-bit MEX ABI cannot represent four algorithms or complete
% parity evidence and is never selected. Requested acceleration is recorded
% separately from execution; no existing binary is assumed ABI-compatible.
if nargin<5, useBatch=false; end
policy=sixgr.config.validateLDPCPolicy(policy);
args={'Algorithm',policy.algorithm,'ScalingFactor',policy.scalingFactor, ...
    'Offset',policy.minSumOffset,'Termination',policy.termination};
if useBatch
    [bits,iterations,parity,receipt]=sixgr_ldpc_decode_batch_kernel_v2( ...
        llr,bgn,maxIter,args{:});
else
    [bits,iterations,parity,receipt]=sixgr.phy.phycode.decodeLDPCExact( ...
        llr,bgn,maxIter,args{:});
end
receipt.AccelerationRequested=logical(useBatch);
receipt.MEXApplied=false;
receipt.AccelerationStatus="native_execution";
if useBatch, receipt.AccelerationStatus="exact_MATLAB_batch_v2_no_qualified_v2_MEX"; end
end
