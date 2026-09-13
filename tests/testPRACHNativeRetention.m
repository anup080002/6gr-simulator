function ok=testPRACHNativeRetention(root)
if nargin<1, root=tempname; end
% Actual standalone generator/channel/detector executions, NOT a main 12 dB run.
setup6GRSimToolkit('Verbose',false);
assert(~isfolder(root),'test:PreserveExistingEvidence','Use a new output directory.');
mkdir(root);
folder=fileparts(mfilename('fullpath'));
fixtures=["prach_native_nr_fixture.yaml","prach_native_noise_fixture.yaml","prach_native_zcdpe_fixture.yaml"];
for k=1:numel(fixtures)
    scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(folder,'fixtures',fixtures(k)));
    target=fullfile(root,scfg.ScenarioID);
    mkdir(target); % A noise-only result may correctly produce no allocation CSV.
    cfg=sixgr.lls6g.buildInternalConfig(scfg,target);
    % Resolved fixture identity, matching the front-door runner boundary.
    cfg.meta.configHash=char(scfg.ConfigHash);
    cfg.run.scenarioID=char(scfg.ScenarioID);
    scenario=struct('ScenarioName',char(scfg.ScenarioID));
    candidate=sixgr.rach.runPRACHLLS(cfg,'WriteOutputs',false,'ScenarioMatrix',scenario,'Verbose',false);
    T=candidate.ObservedREAllocationTable;
    transmitted=nnz(candidate.TrialTable.preamble_tx_present);
    if transmitted==0
        assert(isempty(T),'test:InventedNativePRACH','Reference/noise-only waveform must not become a transmission.');
    else
        assert(numel(unique(T.allocation_id))==transmitted);
        assert(all(T.PRACHStudyTransmitterRole=="serving") && all(T.grid_domain=="prach_native_ofdm"));
        assert(all(T.PRACHStudySeed==candidate.ROTable.seed(1)));
        assert(all(T.PRACHStudyDesign==candidate.ROTable.prach_design(1)));
        assert(all(strlength(T.waveform_sha256)==64));
    end
    layout=verifyObservedREPublication(T,cfg,target);
    if transmitted>0
        [status,message]=system(sprintf('python "%s" "%s"', ...
            fullfile(pwd,'tests','verify_native_prach_publication.py'),layout.ReportCSVDir));
        assert(status==0,'test:NativePRACHPublication','%s',message); fprintf('%s',message);
    end
    save(fullfile(target,'native_retention_comparison.mat'),'candidate');
    fprintf('PRACH_NATIVE_RETENTION_CASE_PASS fixture=%s actual_tx=%d allocation_rows=%d actual_native_retention=1\n', ...
        fixtures(k),transmitted,height(T));
end
fprintf('PRACH_NATIVE_RETENTION_PASS standalone_PHY_and_CSV_PNG_only main_12db_qualified=0\n');
ok=true;
end
