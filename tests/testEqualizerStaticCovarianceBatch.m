function ok = testEqualizerStaticCovarianceBatch()
%TESTEQUALIZERSTATICCOVARIANCEBATCH Exact 4x64-style IRC batch regression.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
rng(260806,"twister");
nRE = 48;
nRx = 64;
nLayers = 2;
rx = complex(randn(nRE,nRx),randn(nRE,nRx))/sqrt(2);
H = complex(randn(nRE,nRx,nLayers),randn(nRE,nRx,nLayers))/sqrt(2*nRx);
B = complex(randn(nRx,8),randn(nRx,8))/sqrt(16);
R = B*B' + 0.15*eye(nRx);
nVar = 0.01;

[eq,~,info] = sixgr.phy.rx.equalizeMMSE(rx,H,nVar, ...
    "Algorithm","IRC","Rint",R,"RIncludesNoise",true);
assert(string(info.EngineUsed) == "batchedStaticCovarianceVariableChannel");
assert(double(info.CovarianceFactorizationCount) == 1, ...
    "Static IRC covariance must be factorized exactly once.");
assert(double(info.UniqueSolveCount) == nRE, ...
    "A varying channel still requires one exact layer-domain filter per RE.");

Rprepared = (R+R')/2;
Rprepared = Rprepared + max(norm(Rprepared,"fro")*1e-12,eps)*eye(nRx);
reference = complex(zeros(nRE,nLayers));
referenceSINR = zeros(nRE,nLayers);
for re = 1:nRE
    Hre = reshape(H(re,:,:),nRx,nLayers);
    RinvH = Rprepared\Hre;
    W = (Hre'*RinvH+eye(nLayers))\RinvH';
    reference(re,:) = (W*rx(re,:).').';
    WH = W*Hre;
    Cout = W*Rprepared*W';
    for layer = 1:nLayers
        desired = abs(WH(layer,layer))^2;
        interference = sum(abs(WH(layer,:)).^2)-desired;
        referenceSINR(re,layer) = desired/max(interference+real(Cout(layer,layer)),eps);
    end
end

assert(max(abs(eq(:)-reference(:))) < 2e-10, ...
    "Batched static-covariance IRC changed equalized symbols.");
actualSINR = double(info.EqualizerResult.PostEqSINRLinear);
assert(max(abs(actualSINR(:)-referenceSINR(:))) < 2e-10, ...
    "Batched static-covariance IRC changed post-EQ SINR.");
fprintf("PASS testEqualizerStaticCovarianceBatch: %d RE, %dx%d, one covariance factorization.\n", ...
    nRE,nRx,nLayers);
ok = true;
end
