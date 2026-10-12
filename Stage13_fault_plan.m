function P = Stage13_fault_plan()
% Balanced, shuffled, reproducible assignment of one PV fault and one battery fault to each of the 100 runs.
Kp = Stage13_catalogue('pv');     % 16 combinations
Kb = Stage13_catalogue('batt');   % 12 combinations
n = 100;
rng(400001);  b = repmat(1:numel(Kp), 1, ceil(n/numel(Kp)));  b = b(1:n);  ip = b(randperm(n));
rng(400002);  b = repmat(1:numel(Kb), 1, ceil(n/numel(Kb)));  b = b(1:n);  ib = b(randperm(n));
run = (1:n)';
pvChannel = {Kp(ip).channel}';  pvType = {Kp(ip).typeName}';  pvParam = {Kp(ip).param}';
pvValue = [Kp(ip).value]';      pvTarget = [Kp(ip).target]';  pvCode = [Kp(ip).type]';
bChannel = {Kb(ib).channel}';   bType = {Kb(ib).typeName}';   bParam = {Kb(ib).param}';
bValue = [Kb(ib).value]';       bTarget = [Kb(ib).target]';   bCode = [Kb(ib).type]';
P = table(run, pvChannel, pvType, pvParam, pvValue, pvTarget, pvCode, bChannel, bType, bParam, bValue, bTarget, bCode);
writetable(P, 'Stage13_Fault_Manifest.csv');
end