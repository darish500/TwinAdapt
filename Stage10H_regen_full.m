function Stage10H_regen_full()
% Reproducibility audit, full simulation regeneration: re-simulates ALL 100 Dataset A runs from the manifest (same seeds, same
% code, the model as it is now) and compares every column with the saved run files in Stage10_runs.
% Read-only for the saved data. Results: Stage10H_RegenFull.csv (one row per run), written after every run so an
% interrupted session can be resumed: runs already in the file are skipped on the next call.
% Note: Stage10_run_one re-runs reformable_AI.m, which re-saves the parameter .mat files (same code, same values; only
% their timestamps change). A failed run is recorded as FAILED with its error message; it does not stop the loop.
% Extends Stage10H_regen_test.m (which checked runs 1, 37 and 100 only).
here = fileparts(which('Stage10H_regen_full'));
if isempty(here), error('Keep Stage10H_regen_full.m in the Reformable_AI folder.'); end
cd(here);
M   = readtable('Stage10_DatasetA_Manifest.csv');
out = 'Stage10H_RegenFull.csv';
tol = 1e-9;
if isfile(out)
    R = readtable(out, 'TextType', 'string');  done = R.Run;
    fprintf('Resuming: %d runs already in %s.\n', numel(done), out);
else
    R = table('Size',[0 6], 'VariableTypes',{'double','double','double','string','double','string'}, ...
              'VariableNames',{'Run','NoiseSeed','MaxRelDiff','WorstColumn','Seconds','Status'});
    done = [];
end
for r = M.run'
    if any(done == r), continue; end
    m = M(M.run == r, :);
    tic;
    try
        T = Stage10_run_one(m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed);
        S = readtable(fullfile('Stage10_runs', sprintf('run_%03d.csv', r)));
        assert(isequal(T.Properties.VariableNames, S.Properties.VariableNames), 'column names differ');
        assert(height(T) == height(S), 'row count differs (%d vs %d)', height(T), height(S));
        worst = 0;  worstCol = '';
        for c = T.Properties.VariableNames
            d  = max(abs(T.(c{1}) - S.(c{1})));
            sc = max(1, max(abs(S.(c{1}))));
            if d/sc > worst, worst = d/sc; worstCol = c{1}; end
        end
        if worst < tol, st = "MATCH"; else, st = "DIFFERS"; end
        newRow = {r, m.noiseSeed, worst, string(worstCol), toc, st};
        fprintf('run %3d: largest relative difference %.3g (%s) -> %s\n', r, worst, worstCol, st);
    catch err
        newRow = {r, m.noiseSeed, NaN, "", toc, "FAILED: " + string(strrep(err.message, newline, ' '))};
        fprintf('run %3d: FAILED: %s\n', r, err.message);
    end
    R = [R; newRow]; %#ok<AGROW>
    writetable(R, out);
end
nMatch = sum(R.Status == "MATCH");  nDiff = sum(R.Status == "DIFFERS");  nFail = sum(startsWith(R.Status, "FAILED"));
fprintf('\n=== Regeneration of Dataset A: %d runs checked | %d match (< %g) | %d differ | %d failed ===\n', height(R), nMatch, tol, nDiff, nFail);
fprintf('Largest relative difference over all runs: %.3g\n', max(R.MaxRelDiff));
if nMatch == height(R) && height(R) == height(M)
    fprintf('RESULT: all %d Dataset A runs regenerate from the manifest to within %g.\n', height(R), tol);
else
    fprintf('RESULT: NOT all runs match. Do not call the simulation fully reproducible; report the runs listed as DIFFERS or FAILED.\n');
end
end