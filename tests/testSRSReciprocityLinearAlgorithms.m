function ok = testSRSReciprocityLinearAlgorithms()
% Receiver-policy algebra, NOT array/RF reciprocity or campaign qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
H = [1+.3i .2-.4i .5+.2i; -.4+.2i 1-.1i .3+.7i];
for method = ["MRT","ZF","SVD"]
    W = sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(H,2,char(method));
    assert(isequal(size(W),[3 2]) && max(abs(sum(abs(W).^2,1)-1))<1e-12);
    assert(abs(norm(W,'fro')^2-2)<1e-12,'Column normalization is not total-power normalization.');
    if method=="ZF"
        effective = H*W;
        assert(norm(effective-diag(diag(effective)),'fro')<1e-12);
        assert(all(abs(diag(effective))>0));
    elseif method=="MRT"
        expected = H'./sqrt(sum(abs(H').^2,1));
        assert(norm(W-expected,'fro')<1e-12,'MRT is not conjugate channel steering.');
    else
        [~,~,V] = svd(H,'econ');
        assert(norm(W*W'-V*V','fro')<1e-12);
    end
end
% Weak but full-rank streams distinguish ZF from silently regularized ZF.
weak = diag([1 1e-8]);
W = sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(weak,2,'ZF');
assert(norm(W-eye(2),'fro')<1e-12);
% Every singleton receive/transmit configuration must preserve channel axes.
for nr = [1 4]
    for nt = [1 4]
        A = reshape((1:nr*nt)+1i*(nr*nt:-1:1),nr,nt);
        estimates = repmat(reshape(A,1,1,nr,nt),3,2,1,1);
        out = sixgr.rf.BeamformingSRSReciprocity.fromHest(estimates,1,'SVD');
        assert(isequal(size(out.Hbar),[nr nt]) && norm(out.Hbar-A,'fro')<1e-12);
        assert(isequal(out.Hdl,A.') && isequal(size(out.W),[nr 1]));
        assert(out.nLayers==size(out.W,2));
    end
end
localMustError(@()sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(ones(2),2,'ZF'), ...
    'BeamformingSRSReciprocity:RankDeficientZF');
localMustError(@()sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(ones(2),2,'SVD'), ...
    'BeamformingSRSReciprocity:RankDeficientSVD');
localMustError(@()sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(H,3,'SVD'), ...
    'BeamformingSRSReciprocity:InvalidLayers');
localMustError(@()sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(zeros(2),1,'MRT'), ...
    'BeamformingSRSReciprocity:ZeroPrecoder');
% Existing DFT codebook already has the essential denominator absent from
% the note's printed formula. Check rather than importing the faulty formula.
B = sixgr.rf.getCachedOversampledDFTCodebook(8,8);
assert(norm(B'*B-eye(8),'fro')<1e-12);
B = sixgr.rf.getCachedOversampledDFTCodebook(8,16);
assert(max(abs(sum(abs(B).^2,1)-1))<1e-12 && rank(B)==8);
ok = true;
fprintf('PASS testSRSReciprocityLinearAlgorithms: MRT/ZF/SVD, singleton axes, DFT normalization and rank guards.\n');
end

function localMustError(fun,id)
try
    fun();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error %s instead of %s.',err.identifier,id);
    return;
end
error('testSRSReciprocityLinearAlgorithms:MissingError','Expected %s.',id);
end
