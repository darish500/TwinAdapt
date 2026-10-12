function Stage13_run_campaign(firstRun, lastRun)
if nargin < 1, firstRun = 1;   end
if nargin < 2, lastRun  = 100; end
M = readtable('Stage10_DatasetA_Manifest.csv');
P = Stage13_fault_plan();
folder = 'Stage11_D_runs';
if ~exist(folder,'dir'), mkdir(folder); end
failed = [];
for r = firstRun:lastRun
    f = fullfile(folder, sprintf('run_%03d.csv', r));
    if isfile(f), continue; end
    m = M(M.run == r, :);  p = P(P.run == r, :);
    tic;
    try
        T = Stage13_run_one(m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed, p);
        assert(abs(mean(T.D_index) - m.pvL/4) < 1e-6 && abs(mean(T.D_batt) - m.bL/4) < 1e-6, 'health level mismatch');
        writetable(T, f);
        fprintf('>>> D run %3d of %d finished in %.1f s\n', r, lastRun, toc);
    catch err
        failed(end+1) = r; %#ok<AGROW>
        fprintf(2, '>>> D run %d FAILED: %s\n', r, err.message);
    end
end
if isempty(failed), fprintf('D campaign: no failures\n'); else, fprintf('failed runs: %s\n', mat2str(failed)); end
end