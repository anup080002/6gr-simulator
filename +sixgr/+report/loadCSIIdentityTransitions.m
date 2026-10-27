function T=loadCSIIdentityTransitions(runFolder,installations,access)
% Original received identity bridge. Never rename a pre-access measurement.
% Scope comes from this run's persisted execution identity, not current cfg.
if nargin<2, installations=readOptional(runFolder,'radio_identity_installations.csv'); end
if nargin<3, access=readOptional(runFolder,'prach_trials.csv'); end
T=table();
if isempty(installations)||isempty(access), return; end
identityPath=fullfile(runFolder,'meta','execution_identity.json');
if ~isfile(identityPath), return; end
identity=jsondecode(fileread(identityPath));
for f=["RunID","ExecutionID","ConfigHash"]
    assert(isfield(identity,f)&&strlength(string(identity.(f)))>0, ...
        'sixgr:report:CSIIdentityTransitionScope','Original execution identity is incomplete.');
end
if isstruct(installations), installations=struct2table(installations); end
for k=1:height(installations)
    i=table2struct(installations(k,:));
    req={'UEIndex','ServingCell','RNTI','ConfiguredRNTI','Msg4CanonicalSlot', ...
        'Source','EncodingProfile','MACRRCStandardsQualified','EvidenceSHA256','InstalledAtCanonicalSlot'};
    assert(all(isfield(i,req)),'sixgr:report:CSIIdentityTransitionScope','Incomplete installation record.');
    original=struct('UEIndex',double(i.UEIndex),'ServingCell',double(i.ServingCell), ...
        'RNTI',double(i.RNTI),'ConfiguredRNTI',double(i.ConfiguredRNTI), ...
        'Msg4CanonicalSlot',double(i.Msg4CanonicalSlot),'Source',string(i.Source), ...
        'EncodingProfile',string(i.EncodingProfile),'MACRRCStandardsQualified',logical(i.MACRRCStandardsQualified));
    assert(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(original),'UTF-8')))==string(i.EvidenceSHA256), ...
        'sixgr:report:CSIIdentityTransitionScope','Original received installation digest differs.');
    assert(string(i.Source)=="decoded_msg4_payload_after_contention_match" && ...
        string(i.EncodingProfile)=="legacy_bounded_not_NR_MAC_RRC" && ...
        ~logical(i.MACRRCStandardsQualified),'sixgr:report:CSIIdentityTransitionScope', ...
        'Only the retained supported received installation can bridge identity.');
    hit=find(access.UEIndex==i.UEIndex & access.ServingCell==i.ServingCell & ...
        access.FinalCRNTI==i.RNTI & access.TemporaryCRNTI==i.RNTI);
    assert(isscalar(hit),'sixgr:report:CSIIdentityTransitionScope','Require one original decoded RA result.');
    a=table2struct(access(hit,:));
    flags=["RACompleted","RAPIDMatches","Msg2DCICrcPass","Msg2PDSCHCrcPass", ...
        "RARULGrantValid","Msg3PUSCHCrcPass","Msg4PDCCHCrcPass","Msg4PDSCHCrcPass", ...
        "ContentionIdentityMatches"];
    for f=flags
        assert(isfield(a,f)&&isequal(double(a.(f)),1),'sixgr:report:CSIIdentityTransitionScope', ...
            'An unaccepted original RA result cannot bridge identity.');
    end
    assert(string(a.FinalCRNTISource)==string(i.Source) && ...
        string(a.FinalCRNTIEncodingProfile)==string(i.EncodingProfile), ...
        'sixgr:report:CSIIdentityTransitionScope','Received source/profile differs.');
    base=string(a.RASlotTimeBase);
    assert(any(base==["absolute_zero_based","absolute_one_based"]), ...
        'sixgr:report:CSIIdentityTransitionScope','Retain explicit RA clock base.');
    msg4=double(a.Msg4ScheduledSlot)+double(base=="absolute_zero_based");
    assert(msg4==i.Msg4CanonicalSlot && msg4<=i.InstalledAtCanonicalSlot, ...
        'sixgr:report:CSIIdentityTransitionScope','Received Msg4 is not available at installation.');
    if isfield(a,'RequireRRCSetupComplete')&&a.RequireRRCSetupComplete
        for f=["RRCSetupRequestDecoded","RRCSetupDecoded","SRB1Installed", ...
                "RRCSetupCompleteCRC","RRCSetupCompleteDecoded","RRCConnected"]
            assert(isfield(a,f)&&isequal(double(a.(f)),1),'sixgr:report:CSIIdentityTransitionScope', ...
                'Required RRC receive completion is absent.');
        end
        assert(double(a.SetupCompleteScheduledSlot)+double(base=="absolute_zero_based")<=i.InstalledAtCanonicalSlot && ...
            strlength(string(a.RRCSetupCompletePayloadSHA256))==64, ...
            'sixgr:report:CSIIdentityTransitionScope','RRC receive clock/hash unavailable.');
    end
    for f=["RunID","ExecutionID","ConfigHash"]
        assert(isfield(a,f)&&string(a.(f))==string(identity.(f)), ...
            'sixgr:report:CSIIdentityTransitionScope','Decoded RA evidence belongs to another execution.');
        i.(f)=string(identity.(f));
    end
    i.DecodedRAEvidenceSHA256=sixgr.util.sha256Hex(string(jsonencode(a)));
    i.TransitionEvidenceRole="received_RA_installation_bridge_not_measurement_relabel";
    T=[T;struct2table(i)]; %#ok<AGROW>
end
end
function T=readOptional(root,name)
p=fullfile(root,'control','csv',name); T=table();
if isfile(p), T=sixgr.util.csvReadTable(p,'TextType','string'); end
end
