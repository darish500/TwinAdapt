function Stage10H_regen_test()
% Reproducibility audit, simulation regeneration: re-simulates three Dataset A runs from the manifest (same seeds, same code,
% the model as it is now) and compares every column with the saved run files. Read-only for the saved data: results go to
% Stage10H_RegenTest.csv; Stage10_runs is not touched. Note that Stage10_run_one re-runs reformable_AI.m, which re-saves the
% parameter .mat files (same code, so same values; only their timestamps change).
here = fileparts(which('Stage10H_regen_test'));
if isempty(here), error('Keep Stage10H_regen_test.m in the Reformable_AI folder.'); end
cd(here);
M = readtable('Stage10_DatasetA_Manifest.csv');
runs = [1 37 100];
rows = {};  worstAll = 0;
for r = runs
    m = M(M.run == r, :);
    tic;
    T = Stage10_run_one(m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed);
    S = readtable(fullfile('Stage10_runs', sprintf('run_%03d.csv', r)));
    assert(isequal(T.Properties.VariableNames, S.Properties.VariableNames), 'column names differ for run %d', r);
    worst = 0;  worstCol = '';
    for c = T.Properties.VariableNames
        d = max(abs(T.(c{1}) - S.(c{1})));
        sc = max(1, max(abs(S.(c{1}))));
        if d/sc > worst, worst = d/sc; worstCol = c{1}; end
    end
    worstAll = max(worstAll, worst);
    rows(end+1,:) = {r, m.noiseSeed, worst, worstCol, toc}; %#ok<AGROW>
    fprintf('run %3d: largest relative difference vs saved run = %.3g (column %s)\n', r, worst, worstCol);
end
writetable(cell2table(rows, 'VariableNames', {'Run','NoiseSeed','MaxRelDiff','WorstColumn','Seconds'}), 'Stage10H_RegenTest.csv');
if worstAll < 1e-9, fprintf('RESULT: regenerated runs match the saved Dataset A runs (relative difference < 1e-9).\n');
else, fprintf('RESULT: regenerated runs DIFFER from the saved runs (largest relative difference %.3g). Do not call the simulation reproducible.\n', worstAll); end
end