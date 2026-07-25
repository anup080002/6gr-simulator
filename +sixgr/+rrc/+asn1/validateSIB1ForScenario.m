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
for name = ["downlinkConfigCommon","uplinkConfigCommon","ssb_PositionsInBurst","ssb_periodicityServingCell","dmrs_TypeA_Position"]
    if ~isfield(serving, name)
        error("sixgr:rrc:asn1:MissingSIB1IE", "Required servingCellConfigCommon IE '%s' is missing.", name);
    end
end
pdcchSIB1 = serving.downlinkConfigCommon.initialDownlinkBWP.pdcch_ConfigCommon.pdcch_ConfigSIB1;
coreset0 = double(pdcchSIB1.controlResourceSetZero);
search0 = double(pdcchSIB1.searchSpaceZero);
if ~(isfinite(coreset0) && coreset0 >= 0 && coreset0 <= 15 && isfinite(search0) && search0 >= 0 && search0 <= 15)
    error("sixgr:rrc:asn1:UnsupportedSIB1IE", ...
        "Anchor SIB1 profile supports CORESET0/searchSpaceZero indices in [0,15].");
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
