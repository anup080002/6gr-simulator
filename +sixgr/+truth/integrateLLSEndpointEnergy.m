function out=integrateLLSEndpointEnergy(T,modelCfg)
%INTEGRATELLSENDPOINTENERGY Integrate disjoint intervals of one endpoint.
% Input rows are NONADDITIVE channel observations of configured power
% models, not circuit-power measurements. Duplicate descriptions of an
% identical state do not add circuit power. Different simultaneous power
% states need joint-state authority; neither sum nor max is an estimator.
arguments
    T table
    modelCfg (1,1) struct = struct()
end
prototype=struct('Entity',"",'EntityID',NaN,'ObservationPopulationKey',"", ...
    'TimestampSim_ms',NaN,'Duration_s',NaN,'Power_W',NaN,'Energy_J',NaN, ...
    'BBProcessingEnergy_J',NaN,'ActivePRBCount',NaN, ...
    'ActiveBWFraction',NaN,'RFChainCount',NaN,'SourceObservationRowsJSON',"", ...
    'SourceDomains',"",'Availability',"",'Status',"", ...
    'EvidenceType',"runtime_state_conditioned_engineering_model");
rows=repmat(prototype,0,1);
if isempty(T), out=struct2table(rows); return; end
needed=["Entity","EntityID","ObservationPopulationKey","TimestampSim_ms", ...
    "Duration_s","Power_W","BBProcessingEnergy_J","Direction","Domain"];
assert(all(ismember(needed,string(T.Properties.VariableNames))), ...
    'sixgr:truth:MissingEndpointEnergyInputs','Endpoint energy needs explicit identity, interval and model power.');
entity=string(T.Entity);
ids=double(T.EntityID);
population=string(T.ObservationPopulationKey);
% Unknown IDs remain unknown in the export. A single undeclared endpoint
% is only grouped within the same explicit population; no cross-run union.
idTokens=string(ids);
idTokens(~isfinite(ids))="<undeclared_endpoint>";
assert(~any(ismissing(entity)) && ~any(ismissing(population)), ...
    'sixgr:truth:MissingEndpointEnergyPopulation','A missing population key cannot identify an execution.');
keys=entity+"|id="+idTokens+"|"+population;
for key=reshape(unique(keys,'stable'),1,[])
    members=find(keys==key);
    starts=double(T.TimestampSim_ms(members))/1000;
    durations=double(T.Duration_s(members));
    assert(all(isfinite(starts)) && all(isfinite(durations)&durations>0), ...
        'sixgr:truth:InvalidEndpointEnergyInterval','Energy intervals must be finite and positive.');
    ends=starts+durations;
    edges=unique([starts;ends]);
    for k=1:numel(edges)-1
        left=edges(k); right=edges(k+1);
        if right<=left, continue; end
        active=members(starts<right & ends>left);
        if isempty(active), continue; end
        power=double(T.Power_W(active));
        bbPower=double(T.BBProcessingEnergy_J(active))./double(T.Duration_s(active));
        directions=unique(upper(string(T.Direction(active))));
        row=prototype;
        row.Entity=entity(members(1));
        row.EntityID=ids(members(1));
        row.ObservationPopulationKey=population(members(1));
        row.TimestampSim_ms=left*1000;
        row.Duration_s=right-left;
        row.SourceObservationRowsJSON=string(jsonencode(active(:).'));
        row.SourceDomains=strjoin(unique(string(T.Domain(active)),'stable'),"|");
        samePower=all(isfinite(power)) && all(isfinite(bbPower)) && ...
            all(abs(power-power(1))<=16*eps(max(1,abs(power(1))))) && ...
            all(abs(bbPower-bbPower(1))<=16*eps(max(1,abs(bbPower(1)))));
        [joint,jointStatus]=localJointState(T(active,:),modelCfg);
        if ~isempty(joint)
            row.Power_W=joint.totalW;
            row.Energy_J=joint.totalW*row.Duration_s;
            row.BBProcessingEnergy_J=joint.trxW*row.Duration_s;
            row.ActivePRBCount=joint.PRBS;
            row.ActiveBWFraction=joint.load;
            row.RFChainCount=joint.nTRxP;
            row.Availability="AVAILABLE";
            row.Status=jointStatus;
        elseif any(~isfinite(power)) || any(~isfinite(bbPower))
            row.Availability="NOT_EVALUATED";
            row.Status="missing_endpoint_power_model_inputs";
        elseif samePower && numel(directions)==1 && ...
                (numel(active)==1 || localSameDeclaredState(T(active,:)))
            row.Power_W=power(1);
            row.Energy_J=power(1)*row.Duration_s;
            row.BBProcessingEnergy_J=bbPower(1)*row.Duration_s;
            row.Availability="AVAILABLE";
            row.Status="identical_endpoint_model_state_integrated_once";
        else
            row.Availability="NOT_EVALUATED";
            row.Status="joint_endpoint_power_state_required_for_nonidentical_overlap";
            if samePower && numel(directions)==1
                row.Status="equal_power_does_not_establish_joint_endpoint_state";
            end
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end
out=struct2table(rows);
end

function tf=localSameDeclaredState(T)
% A separately declared whole-endpoint state can be described more than
% once. Equality of channel-attribution watts alone is NOT such authority.
tf=false;
if ~ismember('EndpointPowerStateID',T.Properties.VariableNames), return; end
ids=string(T.EndpointPowerStateID);
tf=all(~ismissing(ids)&strlength(strtrim(ids))>0) && all(ids==ids(1));
end

function [power,status]=localJointState(T,cfg)
% Evaluate the declared site model once for the union of actual occupied
% PRBs. PA input is the explicitly declared ENDPOINT budget, not the sum
% of identical per-channel copies. No physical RF watts are inferred from
% normalized IQ. Missing operands retain the strict legacy boundary.
power=[]; status="";
if all(string(T.Entity)=="UE")
    [power,status]=localJointUEState(T,cfg);
    return;
end
needed={'ResourcePRBSetJSON','ResourceGridPRBCount','RFChainCount','EndpointModelTxPower_W'};
if ~all(string(T.Entity)=="gNB") || numel(unique(string(T.Direction)))~=1 || ...
        ~all(ismember(needed,T.Properties.VariableNames)) || isempty(fieldnames(cfg))
    return;
end
raw=string(T.ResourcePRBSetJSON);
if any(ismissing(raw)|strlength(strtrim(raw))==0), return; end
grid=double(T.ResourceGridPRBCount); chains=double(T.RFChainCount);
budget=double(T.EndpointModelTxPower_W);
if ~all(isfinite(grid)&grid>0&grid==fix(grid)) || ~all(grid==grid(1)) || ...
        ~all(isfinite(chains)&chains>0&chains==fix(chains)) || ~all(chains==chains(1)) || ...
        ~all(isfinite(budget)&budget>=0) || ~all(budget==budget(1))
    return;
end
fields=["staticW","perTRxPW","sleepW","efficiencyPA","idleRFChainPowerFraction"];
for field=fields
    v=sixgr.util.structGet(cfg,"energy.bs."+field,NaN);
    assert(isnumeric(v)&&isscalar(v)&&isfinite(v)&&v>=0, ...
        'sixgr:truth:MissingExplicitJointEnergyModel', ...
        'Every joint circuit-model operand must be explicitly declared and finite.');
end
eff=cfg.energy.bs.efficiencyPA;
assert(eff>0 && eff<=1,'sixgr:truth:InvalidJointEnergyPAEfficiency', ...
    'Do not silently clamp a declared PA efficiency in joint accounting.');
occupied=[];
model=sixgr.rf.EnergyModelBS(cfg);
for k=1:numel(raw)
    prbs=jsondecode(raw(k));
    validateattributes(prbs,{'numeric'},{'vector','nonempty','finite','integer','nonnegative','<',grid(1)});
    assert(numel(unique(prbs))==numel(prbs),'sixgr:truth:DuplicateJointEnergyPRB', ...
        'A mapped PRB set cannot repeat physical resources.');
    expected=model.power('active',chains(k),numel(prbs)/grid(k),budget(k));
    assert(isfinite(T.Power_W(k)) && ...
        abs(T.Power_W(k)-expected.totalW)<=32*eps(max(1,abs(expected.totalW))) && ...
        abs(T.BBProcessingEnergy_J(k)/T.Duration_s(k)-expected.trxW)<=32*eps(max(1,abs(expected.trxW))), ...
        'sixgr:truth:EnergyModelOperandMismatch', ...
        'Per-observation model power must agree with its retained resource and endpoint inputs.');
    occupied=union(occupied,double(prbs(:).'));
end
power=model.power('active',chains(1),numel(occupied)/grid(1),budget(1));
power.PRBS=numel(occupied);
status="joint_occupied_PRB_union_endpoint_engineering_model";
end

function [power,status]=localJointUEState(T,cfg)
% The declared UE model is an endpoint-state model (not bandwidth-scaled).
% Multiple received channels share one RX circuit state. Simultaneous UL
% signals use one explicitly declared endpoint RF budget, not its sum.
power=[]; status="";
needed={'RFChainCount','EndpointModelTxPower_W','State'};
if numel(unique(string(T.Direction)))~=1 || isempty(fieldnames(cfg)) || ...
        ~all(ismember(needed,T.Properties.VariableNames)), return; end
chains=double(T.RFChainCount); budget=double(T.EndpointModelTxPower_W);
if ~all(isfinite(chains)&chains>0&chains==fix(chains)) || ~all(chains==chains(1)) || ...
        ~all(isfinite(budget)&budget>=0) || ~all(budget==budget(1)), return; end
for field=["idleW","rxW","sleepW","txWPerWattRF"]
    v=sixgr.util.structGet(cfg,"energy.ue."+field,NaN);
    assert(isnumeric(v)&&isscalar(v)&&isfinite(v)&&v>=0, ...
        'sixgr:truth:MissingExplicitJointEnergyModel','UE circuit terms must be explicitly configured.');
end
if all(string(T.Direction)=="DL")
    assert(all(ismember(string(T.State),["active_rx","monitor_only"])) && all(budget==0), ...
        'sixgr:truth:InvalidJointUEState','DL receive-state accounting cannot consume a UE TX budget.');
    state='rx'; status="joint_endpoint_RX_circuit_engineering_model";
else
    assert(all(string(T.Direction)=="UL") && all(string(T.State)=="active_tx"), ...
        'sixgr:truth:InvalidJointUEState','UL accounting requires the declared UE transmit state.');
    state='tx'; status="joint_endpoint_TX_budget_engineering_model";
end
model=sixgr.rf.EnergyModelUE(cfg); expected=model.power(state,budget(1));
assert(all(isfinite(T.Power_W)) && ...
    all(abs(T.Power_W-expected.totalW)<=32*eps(max(1,abs(expected.totalW)))) && ...
    all(T.BBProcessingEnergy_J==0), ...
    'sixgr:truth:EnergyModelOperandMismatch','UE channel attribution must match its explicit endpoint state model.');
power=struct('totalW',expected.totalW,'trxW',0,'PRBS',NaN,'load',NaN,'nTRxP',chains(1));
end
