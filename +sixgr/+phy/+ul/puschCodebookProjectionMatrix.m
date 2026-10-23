function [Wlayer, status, Wtx, Winv] = puschCodebookProjectionMatrix(nLayers, nPorts, tpmi, transformPrecoding, codebookType)
%PUSCHCODEBOOKPROJECTIONMATRIX NR PUSCH codebook layer-to-port matrix.
%   Wlayer is NumPorts-by-NumLayers. Port-domain symbols are X=S*Wlayer.'
%   Wtx is NumLayers-by-NumPorts and follows nrPUSCHCodebook directly.
%   Winv is the right inverse used for symbol-domain recovery S=X*Winv.

narginchk(3, 5);
familyProvided = nargin >= 5;
if nargin < 4
    transformPrecoding = false;
end
if nargin < 5
    codebookType = "";
end
if ~(localInteger(nLayers, 1) && localInteger(nPorts, 1) && localInteger(tpmi, 0))
    error("sixgr:phy:ul:PUSCHCodebookProjection:BadParameters", ...
        "PUSCH codebook projection requires exact integer layers, ports and TPMI.");
end
nLayers = double(nLayers);
nPorts = double(nPorts);
tpmi = double(tpmi);
if familyProvided
    catalog = sixgr.phy.ul.puschCodebookCatalog(nLayers, nPorts, transformPrecoding, codebookType);
else
    catalog = sixgr.phy.ul.puschCodebookCatalog(nLayers, nPorts, transformPrecoding);
end
if ~logical(catalog.Valid)
    if catalog.Reason == "missing_eight_port_codebook_type"
        error("sixgr:phy:ul:PUSCHCodebookProjection:MissingCodebookType", ...
            "Eight-port projection requires the actual explicit CodebookType.");
    end
    error("sixgr:phy:ul:PUSCHCodebookProjection:UnsupportedCombination", ...
        "Unsupported PUSCH codebook combination: ports=%d layers=%d (%s).", ...
        nPorts, nLayers, char(string(catalog.Reason)));
end
transformPrecoding = catalog.TransformPrecoding;
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
    if catalog.CodebookTypeApplicable
        Wtx = nrPUSCHCodebook(nLayers, nPorts, tpmi, transformPrecoding, ...
            char(catalog.EffectiveCodebookType));
    else
        % Preserve the existing one/two/four-port numerical path exactly.
        Wtx = nrPUSCHCodebook(nLayers, nPorts, tpmi, transformPrecoding);
    end
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
if catalog.CodebookTypeApplicable
    status = string(status) + "_" + catalog.EffectiveCodebookType;
end
end

function tf = localInteger(value, minimum)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= minimum && value == fix(value);
end
