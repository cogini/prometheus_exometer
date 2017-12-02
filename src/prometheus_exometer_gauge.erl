-module(prometheus_exometer_gauge).
-behaviour(exometer_probe).

%% exometer_entry callbacks
-export([behaviour/0,
         probe_init/3,
         probe_terminate/1,
         probe_setopts/3,
         probe_update/2,
         probe_get_value/2,
         probe_get_datapoints/1,
         probe_reset/1,
         probe_code_change/3,
         probe_sample/1,
         probe_handle_msg/2]).

-compile(inline).

-record(st, {name,
             internal_name,
             internal_type,
             sub_type,
             options = []}).

-spec behaviour() -> exometer:behaviour().
behaviour()->
    probe.

probe_init(Name, _Type, Options) ->
    % lager:debug("Options: ~p ~p", [Name, Options]),
    St = process_options(#st{name = Name,
                          internal_name = Name ++ [internal],
                          internal_type = gauge,
                          sub_type = gauge
                         }, Options),
    % lager:debug("St: ~p ~p", [Name, St]),

    PrometheusOptions0 = proplists:get_value(prometheus, Options, #{}),
    PrometheusOptions = maps:merge(PrometheusOptions0, #{parent => Name}),

    ChildOptions0 = proplists:delete(module, Options),
    ChildOptions = proplists:delete(prometheus, ChildOptions0),

    % lager:debug("ChildOptions: ~p ~p", [Name, ChildOptions]),
    InternalOptions = ChildOptions ++ [{prometheus, maps:merge(PrometheusOptions, #{internal => true})}],
    exometer:ensure(St#st.internal_name, St#st.internal_type, InternalOptions),

    % SubOptions = ChildOptions ++ [{prometheus, PrometheusOptions}],
    SubOptions = ChildOptions ++ [{prometheus, maps:merge(PrometheusOptions, #{sub => true})}],
    exometer_admin:set_default(Name ++ ['_'], St#st.sub_type,
                               [{options, SubOptions}, {module, exometer}]),
    {ok, St}.

probe_terminate(_St) ->
    ok.

probe_get_value(DataPoints, St) ->
    exometer:get_value(St#st.internal_name, DataPoints).

probe_get_datapoints(St) ->
    {ok, exometer:info(St#st.internal_name, datapoints)}.

probe_setopts(_Entry, _Options, _St)  ->
    % process_options(St, Options),
    ok.

probe_update(Value, St) ->
    ok = exometer:update(St#st.internal_name, Value),
    {ok, St}.

probe_reset(St) ->
    ok = exometer:reset(St#st.internal_name),
    {ok, St}.

probe_sample(_St) ->
    {error, unsupported}.

probe_handle_msg(_, S) ->
    {ok, S}.

probe_code_change(_, S, _) ->
    {ok, S}.

process_options(St, Options0) ->
    exometer_proc:process_options(Options0),
    Options = clean_options(Options0),
    lists:foldl(
      fun
          % TODO options for this module
          %% Sample interval.
          % ({time_span, Val}, St1) -> St1#st{time_span = Val};
          % ({slot_period, Val}, St1) -> St1#st{slot_period = Val};

          %% Unknown option, pass on to State options list, replacing
          %% any earlier versions of the same option.
          ({Opt, Val}, St1) ->
                       St1#st{options = [{Opt, Val}
                                      | lists:keydelete(Opt, 1, St1#st.options)]}
               end, St, Options).

-spec clean_options(Options) -> Options when
      Options :: list(proplist:property()).
clean_options(Options) ->
    Description = proplists:get_value(description, Options),
    Options1 = proplists:delete(description, Options),
    Options1 ++ [{description, Description}].
