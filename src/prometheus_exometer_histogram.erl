-module(prometheus_exometer_histogram).
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

-export([define_buckets/1]).

-compile(inline).

-record(st, {name,
             internal_name,
             internal_type,
             sub_type,
             reset_time,
             buckets = [],
             options = []}).

-spec behaviour() -> exometer:behaviour().
behaviour()->
    probe.

probe_init(Name, _Type, Options) ->
    % logger:debug("Options: ~p ~p", [Name, Options]),
    St = process_options(#st{name = Name,
                          internal_name = Name ++ [internal],
                          internal_type = histogram,
                          sub_type = prometheus_histogram
                         }, Options),
    % logger:debug("St: ~p ~p", [Name, St]),

    PrometheusOptions0 = proplists:get_value(prometheus, St#st.options, #{}),
    PrometheusOptions = maps:merge(PrometheusOptions0, #{parent => Name}),

    ChildOptions0 = proplists:delete(module, St#st.options),
    ChildOptions = proplists:delete(prometheus, ChildOptions0),

    % logger:debug("ChildOptions: ~p ~p", [Name, ChildOptions]),
    InternalOptions = ChildOptions ++ [{prometheus, maps:merge(PrometheusOptions, #{internal => true})}],
    exometer:ensure(St#st.internal_name, St#st.internal_type, InternalOptions),
    lists:foreach(fun({BucketName, _Bucket}) ->
        ok = exometer:ensure(Name ++ [bucket, BucketName], counter, InternalOptions)
                  end, St#st.buckets),
    ok = exometer:ensure(Name ++ [sum], counter, InternalOptions),
    ok = exometer:ensure(Name ++ [count], counter, InternalOptions),

    % SubOptions = ChildOptions ++ [{prometheus, PrometheusOptions}],
    SubOptions = ChildOptions ++ [{prometheus, maps:merge(PrometheusOptions, #{sub => true})}],
    exometer_admin:set_default(Name ++ ['_'], St#st.sub_type,
                               [{options, SubOptions}, {module, prometheus_exometer_histogram}]),

    % process_flag(min_heap_size, 40000),
    {ok, St}.

probe_terminate(_St) ->
    ok.

probe_get_value(DataPoints, St) ->
    {ok, [get_single_value(St, DataPoint) || DataPoint <- DataPoints]}.

probe_get_datapoints(St) ->
    Buckets = [Name || {Name, _Bucket} <- St#st.buckets],
    % logger:debug("buckets: ~p", [Buckets]),
    {ok, [sum, count] ++ Buckets}.

probe_setopts(_Entry, _Options, _St)  ->
    % TODO: implement this
    % process_options(St, Options),
    ok.

probe_update(Value, St) ->
    exometer:update(St#st.internal_name, Value),
    exometer:update(St#st.name ++ [sum], round(Value)), % TODO: accept float
    exometer:update(St#st.name ++ [count], 1),
    lists:foreach(fun
                     ({BucketName, inf}) ->
                        exometer:update(St#st.name ++ [bucket, BucketName], 1);
                     ({BucketName, Bucket}) ->
                        case Value =< Bucket of
                            true ->
                                exometer:update(St#st.name ++ [bucket, BucketName], 1);
                            _ ->
                                ok
                        end
                  end, St#st.buckets),
    {ok, St}.

probe_reset(St) ->
    exometer:reset(St#st.internal_name),
    exometer:reset(St#st.name ++ [sum]),
    exometer:reset(St#st.name ++ [count]),
    lists:foreach(fun({BucketName, _Bucket}) ->
        exometer:reset(St#st.name ++ [bucket, BucketName])
                  end, St#st.buckets),
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

get_single_value(St, Name) ->
    case proplists:get_value(Name, St#st.buckets, undefined) of
        undefined ->
            {Name, {error, unsupported}};
        _Bucket ->
            {ok, DataPoints} = exometer:get_value(St#st.name ++ [bucket, Name]),
            {Name, proplists:get_value(value, DataPoints)}
    end.

process_options(St, Options0) ->
    exometer_proc:process_options(Options0),
    Options = clean_options(Options0),

    lists:foldl(
      fun
          % ({buckets, BucketSpec}, St1) ->
          %     Buckets = define_buckets(BucketSpec),
          %     BucketNames = [{to_bucket_name(Bucket), Bucket} || Bucket <- Buckets] ++ [{'+Inf', inf}],
          %     St1#st{buckets = BucketNames};

          ({prometheus, PrometheusOptions}, St1) ->
              process_options_prometheus(St1, PrometheusOptions);

          %% Unknown option, pass on to State options list, replacing
          %% any earlier versions of the same option.
          ({Opt, Val}, St1) ->
                       St1#st{options = [{Opt, Val}
                                      | lists:keydelete(Opt, 1, St1#st.options)]}
               end, St, Options).

process_options_prometheus(St0, Options) ->
    % These are the defaults used by the Go library, assuming seconds, but we use microseconds internally
    % https://github.com/prometheus/client_golang/blob/master/prometheus/histogram.go#L54
    % DefaultBuckets = [.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10],
    DefaultBuckets = [5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000],
    Defaults = #{
      buckets => DefaultBuckets,
      export_buckets => false
    },
    MergedOptions = maps:merge(Defaults, Options),
    St1 = St0#st{options = [{prometheus, MergedOptions}
                            | lists:keydelete(prometheus, 1, St0#st.options)]},

    maps:fold(fun(buckets, BucketSpec, St) ->
                      Buckets = define_buckets(BucketSpec),
                      BucketNames = [{to_bucket_name(Bucket), Bucket} || Bucket <- Buckets] ++ [{'+Inf', inf}],
                      St#st{buckets = BucketNames};
                 (_K, _V, St) ->
                      St
              end, St1, MergedOptions).

-spec clean_options(Options) -> Options when
      Options :: list(proplists:property()).
clean_options(Options) ->
    PrometheusOptions = proplists:get_value(prometheus, Options),
    Options1 = proplists:delete(prometheus, Options),
    Options1 ++ [{prometheus, PrometheusOptions}].

% Create 'count' buckets, each 'width' wide, where the lowest bucket
% has an upper bound of 'start'. The final +Inf bucket is not counted.
define_buckets({linear, Start, Width, Count}) ->
    End = Count * Width,
    lists:seq(Start, End, Width);
% Create 'count' buckets, where the lowest bucket has an upper bound
% of 'start' and each following bucket's upper bound is 'factor' times
% the previous bucket's upper bound. The final +Inf bucket is not counted.
define_buckets({exponential, Start, Factor, Count}) ->
    {_Prev, Buckets} = lists:foldl(
        fun(_N, {Prev, B}) ->
            {Prev * Factor, [Prev * Factor | B]}
        end, {Start, [Start]}, lists:seq(1, Count - 1)
    ),
    lists:reverse(Buckets);
% User defined list of buckets
define_buckets(Buckets) when is_list(Buckets) ->
    Buckets.

to_bucket_name(Bucket) when is_atom(Bucket) ->
    Bucket;
to_bucket_name(Bucket) when is_binary(Bucket) ->
    binary_to_atom(Bucket, utf8);
to_bucket_name(Bucket) when is_float(Bucket) ->
    binary_to_atom(float_to_binary(Bucket, [{decimals, 4}]), utf8);
to_bucket_name(Bucket) when is_integer(Bucket) ->
    binary_to_atom(integer_to_binary(Bucket), utf8).
