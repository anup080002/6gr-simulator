function validateSIB1ForScenario(msg, cfg)
%VALIDATESIB1FORSCENARIO Fail closed outside the supported SIB1 profile.

if nargin < 2
    cfg = struct(); %#ok<NASGU>
end
if ~(isstruct(msg) && isfield(msg, "message") && isfield(msg.message, "c1") && ...
        isfield(msg.message.c1, "systemInformationBlockType1"))
    error("sixgr:rrc:asn1:UnsupportedSIB1IE", ...
        "SIB1 must be BCCH-DL-SCH-Message.message.c1.systemInformationBlockType1.");
end
sib1 = msg.message.c1.systemInformationBlockType1;
required = ["cellSelectionInfo","cellAccessRelatedInfo","si_SchedulingInfo","servingCellConfigCommon"];
for i = 1:numel(required)
    if ~isfield(sib1, required(i))
        error("sixgr:rrc:asn1:MissingSIB1IE", "Required SIB1 IE '%s' is missing.", required(i));
    end
end
serving = sib1.servingCellConfigCommon;
if isfield(serving,'n_TimingAdvanceOffset')
    value=string(serving.n_TimingAdvanceOffset);
    if ~isscalar(value) || ~any(value==["n0","n25600","n39936"])
        error('sixgr:rrc:asn1:UnsupportedSIB1IE', ...
            'n-TimingAdvanceOffset must be n0, n25600 or n39936; omit the IE for its standards default.');
    end
end
for name = ["downlinkConfigCommon","uplinkConfigCommon","ssb_PositionsInBurst","ssb_periodicityServingCell"]
    if ~isfield(serving, name)
        error("sixgr:rrc:asn1:MissingSIB1IE", "Required servingCellConfigCommon IE '%s' is missing.", name);
    end
end
% PDCCH-ConfigCommon is optional; its constraints are checked by the actual
% generated ASN.1 encoder. Do not require an invented MIB pdcch-ConfigSIB1.
for direction = ["downlink", "uplink"]
    if direction == "downlink", bwpName = "initialDownlinkBWP";
    else, bwpName = "initialUplinkBWP"; end
    bwp = serving.(direction + "ConfigCommon").(bwpName);
    riv = double(bwp.genericParameters.locationAndBandwidth);
    [startRB, sizeRB] = sixgr.bwop.RIVFDRA.decode(275, riv);
    if sixgr.bwop.RIVFDRA.encode(275, startRB, sizeRB) ~= riv
        error("sixgr:rrc:asn1:InvalidBWPAllocation", "Noncanonical initial BWP RIV.");
    end
    for unsupported = ["pdsch_ConfigCommon", "pusch_ConfigCommon", "pucch_ConfigCommon"]
        if isfield(bwp, unsupported)
            error("sixgr:rrc:asn1:UnsupportedSIB1IE", ...
                "%s is not encoded by the bounded SIB1 profile.", unsupported);
        end
    end
end
prach = serving.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
if isfield(prach, "restrictedSet") && ~any(strcmpi(string(prach.restrictedSet), ...
        ["unrestricted","UnrestrictedSet","false","0","", ...
        "RestrictedSetTypeA","RestrictedSetTypeB"]))
    error("sixgr:rrc:asn1:UnsupportedSIB1IE", ...
        "SIB1 restrictedSet must be unrestricted, Type A, or Type B.");
end
if ~isfield(sib1, "ue_TimersAndConstants")
    error("sixgr:rrc:asn1:MissingSIB1IE", ...
        "Release-18 bounded SIB1 requires ue-TimersAndConstants.");
end
end
