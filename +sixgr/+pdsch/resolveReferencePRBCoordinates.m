function coordinates = resolveReferencePRBCoordinates(assignment,carrier,pdsch)
%RESOLVEREFERENCEPRBCOORDINATES Separate carrier grid and RS sequence origins.
% TS 38.211 V18.8.0 7.4.1.1.2: CRB0 normally, the CORESET0 reference
% under the applicable Type0/SI-RNTI procedure. Native PRB0 models the
% latter using a BWP aligned with CORESET0. This PHY adapter validates
% coordinates, not that a connected control procedure authorizes PRB0.
arguments
    assignment (1,1) sixgr.pdsch.PDSCHSchedulingAssignment
    carrier (1,1) nrCarrierConfig
    pdsch (1,1) nrPDSCHConfig
end
carrierPRBs = double(assignment.get("PRBSetCarrierRelative"));
carrierPRBs = carrierPRBs(:).';
start = double(pdsch.NStartBWP);
width = double(pdsch.NSizeBWP);
if isempty(start), start = double(carrier.NStartGrid); end
if isempty(width), width = double(carrier.NSizeGrid); end
delta = start-double(carrier.NStartGrid);
nativePRBs = double(pdsch.PRBSet(:).');
assert(isequal(nativePRBs+delta,carrierPRBs) ...
    && all(nativePRBs>=0 & nativePRBs<width) ...
    && all(carrierPRBs>=0 & carrierPRBs<double(carrier.NSizeGrid)), ...
    "sixgr:pdsch:ReferencePRBCoordinateMismatch", ...
    "Native BWP-relative PRBs do not identify the original carrier-relative assignment.");
point = string(pdsch.DMRS.DMRSReferencePoint);
if point == "CRB0"
    offset = double(carrier.NStartGrid);
elseif point == "PRB0"
    % A PRB0 sequence must use the actual original BWP, not merely the
    % materializer's carrier-wide default when assignment aliases differ.
    bwpPRBs=double(assignment.get("PRBSetBWPRelative"));
    assert(isequal(nativePRBs,bwpPRBs(:).'), ...
        "sixgr:pdsch:ReferencePRBCoordinateMismatch", ...
        "PRB0 requires the original BWP-relative assignment and BWP origin.");
    offset = -delta;
else
    error("sixgr:pdsch:InvalidDMRSReferencePoint", ...
        "DMRSReferencePoint must be CRB0 or PRB0.");
end
coordinates = struct("ContractVersion","PDSCHReferencePRBCoordinates/v1", ...
    "DMRSReferencePoint",point,"CarrierStartCRB",double(carrier.NStartGrid), ...
    "NativeBWPStartCRB",start,"NativeBWPNumPRB",width, ...
    "PRBSetCarrierRelative",carrierPRBs,"ReferenceRBOffset",offset, ...
    "PRBSetReferenceRelative",carrierPRBs+offset, ...
    "ControlProcedureQualified",false);
end
