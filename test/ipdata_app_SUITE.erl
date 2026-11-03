%%%-------------------------------------------------------------------
%%% @doc Common Test suite for the ipdata application lifecycle.
%%%
%%% Starts and stops the real application (no network access is
%%% needed: no request is made) and checks that the `ipdata' httpc
%%% profile holding the persistent connections follows it.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_app_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-compile(export_all).

%%--------------------------------------------------------------------
%% Suite setup
%%--------------------------------------------------------------------

all() ->
    [start_creates_profile_with_options,
     start_accepts_already_started_profile,
     httpc_options_env_applied_on_start,
     stop_removes_profile].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(inets),
    _ = application:load(ipdata),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    reset(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    reset(),
    ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

start_creates_profile_with_options(_Config) ->
    ?assertEqual({error, {not_started, ipdata}}, httpc:info(ipdata)),
    {ok, Started} = application:ensure_all_started(ipdata),
    ?assert(lists:member(ipdata, Started)),
    {ok, Opts} = httpc:get_options([max_sessions, max_keep_alive_length,
                                    keep_alive_timeout], ipdata),
    ?assertEqual(16, proplists:get_value(max_sessions, Opts)),
    ?assertEqual(4, proplists:get_value(max_keep_alive_length, Opts)),
    ?assertEqual(60000, proplists:get_value(keep_alive_timeout, Opts)),
    ?assertEqual(lists:sort(ipdata_http:profile_options()), lists:sort(Opts)),
    %% nothing has been requested yet: no connection
    ?assertEqual({[], [], []}, httpc:which_sessions(ipdata)).

start_accepts_already_started_profile(_Config) ->
    {ok, _} = inets:start(httpc, [{profile, ipdata}]),
    {ok, _} = application:ensure_all_started(ipdata),
    ?assertEqual({ok, [{max_sessions, 16}]},
                 httpc:get_options([max_sessions], ipdata)).

httpc_options_env_applied_on_start(_Config) ->
    ok = application:set_env(ipdata, httpc_options,
                             [{max_sessions, 3}, {keep_alive_timeout, 1000}]),
    {ok, _} = application:ensure_all_started(ipdata),
    {ok, Opts} = httpc:get_options([max_sessions, max_keep_alive_length,
                                    keep_alive_timeout], ipdata),
    ?assertEqual(3, proplists:get_value(max_sessions, Opts)),
    ?assertEqual(1000, proplists:get_value(keep_alive_timeout, Opts)),
    ?assertEqual(4, proplists:get_value(max_keep_alive_length, Opts)).

stop_removes_profile(_Config) ->
    {ok, _} = application:ensure_all_started(ipdata),
    ?assertMatch({ok, _}, httpc:get_options([max_sessions], ipdata)),
    ok = application:stop(ipdata),
    ?assertEqual({error, {not_started, ipdata}}, httpc:info(ipdata)),
    %% and the application can be started again
    {ok, _} = application:ensure_all_started(ipdata),
    ?assertMatch({ok, _}, httpc:get_options([max_sessions], ipdata)).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

reset() ->
    _ = application:stop(ipdata),
    _ = inets:stop(httpc, ipdata),
    ok = application:unset_env(ipdata, httpc_options).
