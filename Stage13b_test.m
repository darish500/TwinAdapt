function Stage13b_test()
M = readtable('Stage10_DatasetA_Manifest.csv');
P = Stage13_fault_plan();                                      % also writes Stage13_Fault_Manifest.csv
m = M(M.run == 1, :);  p = P(P.run == 1, :);
T = Stage13_run_one(m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed, p);
A = readtable('Stage10_runs/run_001.csv');

chans  = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final', ...
          'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
pvName = {'G','Tc','V','I'};  bName = {'V','I','T'};
faulted = [find(strcmp(pvName, char(p.pvChannel))), 4 + find(strcmp(bName, char(p.bChannel)))];
fprintf('\nRun 1 faults:  PV %s on %s (%s = %g)   |   battery %s on %s (%s = %g)\n', char(p.pvType), char(p.pvChannel), ...
    char(p.pvParam), p.pvValue, char(p.bType), char(p.bChannel), char(p.bParam), p.bValue);
fprintf('%-26s %-14s %-10s %s\n', 'channel', 'max |diff|', 'faulted?', 'result');
allok = true;
for k = 1:numel(chans)
    d = max(abs(T.(chans{k}) - A.(chans{k})));
    isF = ismember(k, faulted);
    ok = (isF && d > 1e-6) || (~isF && d < 1e-9);
    allok = allok && ok;
    fprintf('%-26s %-14.4g %-10d %s\n', chans{k}, d, isF, ternary(ok));
end
dT = max(abs(T.True_PV_Current - A.True_PV_Current));
dB = max(abs(T.True_Battery_Voltage - A.True_Battery_Voltage));
fprintf('real plant unchanged (true PV current, true battery voltage): %.2g, %.2g   %s\n', dT, dB, ternary(dT < 1e-9 && dB < 1e-9));
fprintf('OVERALL %s\n', ternary(allok && dT < 1e-9 && dB < 1e-9));
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end