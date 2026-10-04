function ok=testSLSAggregateSRRuntime()
% Public optional SR policy through the normal scheduler/file/UCI runtime.
% Development calibration remains explicit; this is not a performance curve.
ok=testSystemFTP3CalibratedDelivery('UL','network','automatic', ...
    'shared_configured_resources','simulator/configs/system/aggregate_ftp3_sr_mac.yaml');
end
