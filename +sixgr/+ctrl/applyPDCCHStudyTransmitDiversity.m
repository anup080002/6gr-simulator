function outGrid = applyPDCCHStudyTransmitDiversity(inGrid,cfg,trialSeed,reTable)
% Map one logical control port to TX dimensions with unit-norm weights.
% Seeded phase cycling is an explicit study precoder, not an NR codebook.
outGrid=inGrid;
if ~logical(cfg.EnableTransmitDiversity) || cfg.NTx<=1, return; end
if strcmpi(cfg.DiversityMode,"nontransparent_stub")
    error('sixgr:ctrl:runPDCCHStudyLLS:NonTransparentStub', ...
        'nontransparent_stub is declared as a future-study hook and is not decodable yet.');
end
assert(~any(inGrid(:,:,2:end,:)~=0,'all'), ...
    'sixgr:ctrl:TransmitDiversityLogicalPort', ...
    'Study diversity requires one logical input port; do not discard other ports.');
[nSC,nSym,~,nSlots]=size(inGrid);
logicalGrid=reshape(inGrid(:,:,1,:),nSC,nSym,nSlots);
outGrid=zeros(nSC,nSym,cfg.NTx,nSlots,'like',inGrid);
if strcmpi(cfg.PrecoderGranularity,"reg_bundle")
    assert(istable(reTable) && ~isempty(reTable) && ...
        all(ismember({'REGIndex','Subcarrier','Symbol','SlotIndex'},reTable.Properties.VariableNames)), ...
        'sixgr:ctrl:TransmitDiversityBundleMap','Require actual candidate REG/RE/slot identity.');
    bundleSize=double(cfg.CORESET.REGBundleSize);
    validateattributes(bundleSize,{'numeric'},{'scalar','integer','positive','finite'});
    bundle=ceil(double(reTable.REGIndex)/bundleSize);
    validateattributes(bundle,{'numeric'},{'integer','positive','finite'});
    locations=sub2ind([nSC,nSym,nSlots],double(reTable.Subcarrier)+1, ...
        double(reTable.Symbol)+1,double(reTable.SlotIndex));
    assert(numel(unique(locations))==numel(locations), ...
        'sixgr:ctrl:TransmitDiversityBundleMap','Candidate RE coordinates must be unique.');
    occupied=find(logicalGrid~=0);
    assert(all(ismember(occupied,locations)), ...
        'sixgr:ctrl:TransmitDiversityBundleMap','Every transmitted RE needs an actual REG bundle.');
    stream=RandStream('mt19937ar','Seed',double(trialSeed));
    weights=exp(1j*(pi/2)*randi(stream,[0 3],max(bundle),cfg.NTx))/sqrt(cfg.NTx);
    for tx=1:cfg.NTx
        mapped=zeros(size(logicalGrid),'like',inGrid);
        mapped(locations)=logicalGrid(locations).*weights(bundle,tx);
        outGrid(:,:,tx,:)=reshape(mapped,nSC,nSym,1,nSlots);
    end
else
    for tx=1:cfg.NTx
        outGrid(:,:,tx,:)=inGrid(:,:,1,:)/sqrt(cfg.NTx);
    end
end
end
