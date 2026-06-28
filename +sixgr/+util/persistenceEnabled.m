function tf = persistenceEnabled()
%PERSISTENCEENABLED True when CSV/DB artifact publication is enabled.

disabled = lower(strtrim(string(getenv("SIXGR_DISABLE_PERSISTENCE"))));
coreOnly = lower(strtrim(string(getenv("SIXGR_CORE_ONLY"))));
enabledOverride = lower(strtrim(string(getenv("SIXGR_PERSISTENCE_ENABLED"))));

tf = true;
if any(disabled == ["1","true","yes","on"]) || any(coreOnly == ["1","true","yes","on"])
    tf = false;
end
if any(enabledOverride == ["0","false","no","off"])
    tf = false;
elseif any(enabledOverride == ["1","true","yes","on"])
    tf = true;
end
end
