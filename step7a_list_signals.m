function step7a_list_signals()
model = 'Reformable_AI_2025';
if bdIsLoaded(model), close_system(model, 0); end
evalin('base','reformable_AI;');
load_system(model);
c = onCleanup(@() close_system(model, 0));
set_param(model,'FastRestart','off');
set_param(model,'StopTime','10');
out = sim(model);

names = sort(out.who);
fprintf('%d logged signals\n\n', numel(names));
for i = 1:numel(names)
    v = out.get(names{i});
    if isa(v,'timeseries')
        fprintf('%3d  %-38s  samples=%5d  last=%g\n', i, names{i}, numel(v.Time), double(v.Data(end)));
    else
        fprintf('%3d  %-38s  (%s)\n', i, names{i}, class(v));
    end
end
end