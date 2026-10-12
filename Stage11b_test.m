function Stage11b_test()
M = readtable('Stage10_DatasetA_Manifest.csv');
m = M(M.run == 1, :);                                          % use run 1 of Dataset A
args = {m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed};

% Check 1: zero mismatch must reproduce the stored Dataset A run
T0 = Stage11_run_one(args{:}, Stage11_mismatch(0, 0, 1));
A  = readtable('Stage10_runs/run_001.csv');
cols = setdiff(A.Properties.VariableNames, {'t'});
worst = 0;  worstCol = '';
for c = cols
    d = max(abs(T0.(c{1}) - A.(c{1})) ./ (1 + abs(A.(c{1}))));
    if d > worst, worst = d; worstCol = c{1}; end
end
fprintf('\nCHECK 1  zero mismatch vs stored run_001: worst relative difference %.2e (%s)   %s\n', worst, worstCol, ternary(worst < 1e-6));

% Check 2: a mismatch must shift the Twin features
mm = Stage11_mismatch(0.05, 2, 301);
T1 = Stage11_run_one(args{:}, mm);
k = T0.t >= 60;
fprintf('CHECK 2  mismatch drawn: Iph x%.3f  Rsh x%.3f  n x%.3f  Ki x%.3f  R0 x%.3f  R1 x%.3f  Cap x%.3f  SOC %+.2f pts\n', ...
    mm.pvIph, mm.pvRsh, mm.pvN, mm.pvKi, mm.bR0, mm.bR1, mm.bCap, mm.socOff);
fprintf('         PV  residual current, mean over t>=60 s:  exact Twin %+.4f A   mismatched %+.4f A\n', mean(T0.PV_Residual_Current(k)), mean(T1.PV_Residual_Current(k)));
fprintf('         Batt residual voltage, mean over t>=60 s: exact Twin %+.4f V   mismatched %+.4f V\n', mean(T0.Battery_Residual_Voltage(k)), mean(T1.Battery_Residual_Voltage(k)));
fprintf('         plant unchanged (true PV current identical): %s\n', ternary(max(abs(T0.True_PV_Current - T1.True_PV_Current)) < 1e-9));
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end