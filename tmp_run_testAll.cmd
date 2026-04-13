@if exist testAll_latency_semantics.log del /f /q testAll_latency_semantics.log
@matlab -batch "setup6GRSimToolkit('Verbose',false); report=testAll; if isstruct(report) && isfield(report,'ok'), assert(report.ok); end" > testAll_latency_semantics.log 2>&1
@type testAll_latency_semantics.log
@exit /b %ERRORLEVEL%
