function P = Stage14_make_plan()
% Fault plan for the stress tests on Dataset F: one PV sensor fault and one battery sensor fault assigned to each of the 114 runs of
% Dataset F, balanced over the same catalogue as Dataset A (Stage13_catalogue: 16 PV and 12 battery channel-by-fault-type
% combinations), shuffled with new fixed seeds (400003, 400004; Dataset A used 400001, 400002). Writes Stage14_Fault_Manifest.csv.
% The file is written once; if it exists the plan is frozen and this function stops.
if isfile('Stage14_Fault_Manifest.csv')
    error('Stage14_Fault_Manifest.csv already exists. It is frozen; delete it only on purpose and say why in the report.');
end
M = sortrows(readtable('Stage10F_Manifest.csv'), 'run');
n = height(M);  assert(n == 114, 'expected 114 runs in Stage10F_Manifest.csv, found %d', n);
Kp = Stage13_catalogue('pv');     % 16 combinations
Kb = Stage13_catalogue('batt');   % 12 combinations
rng(400003);  b = repmat(1:numel(Kp), 1, ceil(n/numel(Kp)));  b = b(1:n);  ip = b(randperm(n));
rng(400004);  b = repmat(1:numel(Kb), 1, ceil(n/numel(Kb)));  b = b(1:n);  ib = b(randperm(n));
run = M.run;
pvChannel = {Kp(ip).channel}';  pvType = {Kp(ip).typeName}';  pvParam = {Kp(ip).param}';
pvValue = [Kp(ip).value]';      pvTarget = [Kp(ip).target]';  pvCode = [Kp(ip).type]';
bChannel = {Kb(ib).channel}';   bType = {Kb(ib).typeName}';   bParam = {Kb(ib).param}';
bValue = [Kb(ib).value]';       bTarget = [Kb(ib).target]';   bCode = [Kb(ib).type]';
P = table(run, pvChannel, pvType, pvParam, pvValue, pvTarget, pvCode, bChannel, bType, bParam, bValue, bTarget, bCode);
writetable(P, 'Stage14_Fault_Manifest.csv');
fprintf('Stage14_Fault_Manifest.csv written: %d runs. PV fault types: ', n);  fprintf('%s=%d ', 'bias',nnz(strcmp(pvType,'bias')),'stuck',nnz(strcmp(pvType,'stuck')),'noise',nnz(strcmp(pvType,'noise')),'drift',nnz(strcmp(pvType,'drift')));
fprintf('\nBattery fault types: ');  fprintf('%s=%d ', 'bias',nnz(strcmp(bType,'bias')),'stuck',nnz(strcmp(bType,'stuck')),'noise',nnz(strcmp(bType,'noise')),'drift',nnz(strcmp(bType,'drift')));
fprintf('\nSHA-256 of the manifest: %s\n', Stage10G_lib('sha256','Stage14_Fault_Manifest.csv'));
end