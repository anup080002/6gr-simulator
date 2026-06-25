function [Wlayer, status, Wtx, Winv] = puschCodebookProjectionMatrix(nLayers, nPorts, tpmi, transformPrecoding)
%PUSCHCODEBOOKPROJECTIONMATRIX NR PUSCH codebook layer-to-port matrix.
%   Wlayer is NumPorts-by-NumLayers. Port-domain symbols are X=S*Wlayer.'
%   Wtx is NumLayers-by-NumPorts and follows nrPUSCHCodebook directly.
%   Winv is the right inverse used for symbol-domain recovery S=X*Winv.

narginchk(3, 4);
if nargin < 4
    transformPrecoding = false;
end
nLayers = round(double(nLayers));
nPorts = round(double(nPorts));
tpmi = round(double(tpmi));
if ~(isscalar(nLayers) && isscalar(nPorts) && isscalar(tpmi) && ...
        isfinite(nLayers) && isfinite(nPorts) && isfinite(tpmi))
    error("sixgr:phy:ul:PUSCHCodebookProjection:BadParameters", ...
        "PUSCH codebook projection requires finite scalar layers, ports and TPMI.");
end
catalog = sixgr.phy.ul.puschCodebookCatalog(nLayers, nPorts, logical(transformPrecoding));
if ~logical(catalog.Valid)
    error("sixgr:phy:ul:PUSCHCodebookProjection:UnsupportedCombination", ...
        "Unsupported PUSCH codebook combination: ports=%d layers=%d transformPrecoding=%d (%s).", ...
        nPorts, nLayers, logical(transformPrecoding), char(string(catalog.Reason)));
end
if ~any(double(tpmi) == double(catalog.ValidTPMISet))
    error("sixgr:phy:ul:PUSCHCodebookProjection:UnsupportedTPMI", ...
        "Unsupported PUSCH TPMI=%d for ports=%d layers=%d transformPrecoding=%d. Valid TPMI set is %s.", ...
        tpmi, nPorts, nLayers, logical(transformPrecoding), mat2str(double(catalog.ValidTPMISet)));
end
if exist("nrPUSCHCodebook", "file") ~= 2
    error("sixgr:phy:ul:PUSCHCodebookProjection:ToolboxUnavailable", ...
        "PUSCH codebook projection requires nrPUSCHCodebook from 5G Toolbox.");
end

try
    Wtx = nrPUSCHCodebook(nLayers, nPorts, tpmi, logical(transformPrecoding));
catch ME
    error("sixgr:phy:ul:PUSCHCodebookProjection:ToolboxMatrixFailed", ...
        "nrPUSCHCodebook failed for catalog-valid ports=%d layers=%d TPMI=%d transformPrecoding=%d: %s", ...
        nPorts, nLayers, tpmi, logical(transformPrecoding), ME.message);
end
if isempty(Wtx) || ~isequal(size(Wtx), [nLayers nPorts])
    error("sixgr:phy:ul:PUSCHCodebookProjection:UnexpectedShape", ...
        "nrPUSCHCodebook returned shape %s but expected [%d %d].", ...
        mat2str(size(Wtx)), nLayers, nPorts);
end
Wtx = double(Wtx);
if rank(Wtx) < nLayers
    error("sixgr:phy:ul:PUSCHCodebookProjection:RankDeficient", ...
        "nrPUSCHCodebook returned a rank-deficient matrix for ports=%d layers=%d TPMI=%d.", ...
        nPorts, nLayers, tpmi);
end
Wlayer = Wtx.';
Winv = pinv(Wtx);
if logical(transformPrecoding)
    status = sprintf("nr_pusch_transform_codebook_%dports_%dlayers_tpmi_%d", ...
        nPorts, nLayers, tpmi);
else
    status = sprintf("nr_pusch_cpofdm_codebook_%dports_%dlayers_tpmi_%d", ...
        nPorts, nLayers, tpmi);
end
end
