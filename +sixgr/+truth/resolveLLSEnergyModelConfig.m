function resolved = resolveLLSEnergyModelConfig(cfg, options)
%RESOLVELLSENERGYMODELCONFIG Resolve an explicit, config-owned energy model.
%
% The LLS energy exporter must not inherit MATLAB class defaults.  Every
% parameter below is an engineering-model input and therefore has to be
% present in the resolved YAML configuration (or in an explicitly mapped
% legacy field).  Missing inputs make energy evidence unavailable instead
% of silently changing the model.

arguments
    cfg (1,1) struct
    options.RFInventoryPolicy (1,1) string {mustBeMember(options.RFInventoryPolicy, ...
        ["require_match","bind_declared_inventory"])} = "require_match"
end

spec = [ ...
    localSpec("BSStaticPower_W", "energy.bs.staticW", ...
        ["lls6g.energy_efficiency.bs_static_power_w"], "W", @(x)x >= 0); ...
    localSpec("BSPerRFChainPower_W", "energy.bs.perTRxPW", ...
        ["lls6g.energy_efficiency.bs_per_rf_chain_power_w", ...
         "lls6g.energy_efficiency.per_rf_chain_power_w"], "W/chain", @(x)x >= 0); ...
    localSpec("BSRFChainIdlePowerFraction", "energy.bs.idleRFChainPowerFraction", ...
        ["lls6g.energy_efficiency.bs_rf_chain_idle_power_fraction"], "fraction", @(x)x >= 0 && x <= 1); ...
    localSpec("BSSleepPower_W", "energy.bs.sleepW", ...
        ["lls6g.energy_efficiency.bs_sleep_power_w"], "W", @(x)x >= 0); ...
    localSpec("BSPAEfficiency", "energy.bs.efficiencyPA", ...
        ["lls6g.energy_efficiency.bs_pa_efficiency", ...
         "lls6g.energy_efficiency.pa_efficiency"], "fraction", @(x)x > 0 && x <= 1); ...
    localSpec("UEIdlePower_W", "energy.ue.idleW", ...
        ["lls6g.energy_efficiency.ue_idle_power_w"], "W", @(x)x >= 0); ...
    localSpec("UERxPower_W", "energy.ue.rxW", ...
        ["lls6g.energy_efficiency.ue_rx_power_w"], "W", @(x)x >= 0); ...
    localSpec("UESleepPower_W", "energy.ue.sleepW", ...
        ["lls6g.energy_efficiency.ue_sleep_power_w"], "W", @(x)x >= 0); ...
    localSpec("UETxDCPerWattRF", "energy.ue.txWPerWattRF", ...
        ["lls6g.energy_efficiency.ue_tx_dc_per_watt_rf"], "W/W", @(x)x > 0); ...
    localSpec("BSTxPower_dBm", "powerAndRF.bsTxPower_dBm", ...
        ["lls6g.energy_efficiency.bs_tx_power_dbm", ...
         "lls6g.energy_efficiency.tx_power_dbm", ...
         "scenario.bs.txPower_dBm"], "dBm", @(x)isfinite(x)); ...
    localSpec("UETxPower_dBm", "powerAndRF.ueTxPower_dBm", ...
        ["lls6g.energy_efficiency.ue_tx_power_dbm", ...
         "phy.pusch.powerControl.pcmax_dBm"], "dBm", @(x)isfinite(x)); ...
    localSpec("BSRFChainCount", "powerAndRF.bsRFChainCount", ...
        ["lls6g.energy_efficiency.bs_rf_chain_count", ...
         "lls6g.energy_efficiency.rf_chain_count"], "count", @(x)x >= 1 && x == fix(x)); ...
    localSpec("UERFChainCount", "powerAndRF.ueRFChainCount", ...
        ["lls6g.energy_efficiency.ue_rf_chain_count"], "count", @(x)x >= 1 && x == fix(x))];

modelCfg = cfg;
inventorySource=string(sixgr.util.structGet(cfg, ...
    'lls6g.energy_efficiency.rf_inventory_source','explicit_energy_counts'));
assert(isscalar(inventorySource)&&any(inventorySource== ...
    ["explicit_energy_counts","declared_endpoint_inventory"]), ...
    'sixgr:truth:InvalidEnergyRFInventorySource','Select a declared RF inventory source.');
operatingPolicy=string(sixgr.util.structGet(cfg, ...
    'lls6g.energy_efficiency.operating_state_policy','represented_intervals'));
assert(isscalar(operatingPolicy)&&any(operatingPolicy==["represented_intervals","always_awake"]), ...
    'sixgr:truth:InvalidEnergyOperatingPolicy','Select an explicit supported energy operating-state policy.');
if operatingPolicy=="always_awake"
    sixgr.lls6g.config.validateEnergyOperatingPolicy(cfg.lls6g);
end
rows = repmat(localEmptyRow(), numel(spec), 1);
missing = strings(0,1);
for i = 1:numel(spec)
    % Only scenario-resolved aliases are accepted as authority. The
    % canonical energy.* fields exist in defaultConfig and therefore cannot
    % prove that an operator/YAML selected the value.
    paths = string(spec(i).Aliases);
    [value, source] = localFirstExplicitScalar(cfg, paths);
    configuredValue = value;
    valid = isfinite(value) && spec(i).Validator(value);
    inventoryNote = "";
    effectiveInventoryPolicy=options.RFInventoryPolicy;
    if any(spec(i).Name==["BSRFChainCount","UERFChainCount"])
        [inventoryValid,inventoryNote,installed,declaredPool] = localValidateRFInventory( ...
            cfg,spec(i).Name,value);
        if inventorySource=="declared_endpoint_inventory"
            % A YAML-selected runtime authority, not a post-hoc reporting
            % correction. An absent/contradictory endpoint inventory cannot
            % silently fall back to a count or an antenna-element number.
            effectiveInventoryPolicy="yaml_declared_endpoint_inventory";
            value=installed;
            valid=declaredPool && isfinite(value) && spec(i).Validator(value);
            [inventoryValid,inventoryNote]=localValidateRFInventory(cfg,spec(i).Name,value);
            if ~declaredPool
                inventoryNote="configured_inventory_binding_requires_explicit_common_RF_pool_not_max_direction_count";
            end
            source="lls6g.energy_efficiency.rf_inventory_source:declared_endpoint_inventory";
        elseif valid && ~inventoryValid && isfinite(installed) && ...
                options.RFInventoryPolicy=="bind_declared_inventory"
            % Reporting-only corrected model; never modify the run's
            % frozen physical config or infer RF units from element count.
            value=installed;
            [inventoryValid,inventoryNote]=localValidateRFInventory( ...
                cfg,spec(i).Name,value);
            inventoryNote="Explicit_report_model_binding;_original_energy_count="+ ...
                string(configuredValue)+";_declared_RF_inventory="+string(value)+ ...
                "; "+inventoryNote;
        end
        valid = valid && inventoryValid;
    end
    if ~valid
        missing(end+1,1) = string(spec(i).Name); %#ok<AGROW>
    else
        modelCfg = sixgr.util.structSet(modelCfg, spec(i).CanonicalPath, value);
    end
    rows(i) = struct( ...
        "Term", string(spec(i).Name), ...
        "CanonicalPath", string(spec(i).CanonicalPath), ...
        "ConfiguredSourcePath", string(source), ...
        "Value", double(value), ...
        "ConfiguredValue", double(configuredValue), ...
        "RFInventoryPolicy", effectiveInventoryPolicy, ...
        "Unit", string(spec(i).Unit), ...
        "Availability", localAvailability(valid), ...
        "ModelVersion", "lls_energy_accounting_v4", ...
        "Notes", strtrim(localTermNotes(valid) + " " + inventoryNote));
end

resolved = struct();
resolved.Available = isempty(missing);
resolved.MissingTerms = missing;
resolved.ModelConfig = modelCfg;
resolved.TermTable = struct2table(rows);
resolved.ModelVersion = "lls_energy_accounting_v4";
resolved.OperatingStatePolicy=operatingPolicy;
resolved.RFInventorySource=inventorySource;
if resolved.Available
    resolved.FailureReason = "";
else
    resolved.FailureReason = "missing_or_invalid_explicit_energy_terms:" + strjoin(missing, ",");
end
end

function [valid,note,installed,declaredPool]=localValidateRFInventory(cfg,term,count)
% The energy model counts RF units, never antenna elements, logical ports
% or data layers. A declared common RF pool can support fewer chains in one
% direction, but it cannot be smaller than either directional inventory.
endpoint="bs";
if term=="UERFChainCount", endpoint="ue"; end
groups={["antenna."+endpoint+".numRFChains", ...
         "scenario."+endpoint+".numRFChains","rf."+endpoint+".numRFChains"], ...
        ["antenna."+endpoint+".numTxRFChains","scenario."+endpoint+".numTxRFChains"], ...
        ["antenna."+endpoint+".numRxRFChains","scenario."+endpoint+".numRxRFChains"]};
counts=NaN(1,numel(groups));
valid=true; note=""; installed=NaN; declaredPool=false;
for k=1:numel(groups)
    for path=groups{k}
        raw=sixgr.util.structGet(cfg,path,[]);
        if isempty(raw), continue; end
        if ~(isnumeric(raw)&&isreal(raw)&&isscalar(raw)&& ...
                isfinite(raw)&&raw>=1&&raw==fix(raw))
            valid=false;
            note="invalid_RF_inventory:"+path;
            return;
        end
        if isfinite(counts(k)) && counts(k)~=double(raw)
            valid=false;
            note="contradictory_RF_inventory_aliases:"+endpoint;
            return;
        end
        counts(k)=double(raw);
    end
end
directions=counts(2:3);
directions=directions(isfinite(directions));
installed=counts(1);
declaredPool=isfinite(installed);
if ~isfinite(installed) && ~isempty(directions)
    installed=max(directions);
end
if isfinite(installed)
    valid=count==installed && all(directions<=installed);
    if valid
        note="RF_count_matches_declared_endpoint_inventory_not_element_or_layer_count.";
    else
        note="RF_inventory_mismatch:"+endpoint+":energy_count="+string(count)+ ...
            ":installed_pool="+string(installed);
    end
else
    note="Explicit_energy_RF_count_only;_no_independent_endpoint_inventory_declared.";
end
end

function item = localSpec(name, canonicalPath, aliases, unit, validator)
item = struct("Name", string(name), "CanonicalPath", string(canonicalPath), ...
    "Aliases", string(aliases), "Unit", string(unit), "Validator", validator);
end

function [value, source] = localFirstExplicitScalar(cfg, paths)
value = NaN;
source = "";
for path = reshape(string(paths), 1, [])
    raw = sixgr.util.structGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    if islogical(raw)
        raw = double(raw);
    elseif ~isnumeric(raw)
        raw = str2double(string(raw));
    end
    raw = double(raw(:));
    if numel(raw) == 1 && isfinite(raw)
        value = raw;
        source = path;
        return;
    end
end
end

function row = localEmptyRow()
row = struct("Term", "", "CanonicalPath", "", ...
    "ConfiguredSourcePath", "", "Value", NaN, "ConfiguredValue", NaN, ...
    "RFInventoryPolicy", "", "Unit", "", ...
    "Availability", "NOT_EVALUATED", "ModelVersion", "", "Notes", "");
end

function value = localAvailability(valid)
if valid
    value = "AVAILABLE";
else
    value = "NOT_EVALUATED";
end
end

function value = localTermNotes(valid)
if valid
    value = "Explicit resolved configuration term; no MATLAB default used.";
else
    value = "Required engineering-model term is absent or invalid.";
end
end
