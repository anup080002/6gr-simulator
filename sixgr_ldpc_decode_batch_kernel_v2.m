function [decoded,iterations,parity,receipt]=sixgr_ldpc_decode_batch_kernel_v2(llr,bgn,maxIter,varargin)
%SIXGR_LDPC_DECODE_BATCH_KERNEL_V2 Complete policy and parity batch contract.
% MATLAB implementation, deliberately distinct from the old MEX ABI.
if isvector(llr), llr=llr(:); end
assert(ismatrix(llr)&&~isempty(llr),'sixgr:phy:LDPCBatchInput','Require nonempty CB matrix.');
blocks=size(llr,2); receipts=cell(1,blocks);
decoded=[]; iterations=zeros(1,blocks); parity=[];
for c=1:blocks
    [d,it,pc,r]=sixgr.phy.phycode.decodeLDPCExact(llr(:,c),bgn,maxIter,varargin{:});
    if c==1
        decoded=zeros(size(d,1),blocks,'like',d);
        parity=zeros(size(pc,1),blocks,'like',pc);
    end
    assert(size(d,1)==size(decoded,1)&&size(pc,1)==size(parity,1), ...
        'sixgr:phy:LDPCBatchShape','Every CB must retain complete decoded bits and final checks.');
    decoded(:,c)=d; iterations(c)=it; parity(:,c)=pc; receipts{c}=r;
end
receipt=receipts{1};
receipt.DecoderEngine="sixgr_ldpc_decode_batch_kernel_v2_MATLAB";
receipt.CodeBlockCount=blocks; receipt.DecodedShape=size(decoded);
receipt.FinalParityCheckShape=size(parity);
receipt.ActualIterationsPerCodeBlock=iterations;
receipt.UnsatisfiedParityChecksPerCodeBlock=sum(parity~=0,1);
receipt.AllParityChecksSatisfiedPerCodeBlock=all(parity==0,1);
receipt.CodeBlockReceipts=receipts;
end
