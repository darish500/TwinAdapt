function M = Stage10F_make_manifest()
% Builds and FREEZES the Dataset F manifest (untouched final test). Run once, before any F run is simulated.
% Writes Stage10F_Manifest.csv and prints its SHA-256. Refuses to overwrite an existing manifest.
%
% Regime A-F (unseen health levels):  PV and battery health in {0.125, 0.375, 0.625, 0.875}
%     4 x 4 level pairs x 4 repeats = 64 runs, profiles 1..4 (balanced within each level).
%     None of these levels is in Dataset A (A used 0, .25, .5, .75, 1).
% Regime B-F (unseen operating profile): profile family 5 for PV and battery (new shapes),
%     health in {0, .25, .5, .75, 1}; 5 x 5 level pairs x 2 repeats = 50 runs.
% Total 114 runs. Run numbers 1..114.
% Seeds are new: noise seed = 100 + run (so the noise "skip" in Stage10_run_one stays small), profile seeds 810000+run / 820000+run.
% If Stage10_DatasetA_Manifest.csv is present, the script checks that no F seed equals an A seed.
if isfile('Stage10F_Manifest.csv')
    error('Stage10F_Manifest.csv already exists. It is frozen; delete it only on purpose and say why in the report.');
end
rng(20261012, 'twister');                                   % controls only the assignment of profiles/order

lvA = [0.125 0.375 0.625 0.875];
lvB = [0 0.25 0.5 0.75 1];
rows = [];                                                  % columns: regime(1=A,2=B), pvD, bD
for i = 1:numel(lvA), for j = 1:numel(lvA), for k = 1:4
    rows(end+1,:) = [1 lvA(i) lvA(j)]; %#ok<AGROW>
end, end, end
for i = 1:numel(lvB), for j = 1:numel(lvB), for k = 1:2
    rows(end+1,:) = [2 lvB(i) lvB(j)]; %#ok<AGROW>
end, end, end
rows = rows(randperm(size(rows,1)), :);                     % shuffled run order

n = size(rows,1);
pvProf = zeros(n,1);  bProf = zeros(n,1);
isA = rows(:,1) == 1;
pvProf(~isA) = 5;  bProf(~isA) = 5;
% Regime A-F: within each health level, the four profiles appear equally often (16 runs per level -> 4 each)
for L = lvA
    ix = find(isA & abs(rows(:,2) - L) < 1e-12);
    pvProf(ix) = ix_bal(numel(ix));
    ix = find(isA & abs(rows(:,3) - L) < 1e-12);
    bProf(ix) = ix_bal(numel(ix));
end

run = (1:n)';
rg = ["A";"B"];  rg = rg(rows(:,1));
M = table(run, rg, rows(:,2), rows(:,3), pvProf, bProf, ...
    100 + run, 810000 + run, 820000 + run, ...
    'VariableNames', {'run','regime','pvD','bD','pvProf','bProf','noiseSeed','pvProfSeed','bProfSeed'});

% ---- checks ----
assert(all(M.pvProf >= 1 & M.pvProf <= 5) && all(M.bProf >= 1 & M.bProf <= 5));
for L = lvA
    q = M(M.regime == "A" & abs(M.pvD - L) < 1e-12, :);
    assert(height(q) == 16 && all(histcounts(q.pvProf, 0.5:1:4.5) == 4), 'PV profile balance broken');
    q = M(M.regime == "A" & abs(M.bD - L) < 1e-12, :);
    assert(height(q) == 16 && all(histcounts(q.bProf, 0.5:1:4.5) == 4), 'battery profile balance broken');
end
if isfile('Stage10_DatasetA_Manifest.csv')
    A = readtable('Stage10_DatasetA_Manifest.csv');
    assert(~any(ismember([M.noiseSeed; M.pvProfSeed; M.bProfSeed], [A.noiseSeed; A.pvProfSeed; A.bProfSeed])), 'a Dataset F seed equals a Dataset A seed');
    fprintf('Seed check: no Dataset F seed appears in the Dataset A manifest.\n');
else
    warning('Dataset A manifest not found here, so the seed-collision check was skipped.');
end
assert(numel(unique(M.noiseSeed)) == n && numel(unique(M.pvProfSeed)) == n && numel(unique(M.bProfSeed)) == n);

writetable(M, 'Stage10F_Manifest.csv');
fprintf('Saved Stage10F_Manifest.csv: %d runs (A-F %d, B-F %d)\n', n, nnz(isA), nnz(~isA));
fprintf('SHA-256: %s\n', sha256('Stage10F_Manifest.csv'));
fprintf('Write this hash into the report. Do not edit the manifest after this point.\n');
end

function v = ix_bal(m)
v = repmat((1:4)', ceil(m/4), 1);  v = v(1:m);  v = v(randperm(m));
end

function h = sha256(f)
fid = fopen(f, 'r');  b = fread(fid, inf, '*uint8');  fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(b);
u = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(double(u), 2).', 1, []));
end