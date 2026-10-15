function [mapped,info] = puschDemapperCSI(csi,carrier,pusch,qamShape)
%PUSCHDEMAPPERCSI Bind equalizer reliability to the demapper symbol domain.
% For DFT-s-OFDM each inverse-DFT output uses the same mean equalizer CSI
% over that transform block. This equals the DC output of the unitary
% inverse DFT divided by sqrt(Msc), as in MathWorks NR PUSCH Throughput.
% Remove pre-transform PT-RS samples exactly as nrPUSCHDecode does. Never
% truncate/repeat frequency-domain CSI merely to match an LLR length.
mapped=csi;
info=struct('Source',"equalizer_layer_RE_CSI", ...
    'InputCount',numel(csi),'OutputCount',numel(csi), ...
    'PTRSSamplesRemoved',0,'TransformBlockSize',0);
if ~logical(pusch.TransformPrecoding), return; end
validateattributes(csi,{'numeric'},{'2d','real','finite','nonnegative','nonempty'});
msc=12*numel(pusch.PRBSet);
assert(msc>0 && mod(size(csi,1),msc)==0 && size(csi,2)==pusch.NumLayers, ...
    'sixgr:phy:ul:PUSCHCSIDomainMismatch', ...
    'Equalizer CSI must contain complete DFT blocks for every received layer.');
blocks=reshape(double(csi),msc,[],pusch.NumLayers);
averaged=repmat(mean(blocks,1),msc,1,1);
averaged=reshape(averaged,size(csi));
keep=true(size(csi));
relative=nrPUSCHPTRSIndices(carrier,pusch,'IndexBase','1based');
assert(all(double(relative(:))>=1 & double(relative(:))<=numel(keep)), ...
    'sixgr:phy:ul:PUSCHCSIPTRSIndexMismatch', ...
    'PT-RS indices must address the pre-transform equalizer allocation.');
keep(relative)=false;
assert(numel(qamShape)==2 && all(isfinite(qamShape) & qamShape>=0 & qamShape==fix(qamShape)) && ...
    qamShape(2)==pusch.NumLayers && nnz(keep)==prod(qamShape), ...
    'sixgr:phy:ul:PUSCHCSIDemapperShapeMismatch', ...
    'Data CSI after PT-RS removal must match the decoded QAM-symbol dimensions.');
mapped=reshape(averaged(keep),qamShape);
info.Source="per_DFT_block_mean_equalizer_CSI_pretransform_PTRS_removed";
info.OutputCount=numel(mapped);
info.PTRSSamplesRemoved=nnz(~keep);
info.TransformBlockSize=msc;
end
