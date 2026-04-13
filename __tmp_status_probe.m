setup6GRSimToolkit('Verbose',false);
tmp=tempname; mkdir(tmp);
baseScenario = fullfile(pwd,'simulator','configs','scenarios','low_snr_stress.yaml');
for snr = [-15 -25 -35]
  scenarioPath = fullfile(tmp, sprintf('probe_%d.yaml', abs(snr)));
  fid = fopen(scenarioPath,'w');
  fprintf(fid,'%s',['{' ...
    '"inherits":["' strrep(baseScenario,'\','\\') '"],' ...
    '"meta":{"scenario_id":"status_probe_' num2str(abs(snr)) '","description":"status probe","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"n_frames":4,"n_slots":4,"monte_carlo_iterations":2,"random_seed":11,"snr_db":' num2str(snr) '},' ...
    '"output":{"save_figures":false,"save_mat":true}}']);
  fclose(fid);
  out = run_6g_phy_lls_single(scenarioPath, tmp, sprintf('tag_%d', abs(snr)));
  fprintf('SNR=%g Ok=%d RunFolder=%s\n', snr, logical(out.Ok), string(out.RunFolder));
end
