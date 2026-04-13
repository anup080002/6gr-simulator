function walkStruct(s,prefix)
if nargin<2, prefix=''; end
if isstruct(s)
  f=fieldnames(s);
  for i=1:numel(f)
    key=f{i};
    if strlength(prefix)==0
      path=string(key);
    else
      path=prefix+"."+string(key);
    end
    val=s.(key);
    if isstruct(val)
      walkStruct(val,path);
    else
      disp(path)
    end
  end
end
end
setup6GRSimToolkit('Verbose',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs','scenarios','lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempname,'run'));
walkStruct(cfg,'');
