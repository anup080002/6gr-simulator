function [distance_m, displacement_m] = hexClusterMinImageDistance( ...
    pointPos_m, sitePos_m, translationVectors_m, varargin)
%HEXCLUSTERMINIMAGEDISTANCE Minimum-image distance on a finite hex cluster.
%
% translationVectors_m is the 2x2 cluster translation basis returned by
% buildHexWraparoundTopology. It must not be the primitive one-site basis
% for a multi-site deployment.

ip = inputParser;
ip.addParameter("ImageRadius", 2, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
ip.parse(varargin{:});
imageRadius = round(double(ip.Results.ImageRadius));

validateattributes(pointPos_m, {'numeric'}, {'2d','nonempty'}, ...
    mfilename, 'pointPos_m', 1);
validateattributes(sitePos_m, {'numeric'}, {'2d','nonempty'}, ...
    mfilename, 'sitePos_m', 2);
validateattributes(translationVectors_m, {'numeric'}, ...
    {'size',[2 2],'finite'}, mfilename, 'translationVectors_m', 3);
if size(pointPos_m,2) < 2 || size(sitePos_m,2) < 2
    error("sixgr:ran1ai1032:InvalidGeometryDimension", ...
        "Point and site positions require at least x/y columns.");
end

basis = double(translationVectors_m);
if abs(det(basis)) <= eps(max(abs(basis), [], "all"))^2
    error("sixgr:ran1ai1032:SingularWraparoundBasis", ...
        "The finite-cluster wrap-around basis must be nonsingular.");
end
[distance_m, displacement_m] = sixgr.scenario.wraparoundDistance( ...
    double(pointPos_m), double(sitePos_m), [1 1], ...
    "Mode", "hex_cluster_min_image", ...
    "TranslationVectors_m", basis, "ImageRadius", imageRadius);
end
