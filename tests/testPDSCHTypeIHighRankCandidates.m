function ok = testPDSCHTypeIHighRankCandidates()
%TESTPDSCHTYPEIHIGHRANKCANDIDATES Guard the shared Type-I rank basis.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

cfg = struct();
cfg.phy.csi.codebookType = "type1";
cfg.phy.csi.pmiCodebookMode = "type1_su_mimo";
% Deliberately keep the beam-management sweep at four.  Rank-3/4 CSI
% precoding must still resolve its own complete port-domain basis.
cfg.phy.beamManagement.dlCodebookSize = 4;

for rankValue = 1:4
    [candidates, info] = sixgr.phy.dl.pmiCodebookCandidates( ...
        cfg, rankValue, 4, "Mode", "type1_su_mimo");
    assert(~isempty(candidates), ...
        "No 4-port Type-I candidate was produced for rank %d.", rankValue);
    assert(double(info.NumPorts) == 4 && ...
        double(info.NumLayers) == rankValue, ...
        "Type-I candidate metadata lost the port/rank contract.");
    for candidateIndex = 1:numel(candidates)
        W = double(candidates(candidateIndex).W);
        assert(isequal(size(W), [4 rankValue]) && ...
            all(isfinite(real(W(:)))) && all(isfinite(imag(W(:)))), ...
            "Type-I rank-%d candidate %d has an invalid matrix.", ...
            rankValue, candidateIndex);
        assert(rank(W) == rankValue && ...
            norm(W' * W - eye(rankValue), "fro") <= 1e-10, ...
            "Type-I rank-%d candidate %d is not semi-unitary.", ...
            rankValue, candidateIndex);
    end
end

% Rank three and four cannot be represented by the two-polarization span
% of one spatial vector.  The internal CSI basis must be distinct from the
% four-beam SSB/beam-management sweep configured above.
[rank3, info3] = sixgr.phy.dl.pmiCodebookCandidates( ...
    cfg, 3, 4, "Mode", "type1_su_mimo");
[rank4, info4] = sixgr.phy.dl.pmiCodebookCandidates( ...
    cfg, 4, 4, "Mode", "type1_su_mimo");
assert(double(info3.NumBeams) >= 8 && double(info4.NumBeams) >= 8, ...
    "High-rank Type-I codebook basis incorrectly followed the sweep size.");
assert(rank(double(rank3(1).W)) == 3 && rank(double(rank4(1).W)) == 4, ...
    "High-rank Type-I codebook did not preserve requested rank.");

fprintf("PDSCHTypeIHighRankCandidates: 4-port ranks 1-4 semi-unitary.\n");
ok = true;
end
