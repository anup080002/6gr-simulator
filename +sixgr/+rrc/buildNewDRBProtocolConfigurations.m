function configs=buildNewDRBProtocolConfigurations(message,scope,coreContext)
% Pure conversion of exact decoded new-bearer operands. No admission/proof.
id='sixgr:rrc:NewDRBInstallation';
assert(isstruct(message)&&isscalar(message)&&all(isfield(message,{'Bytes','SHA256','Semantic','NestedConfiguration'})),id,'Retain original decoded UPER.');
original=sixgr.rrc.asn1.NRAccessMessageCodec.decode('reconfiguration',message.Bytes);
assert(isequaln(message,original),id,'Decoded configuration must match original UPER exactly.');
s=message.Semantic;
assert(message.NestedConfiguration.new_drb_setup_only&&~message.NestedConfiguration.drb_integrity_protection_field_present,id,'Only one new DRB is supported.');
assert(isstruct(scope)&&isscalar(scope)&&all(isfield(scope,{'UEID','ConfigurationEpoch','SampleRateHz','ClockEpoch'})),id,'Original connection scope is required.');
assert(isstruct(coreContext)&&isscalar(coreContext)&&all(isfield(coreContext,{'KeySource','CipherAlgorithm','IntegrityAlgorithm','UEID','ConfigurationEpoch','SampleRateHz','ClockEpoch','CipherKey','IntegrityKey'})),id,'Explicit original core-key context is required.');
assert(string(coreContext.KeySource)=="configured_preestablished_core_key"&&string(coreContext.CipherAlgorithm)=="NEA0"&&string(coreContext.IntegrityAlgorithm)=="128-NIA2",id,'Unsupported core-key boundary.');
for name=["UEID","ConfigurationEpoch","SampleRateHz","ClockEpoch"]
    assert(isequaln(scope.(name),coreContext.(name)),id,'Original connection/core-key scope differs.');
end
assert(isa(coreContext.CipherKey,'uint8')&&isrow(coreContext.CipherKey)&&numel(coreContext.CipherKey)==16&&isa(coreContext.IntegrityKey,'uint8')&&isrow(coreContext.IntegrityKey)&&numel(coreContext.IntegrityKey)==16,id,'Original 128-bit keys are required.');
% Only the current Runtime's actual SDAP implementation is supported here.
assert(string(s.sdap.header_ul)=="present"&&string(s.sdap.header_dl)=="present"&& ...
    islogical(s.sdap.default_drb)&&s.sdap.default_drb&& ...
    islogical(s.pdcp.integrity_protection)&&~s.pdcp.integrity_protection,id, ...
    'Unsupported received SDAP/header/security configuration must fail before endpoint creation.');
% Parse ALL decoded operands and constructor capabilities before mutation.
discard=timer(s.pdcp.discard_timer,true);reordering=timer(s.pdcp.t_reordering,false);
poll=timer(s.rlc_am.t_poll_retransmit,false);reassembly=timer(s.rlc_am.t_reassembly,false);
prohibit=timer(s.rlc_am.t_status_prohibit,false);
pollPDU=number(s.rlc_am.poll_pdu,'p');pollBytes=number(s.rlc_am.poll_byte,'kB')*1000;
maxRetx=number(s.rlc_am.max_retx_threshold,'t');
configs=cell(1,2);directions=["DL","UL"];
for k=1:2
    suffix=lower(directions(k));
    pdcpSN=sn(s.pdcp.("sn_size_"+suffix),'len','bits');
    rlcSN=sn(s.rlc_am.("sn_size_"+suffix),'size','');
    c=struct('UEID',string(scope.UEID),'BearerID',"DRB-"+s.drb_id, ...
        'BearerType',"DRB",'QFI',s.sdap.qfi,'DRBID',s.drb_id,'LCID',s.lcid, ...
        'PduSessionID',s.sdap.pdu_session,'PDCPSNBits',pdcpSN,'RLCSNBits',rlcSN, ...
        'ConfigurationEpoch',scope.ConfigurationEpoch,'Direction',directions(k), ...
        'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"NIA0",'SecurityActive',true, ...
        'CipherKey',coreContext.CipherKey,'IntegrityKey',coreContext.IntegrityKey, ...
        'DiscardTime_s',discard,'ReorderingTime_s',reordering, ...
        'SampleRateHz',scope.SampleRateHz,'ClockEpoch',scope.ClockEpoch, ...
        'RLCARQEnabled',true,'RLCPollRetransmit_s',poll,'RLCReassembly_s',reassembly, ...
        'RLCStatusProhibit_s',prohibit,'PollPDU',pollPDU,'PollByte',pollBytes,'MaxRetxThreshold',maxRetx);
    configs{k}=c;
end
end
function value=timer(name,allowInfinity)
name=string(name);
if allowInfinity&&name=="infinity",value=Inf;return;end
value=number(name,'ms')/1000;
end
function value=number(name,prefix)
match=regexp(char(string(name)),['^' prefix '([0-9]+)$'],'tokens','once');
assert(~isempty(match),'sixgr:rrc:NewDRBInstallation','Unsupported decoded enum: %s.',string(name));
value=str2double(match{1});
end
function value=sn(name,prefix,suffix)
match=regexp(char(string(name)),['^' prefix '(12|18)' suffix '$'],'tokens','once');
assert(~isempty(match),'sixgr:rrc:NewDRBInstallation','Unsupported original SN-size enum.');value=str2double(match{1});
end
