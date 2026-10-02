function ok=testSystemNetworkDLCSI()
% Real NR channel/calendar/scheduler and dynamic UCI reservations.
% BLER remains a numerical fixture, never accepted study calibration.
ok=testSystemFTP3CalibratedDelivery("DL","network");
end
