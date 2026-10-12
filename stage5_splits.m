% step5_splits.m  -- build the 100-run design and the splits (no Simulink)

[pvL, bL, k] = ndgrid(0:4, 0:4, 0:3);          % every combination: 5 x 5 x 4 = 100 runs
M = table(pvL(:), bL(:), k(:), 'VariableNames', {'pvL','bL','k'});
M.run = (1:height(M))';                        % run number 1..100

M.pvProf = M.k + 1;                            % PV profile 1..4
M.bProf  = mod(M.k + M.pvL + M.bL, 4) + 1;     % battery profile 1..4, shuffled against the PV one

M.noiseSeed = 100000 + M.run;                  % each run gets its own noise seed
M.pvProfSeed = 200000 + M.run;                 % seed for the PV profile shape
M.bProfSeed  = 700000 + M.run;                 % seed for the battery profile shape

n = height(M);
% Regime A: split by health level
M.pvA = repmat("train", n, 1);  M.pvA(ismember(M.pvL,[1 3])) = "test";
M.bA  = repmat("train", n, 1);  M.bA(ismember(M.bL,[1 3]))   = "test";
% Regime B: split by operating profile
M.pvB = repmat("train", n, 1);  M.pvB(M.pvProf == 4) = "test";
M.bB  = repmat("train", n, 1);  M.bB(M.bProf  == 4) = "test";

disp('--- PV, Regime A (health level), runs per level ---');
disp(groupcounts(M, {'pvL','pvA'}));
disp('--- PV, Regime B (profile), runs per profile ---');
disp(groupcounts(M, {'pvProf','pvB'}));
disp('--- Battery, Regime A ---');
disp(groupcounts(M, {'bL','bA'}));
disp('--- Battery, Regime B ---');
disp(groupcounts(M, {'bProf','bB'}));

fprintf('\nunique noise seeds: %d of %d\n', numel(unique(M.noiseSeed)), n);
fprintf('every (pv level, pv profile) cell has 5 runs: %d\n', ...
        all(groupcounts(M, {'pvL','pvProf'}).GroupCount == 5));
fprintf('every (battery level, battery profile) cell has 5 runs: %d\n', ...
        all(groupcounts(M, {'bL','bProf'}).GroupCount == 5));
writetable(M, 'Stage10_DatasetA_Manifest.csv');