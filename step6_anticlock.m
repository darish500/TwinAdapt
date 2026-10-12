function step6_anticlock()
model = 'Reformable_AI_2025';
levels = [0 1];                                % healthy and fully aged
tg = (0:0.5:60)';
S = zeros(numel(tg), numel(levels));

for i = 1:numel(levels)
    if bdIsLoaded(model), close_system(model, 0); end
    evalin('base','reformable_AI;');
    load_system(model);
    c = onCleanup(@() close_system(model, 0));
    set_param(model,'FastRestart','off');
    set_param(model,'StopTime','60');
    const_time(model,'PV_Degradation_Model',      levels(i)*evalin('base','T_life'));
    const_time(model,'Battery_Degradation_Model', levels(i)*evalin('base','T_life_batt'));
    out = sim(model);

    names = out.who;                            % list every logged signal
    hit = names(contains(names,'Twin_SOC','IgnoreCase',true));
    if i == 1, fprintf('SOC-like signals found: %s\n', strjoin(hit', ', ')); end
    sig = out.get(hit{1});
    S(:,i) = interp1(sig.Time, squeeze(sig.Data), tg);
    clear c
end

fprintf('corr(Twin SOC, time)      at D=0 : %7.4f\n', corr(S(:,1), tg));
fprintf('corr(Twin SOC, time)      at D=1 : %7.4f\n', corr(S(:,2), tg));
fprintf('max |SOC(D=0) - SOC(D=1)|        : %.3g\n', max(abs(S(:,1)-S(:,2))));
fprintf('SOC range over the run D=0       : %.4f -> %.4f\n', S(1,1), S(end,1));
end

function const_time(model, subName, tval)
sub = [model '/' subName];
ph  = get_param(sub,'PortHandles'); inP = ph.Inport(1);
ln  = get_param(inP,'Line');
srcP = get_param(ln,'SrcPortHandle');
delete_line(model, srcP, inP);
cb = [model '/S10_time_' subName];
add_block('simulink/Sources/Constant', cb, 'Value', num2str(tval,'%.15g'));
cph = get_param(cb,'PortHandles');
add_line(model, cph.Outport(1), inP);
end