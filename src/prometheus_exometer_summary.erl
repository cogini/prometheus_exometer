-module(prometheus_exometer_summary).
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
             reset_time,
             options = []}).

-spec behaviour() -> exometer:behaviour().
behaviour()->
    probe.

probe_init(Name, _Type, Options) ->
    % lager:debug("Options: ~p ~p", [Name, Options]),
    St = process_options(#st{name = Name,
                          internal_name = Name ++ [internal],
                          internal_type = histogram,
                          sub_type = prometheus_summary
                         }, Options),
    % lager:debug("St: ~p ~p", [Name, St]),

    PrometheusOptions0 = proplists:get_value(prometheus, St#st.options, #{}),
    PrometheusOptions = maps:merge(PrometheusOptions0, #{parent => Name}),

    ChildOptions0 = proplists:delete(module, St#st.options),
    ChildOptions = proplists:delete(prometheus, ChildOptions0),

    % lager:debug("ChildOptions: ~p ~p", [Name, ChildOptions]),
    InternalOptions = ChildOptions ++ [{prometheus, maps:merge(PrometheusOptions, #{internal => true})}],
    exometer:ensure(St#st.internal_name, St#st.internal_type, InternalOptions),
    ok = exometer:ensure(Name ++ [sum], counter, InternalOptions),
    ok = exometer:ensure(Name ++ [count], counter, InternalOptions),

    % SubOptions = ChildOptions ++ [{prometheus, PrometheusOptions}],
    SubOptions = ChildOptions ++ [{prometheus, maps:merge(PrometheusOptions, #{sub => true})}],
    exometer_admin:set_default(Name ++ ['_'], St#st.sub_type,
                               [{options, SubOptions}, {module, prometheus_summary}]),

    % process_flag(min_heap_size, 40000),
    {ok, St}.

probe_terminate(_St) ->
    ok.

probe_get_value(DataPoints, St) ->
    {ok, [get_single_value(St, DataPoint) || DataPoint <- DataPoints]}.

probe_get_datapoints(_St) ->
    % [{sum: 0.0}, {:count, 0.0}, {50, "50}, {75, "75"}, {90, "90"}, {95, "95"}, {inf, "+Inf"}]
    {ok, [sum, count]}.

probe_setopts(_Entry, _Options, _St)  ->
    % process_opts(St, Options),
    ok.

probe_update(Value, St) ->
    exometer:update(St#st.internal_name, Value),
    exometer:update(St#st.name ++ [sum], round(Value)),
    exometer:update(St#st.name ++ [count], 1),
    {ok, St}.

probe_reset(St) ->
    exometer:reset(St#st.internal_name),
    exometer:reset(St#st.name ++ [sum]),
    exometer:reset(St#st.name ++ [count]),
    {ok, St#st{reset_time = os:timestamp()}}.

probe_sample(_St) ->
    {error, unsupported}.

probe_handle_msg(_, S) ->
    {ok, S}.

probe_code_change(_, S, _) ->
    {ok, S}.

% Internal functions

get_single_value(St, sum) ->
    {ok, DataPoints} = exometer:get_value(St#st.name ++ [sum]),
    {sum, proplists:get_value(value, DataPoints)};

get_single_value(St, count) ->
    {ok, DataPoints} = exometer:get_value(St#st.name ++ [count]),
    {count, proplists:get_value(value, DataPoints)};

get_single_value(_St, Name) ->
    {Name, {error, unsupported}}.

process_options(St, Options0) ->
    exometer_proc:process_options(Options0),
    Options = clean_options(Options0),

    lists:foldl(
      fun
          ({prometheus, PrometheusOptions}, St1) ->
              process_options_prometheus(St1, PrometheusOptions);

          %% Unknown option, pass on to State options list, replacing
          %% any earlier versions of the same option.
          ({Opt, Val}, St1) ->
                       St1#st{options = [{Opt, Val}
                                      | lists:keydelete(Opt, 1, St1#st.options)]}
               end, St, Options).

process_options_prometheus(St0, Options) ->
    Defaults = #{
      export_quantiles => false
    },
    MergedOptions = maps:merge(Defaults, Options),
    St0#st{options = [{prometheus, MergedOptions}
                      | lists:keydelete(prometheus, 1, St0#st.options)]}.

    % maps:fold(fun(buckets, BucketSpec, St) ->
    %                   Buckets = define_buckets(BucketSpec),
    %                   BucketNames = [{to_bucket_name(Bucket), Bucket} || Bucket <- Buckets] ++ [{'+Inf', inf}],
    %                   St#st{buckets = BucketNames};
    %              (_K, _V, St) ->
    %                   St
    %           end, St1, MergedOptions).

-spec clean_options(Options) -> Options when
      Options :: list(proplists:property()).
clean_options(Options) ->
    PrometheusOptions = proplists:get_value(prometheus, Options),
    Options1 = proplists:delete(prometheus, Options),
    Options1 ++ [{prometheus, PrometheusOptions}].
