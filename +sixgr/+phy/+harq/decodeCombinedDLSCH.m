function [ok,meanIter,tbBits]=decodeCombinedDLSCH(layout,recLLR,cfg)
% Decode received DL mother-code LLRs without a transmitter object.
% TS 38.212 7.2.1-7.2.3: retained TB CRC and segmentation apply to every RV.
fields={'Direction','TransportBlockSize','TBCRCType','TBCRCLength', ...
    'BaseGraph','MotherCodeLength','NumCodeBlocks','LiftingSize','B'};
assert(isstruct(layout) && isscalar(layout) && all(isfield(layout,fields)) && ...
    string(layout.Direction)=="DL",'sixgr:phy:harq:DLReceiverCodingLayoutRequired', ...
    'Combined DL decoding requires the receiver coding layout, not a transmitter object.');
A=double(layout.TransportBlockSize); bgn=double(layout.BaseGraph);
N=double(layout.MotherCodeLength); C=double(layout.NumCodeBlocks); z=double(layout.LiftingSize);
validateattributes(A,{'double'},{'scalar','integer','positive','finite'});
crcType="16"; crcLength=16;
if A>3824, crcType="24A"; crcLength=24; end
assert(ismember(bgn,[1 2]) && z>0 && z==fix(z) && ...
    N==(66*(bgn==1)+50*(bgn==2))*z && C>=1 && C==fix(C) && ...
    string(layout.TBCRCType)==crcType && double(layout.TBCRCLength)==crcLength && ...
    double(layout.B)==A+crcLength,'sixgr:phy:harq:DLReceiverCodingLayoutMismatch', ...
    'Receiver LDPC dimensions and TB CRC must agree with the retained DL transport block.');
assert(isnumeric(recLLR) && isreal(recLLR) && isequal(size(recLLR),[N C]) && ...
    ~any(isnan(recLLR(:))),'sixgr:phy:harq:DLCombinedLLRShapeMismatch', ...
    'Rate-recovered DL soft bits must match the receiver mother-code rows and code blocks.');
algorithm=char(string(sixgr.util.structGet(cfg,'phy.ldpc.algorithm','Normalized min-sum')));
maxIter=sixgr.phy.phycode.resolveLDPCMaxIterations(cfg,'Direction','DL');
K=(22*(bgn==1)+10*(bgn==2))*z;
decoded=zeros(K,C,'int8'); iterations=NaN(C,1);
for c=1:C
    [bits,it]=sixgr.phy.phycode.ldpcDecode(double(recLLR(:,c)),bgn,maxIter,algorithm);
    assert(numel(bits)==K,'sixgr:phy:harq:DLDecodedCodeBlockShapeMismatch', ...
        'LDPC output must match the receiver code-block dimensions.');
    decoded(:,c)=int8(bits(:));
    if ~isempty(it), iterations(c)=double(it(1)); end
end
[withCRC,cbError]=sixgr.phy.tb.desegmentLDPC(decoded,bgn,A+crcLength);
[tbBits,tbOK]=sixgr.phy.tb.checkCRC(withCRC,char(crcType));
tbBits=int8(tbBits(:));
ok=logical(tbOK && ~any(cbError(:)) && numel(tbBits)==A);
meanIter=mean(iterations,'omitnan');
end
