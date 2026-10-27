function p=resolveNRAccessPolicy(n)
% Explicit access wire profile and upper-layer inputs. NAS bytes are opaque.
assert(isstruct(n)&&isscalar(n),'sixgr:rrc:InvalidAccessPolicy','RRC access policy must be scalar.');
p=struct('EncodingProfile',string(sixgr.util.structGet(n,'encoding_profile', ...
    "legacy_bounded_not_NR_MAC_RRC")),'Enabled',false);
assert(isscalar(p.EncodingProfile)&&ismember(p.EncodingProfile, ...
    ["legacy_bounded_not_NR_MAC_RRC","nr_rrc_access_base_srb1_uper_v1"]), ...
    'sixgr:rrc:InvalidAccessPolicy','Unsupported access encoding profile.');
p.Enabled=p.EncodingProfile=="nr_rrc_access_base_srb1_uper_v1";
if ~p.Enabled,return;end
required=["require_setup_complete","transaction_id","srb1_lcid", ...
    "establishment_cause","selected_plmn_identity","dedicated_nas_hex"];
assert(all(isfield(n,required))&&isequal(n.require_setup_complete,true)&&isequal(n.srb1_lcid,1), ...
    'sixgr:rrc:InvalidAccessPolicy','Supported NR access requires explicit SRB1/setup and upper-layer inputs.');
validateattributes(n.transaction_id,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',3});
validateattributes(n.selected_plmn_identity,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',12});
p.TransactionID=double(n.transaction_id);
p.SRB1LCID=double(n.srb1_lcid);
p.EstablishmentCause=string(n.establishment_cause);
assert(isscalar(p.EstablishmentCause)&&ismember(p.EstablishmentCause, ...
    ["emergency","highPriorityAccess","mt-Access","mo-Signalling","mo-Data", ...
    "mo-VoiceCall","mo-VideoCall","mo-SMS","mps-PriorityAccess","mcs-PriorityAccess"]), ...
    'sixgr:rrc:InvalidAccessPolicy','Use a supported TS38.331 establishmentCause.');
p.SelectedPLMNIdentity=double(n.selected_plmn_identity);
p.DedicatedNASHex=upper(string(n.dedicated_nas_hex));
assert(isscalar(p.DedicatedNASHex)&&~isempty(regexp(char(p.DedicatedNASHex),'^([0-9A-F]{2})+$','once')), ...
    'sixgr:rrc:InvalidAccessPolicy','Provide nonempty original upper-layer NAS octets as hexadecimal.');
p.NASSource="explicit_upper_layer_octets_not_NAS_network_execution";
p.RequireReceivedSetupCompleteGrant=true;
p.DefaultSRB1Reference="TS38.331_V18.8.0_9.2.1";
end
