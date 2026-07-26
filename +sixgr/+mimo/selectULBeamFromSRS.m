function [W_UL, beamIdx, beamHit, gainGap_dB, info] = selectULBeamFromSRS(~, ~, H_SRS, oracleBeam, mimoCfg)
%SELECTULBEAMFROMSRS Measured-SRS RI/SRI/TPMI authority for UL precoding.

if nargin < 4
    oracleBeam = [];
end
if nargin < 5 || ~isstruct(mimoCfg)
    mimoCfg = struct();
end
if ~isempty(oracleBeam) && any(isfinite(double(oracleBeam(:))))
    error("sixgr:mimo:BeamMeasurementOracleForbidden", ...
        "Oracle beam input is forbidden in the strict measured-SRS path.");
end
if isempty(H_SRS) || ~isnumeric(H_SRS)
    error("sixgr:mimo:MissingSRSDecision", ...
        "UL beam selection requires measured SRS channel state.");
end
noiseVar = double(sixgr.util.structGet(mimoCfg,"NoiseVar", ...
    sixgr.util.structGet(mimoCfg,"NoiseVariance",NaN)));
if ~(isscalar(noiseVar)&&isfinite(noiseVar)&&noiseVar>0)
    error("sixgr:mimo:MissingSRSDecision", ...
        "UL beam selection requires measured SRS noise variance.");
end
cfg = mimoCfg;
nPorts = size(H_SRS,2);
if strlength(string(sixgr.util.structGet(cfg,"phy.pusch.transmissionScheme",""))) == 0
    if logical(sixgr.util.structGet(cfg,"Strict",false))
        error("sixgr:mimo:MissingSRSDecision", ...
            "Strict UL selection requires transmissionScheme configuration.");
    end
    cfg.phy.pusch.transmissionScheme = "codebook";
end
if isempty(sixgr.util.structGet(cfg,"phy.pusch.NumAntennaPorts",[]))
    if logical(sixgr.util.structGet(cfg,"Strict",false))
        error("sixgr:mimo:UnsupportedAntennaTuple", ...
            "Strict UL selection requires explicit PUSCH antenna ports.");
    end
    cfg.phy.pusch.NumAntennaPorts = nPorts;
end
estimate = sixgr.phy.ul.estimateSRSRITPMI(H_SRS,noiseVar,cfg);
if ~logical(estimate.Valid) || ~isfinite(estimate.RI) || ~isfinite(estimate.TPMI)
    error("sixgr:mimo:MissingSRSDecision", ...
        "Measured SRS did not produce a valid RI/TPMI decision.");
end
rankValue = double(estimate.RI);
tpmi = double(estimate.TPMI);
codebookType = char(string(sixgr.util.structGet(cfg, ...
    "phy.pusch.codebookType","codebook1_ng1n4n1")));
transformPrecoding = logical(sixgr.util.structGet(cfg, ...
    "phy.pusch.transformPrecoding",false));
Wtoolbox = nrPUSCHCodebook(rankValue,double(estimate.PUSCHCodebookNumPorts), ...
    tpmi,transformPrecoding,codebookType);
% nrPUSCHCodebook returns Nlayer-by-Nport. The canonical simulator
% convention is Nport-by-Nlayer; this is an explicit documented API
% boundary conversion, not dimension guessing.
expectedToolboxSize = [rankValue,double(estimate.PUSCHCodebookNumPorts)];
if ~isequal(size(Wtoolbox),expectedToolboxSize)
    error("sixgr:mimo:PrecoderDimensionMismatch", ...
        "nrPUSCHCodebook returned %s; expected documented %s.", ...
        mat2str(size(Wtoolbox)),mat2str(expectedToolboxSize));
end
W_UL = Wtoolbox.';
matrixInfo = sixgr.phy.mimo.MatrixContract.validate( ...
    W_UL,size(W_UL,1),size(W_UL,2));
beamIdx = tpmi;
beamHit = NaN;
gainGap_dB = 0;
info = estimate;
info.SelectedBeamIndex = tpmi;
info.SelectedBeamGain_dB = NaN;
info.BeamHit = NaN;
info.BeamGainGap_dB = 0;
info.RuntimeEvidenceSource = "measured_srs_posteq_mi_ri_tpmi";
info.MeasurementAuthoritative = true;
info.ConfiguredOverrideUsed = false;
info.SelectionMatrixSHA256 = matrixInfo.MatrixSHA256;
info.SchedulerMatrixSHA256 = matrixInfo.MatrixSHA256;
info.AppliedMatrixSHA256 = matrixInfo.MatrixSHA256;
end
