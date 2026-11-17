function Stage14_run_campaign(tag, firstRun, lastRun)
% Stress-test campaigns on Dataset F (the same 114 runs, same noise seeds and profiles as Dataset F, one change per tag):
%   'E1a' Twin parameters off by up to +-1 %   'E1b' +-2 %   'E1' +-5 %   'E2' +-10 %   'E3' Twin starts 3 SOC points off
%   'D'   one silent sensor fault per sensor group, from Stage14_Fault_Manifest.csv (Twin parameters exact)
% Mismatch draws use seed 500000 + run (Dataset A used 300000 + run), the same draw for every level, scaled by the level.
% Runs are saved to Stage14_<tag>_runs/run_###.csv. Re-running skips runs that exist, so it can be stopped and resumed.
if nargin < 2, firstRun = 1;   end
if nargin < 3, lastRun  = 114; end
switch tag
    case 'E1a', level = 0.01;  socPts = 0;
    case 'E1b', level = 0.02;  socPts = 0;
    case 'E1',  level = 0.05;  socPts = 0;
    case 'E2',  level = 0.10;  socPts = 0;
    case 'E3',  level = 0;     socPts = 3;
    case 'D',   level = NaN;   socPts = NaN;
    otherwise, error('unknown tag %s (use E1a, E1b, E1, E2, E3 or D)', tag);
end
M = readtable('Stage10F_Manifest.csv');
if strcmp(tag,'D')
    assert(isfile('Stage14_Fault_Manifest.csv'), 'Run Stage14_make_plan first.');
    P = readtable('Stage14_Fault_Manifest.csv');
end
folder = ['Stage14_' tag '_runs'];
if ~exist(folder,'dir'), mkdir(folder); end
flt = {'Fault_Active','PV_SensorFault_Active','Battery_SensorFault_Active','Battery_Fault_Active'};
failed = [];
for r = firstRun:lastRun
    f = fullfile(folder, sprintf('run_%03d.csv', r));
    if isfile(f), continue; end
    m = M(M.run == r, :);
    tic;
    try
        if strcmp(tag,'D')
            p = P(P.run == r, :);
            T = Stage14_run_one_fault(m.pvD, m.bD, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed, p);
        else
            mm = Stage11_mismatch(level, socPts, 500000 + r);
            T  = Stage14_run_one_mismatch(m.pvD, m.bD, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed, mm);
            assert(~any(any(T{:,flt} ~= 0)), 'a fault flag is on in a mismatch run');
        end
        assert(abs(mean(T.D_index) - m.pvD) < 1e-6 && abs(mean(T.D_batt) - m.bD) < 1e-6, 'health level mismatch');
        writetable(T, f);
        fprintf('>>> %s run %3d of %d finished in %.1f s\n', tag, r, lastRun, toc);
    catch err
        failed(end+1) = r; %#ok<AGROW>
        fprintf(2, '>>> %s run %d FAILED: %s\n', tag, r, err.message);
    end
end
if isempty(failed), fprintf('%s campaign: no failures\n', tag); else, fprintf('failed runs: %s\n', mat2str(failed)); end
end