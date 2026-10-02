function ok = testSimulationModeDispatch()
% Front-door dispatch and preservation guards. No unqualified study run.
folder=fullfile(pwd,'logs',['simulation_mode_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
request=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_network_calibrated.yaml');
assert(request.Mode=="SLS" && string(request.Config.run.mode)=="system");
assert(string(request.Config.system.phyBackend)=="calibrated_link_abstraction");
assert(~request.Config.system.linkAbstraction.allowDevelopmentFixtures);
assert(request.Config.outputs.saveCSV && request.Config.outputs.saveFigures);
assert(strcmpi(sixgr.phy.frame.resolveDuplexMode(request.Config),'TDD'));
legacy=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
assert(legacy.Mode=="LLS");
payload=request.Data;
payload.sls.config_files={fullfile(pwd,'simulator','configs','system','calibrated_link_abstraction.yaml')};
beam=[1 1i;-1i 1]/sqrt(2);
payload.sls.config.phy.csirs.precoderMatrices=beam;
file=fullfile(folder,'request.json'); sixgr.util.jsonWrite(file,sixgr.util.jsonSafeValue(payload));
roundTrip=sixgr.config.loadSimulationRequest(file);
assert(isequal(roundTrip.Config.phy.csirs.precoderMatrices,beam));
% Relative native fragments belong to their declaring parent, not the child.
parentFolder=fullfile(folder,'parent'); childFolder=fullfile(folder,'child');
mkdir(parentFolder); mkdir(childFolder);
fragmentPath=fullfile(parentFolder,'native.json');
sixgr.util.jsonWrite(fragmentPath,struct('run',struct('seed',71)));
parentPayload=payload; parentPayload.sls.config_files{end+1}=fragmentPath;
parentPayload.sls.config_files{end}='native.json';
parentPayload.sls.config.run=rmfield(parentPayload.sls.config.run,'seed');
sixgr.util.jsonWrite(fullfile(parentFolder,'parent.json'),sixgr.util.jsonSafeValue(parentPayload));
childPayload=struct('inherits',{{'../parent/parent.json'}}, ...
    'sls',struct('config',struct('run',struct('numTTI',7))));
childPath=fullfile(childFolder,'child.json'); sixgr.util.jsonWrite(childPath,childPayload);
inherited=sixgr.config.loadSimulationRequest(childPath);
assert(inherited.Config.run.seed==71 && inherited.Config.run.numTTI==7);
payload.sls.config.system.linkAbstraction.allowDevelopmentFixtures=true;
bad=fullfile(folder,'fixture.json'); sixgr.util.jsonWrite(bad,sixgr.util.jsonSafeValue(payload));
localReject(@()sixgr.config.loadSimulationRequest(bad),'sixgr:simulation:DevelopmentCalibration');
payload.run_control.execution_mode='LLS';
sixgr.util.jsonWrite(bad,sixgr.util.jsonSafeValue(payload));
localReject(@()sixgr.config.loadSimulationRequest(bad),'sixgr:simulation:ModeMismatch');
payload=request.Data; payload.frequency=struct('bandwidth_hz',20e6);
sixgr.util.jsonWrite(bad,payload);
localReject(@()sixgr.config.loadSimulationRequest(bad),'sixgr:simulation:ModeNamespace');
payload=struct('inherits',{{'cycle.json'}});
cycle=fullfile(folder,'cycle.json'); sixgr.util.jsonWrite(cycle,payload);
localReject(@()sixgr.config.loadSimulationRequest(cycle),'sixgr:simulation:InheritanceCycle');
% Missing calibration must fail rather than launch synthetic traffic.
localReject(@()run_sixgr(file,folder,'missing_calibration'),'sixgr:abstraction:MissingCalibration');
receiptPath=fullfile(folder,'sls',request.Config.meta.scenarioID,'missing_calibration','meta','simulation_run.json');
receipt=jsondecode(fileread(receiptPath));
assert(string(receipt.Status)=="failed" && ~receipt.ExecutionOk && ~receipt.PrimaryStudyAccepted);
assert(isfield(receipt,'CreatedUTC'));
retainedRoot=fileparts(fileparts(receiptPath));
sources=jsondecode(fileread(fullfile(retainedRoot,'meta','input_sources.json')));
assert(~isempty(sources) && all(strlength(string({sources.SHA256}))==64));
for k=1:numel(sources), assert(isfile(fullfile(retainedRoot,sources(k).RetainedPath))); end
localReject(@()run_sixgr(file,folder,'missing_calibration'),'sixgr:simulation:ExistingRun');
ok=true; fprintf('SIMULATION_MODE_DISPATCH_PASS folder=%s\n',folder);
end
function localReject(action,id)
try, action(); catch ME, assert(string(ME.identifier)==id,'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:ExpectedFailure','Expected %s',id);
end
