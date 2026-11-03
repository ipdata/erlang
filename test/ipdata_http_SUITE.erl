%%%-------------------------------------------------------------------
%%% @doc Common Test suite for the ipdata_http module.
%%%
%%% Uses meck to mock `httpc' to test HTTP request construction,
%%% response parsing, and error handling without network access.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_http_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-compile(export_all).

%%--------------------------------------------------------------------
%% Suite setup
%%--------------------------------------------------------------------

all() ->
    [get_success,
     get_json_error,
     get_api_error_with_message,
     get_api_error_without_json,
     get_network_error,
     get_uses_ipdata_profile,
     get_sends_user_agent_with_app_vsn,
     get_tls_options,
     post_success,
     post_api_error,
     post_network_error,
     post_uses_ipdata_profile,
     post_retries_once_on_socket_closed_remotely,
     post_retries_only_once,
     post_does_not_retry_http_errors,
     not_started_starts_profile_and_retries,
     not_started_noproc_exit_starts_profile_and_retries,
     not_started_profile_start_failure_is_request_failed,
     profile_options_defaults,
     profile_options_env_overrides].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(meck),
    %% Load (not start) the application so that its environment and
    %% version are available to the code under test.
    _ = application:load(ipdata),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    meck:new(httpc, [unstick, passthrough]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    meck:unload(httpc),
    ok.

%%--------------------------------------------------------------------
%% GET tests
%%--------------------------------------------------------------------

get_success(_Config) ->
    Body = jsx:encode(#{<<"ip">> => <<"1.2.3.4">>}),
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts, ipdata) ->
                        {ok, {{"HTTP/1.1", 200, "OK"}, [], Body}}
                end),
    {ok, Result} = ipdata_http:get("https://api.ipdata.co?api-key=test", [], 5000),
    ?assertEqual(<<"1.2.3.4">>, maps:get(<<"ip">>, Result)),
    ?assert(meck:validate(httpc)).

get_json_error(_Config) ->
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts, ipdata) ->
                        {ok, {{"HTTP/1.1", 200, "OK"}, [], <<"not json">>}}
                end),
    ?assertMatch({error, {json_error, _}}, ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

get_api_error_with_message(_Config) ->
    Body = jsx:encode(#{<<"message">> => <<"Invalid API key">>}),
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts, ipdata) ->
                        {ok, {{"HTTP/1.1", 401, "Unauthorized"}, [], Body}}
                end),
    ?assertMatch({error, {http_error, 401, <<"Invalid API key">>}},
                 ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

get_api_error_without_json(_Config) ->
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts, ipdata) ->
                        {ok, {{"HTTP/1.1", 500, "Server Error"}, [],
                              <<"Internal Server Error">>}}
                end),
    ?assertMatch({error, {http_error, 500, <<"Internal Server Error">>}},
                 ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

get_network_error(_Config) ->
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts, ipdata) ->
                        {error, {failed_connect,
                                 [{to_address, {"api.ipdata.co", 443}},
                                  {inet, [inet], timeout}]}}
                end),
    ?assertMatch({error, {request_failed, _}},
                 ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

%% Every request goes through httpc:request/5 with the ipdata profile.
get_uses_ipdata_profile(_Config) ->
    expect_response(get, 200, jsx:encode(#{})),
    {ok, _} = ipdata_http:get("https://api.ipdata.co?api-key=test", [], 5000),
    ?assertEqual(1, meck:num_calls(httpc, request, '_')),
    ?assert(meck:called(httpc, request, [get, '_', '_', '_', ipdata])),
    ?assert(meck:validate(httpc)).

%% The User-Agent carries the application version from the .app file.
get_sends_user_agent_with_app_vsn(_Config) ->
    {ok, Vsn} = application:get_key(ipdata, vsn),
    ?assert(is_list(Vsn) andalso Vsn =/= []),
    expect_response(get, 200, jsx:encode(#{})),
    {ok, _} = ipdata_http:get("https://api.ipdata.co?api-key=test",
                              [{"X-Extra", "1"}], 5000),
    {_URL, Headers} = meck:capture(first, httpc, request, '_', 2),
    ?assertEqual("erlang-ipdata/" ++ Vsn, proplists:get_value("User-Agent", Headers)),
    ?assertEqual("application/json", proplists:get_value("Accept", Headers)),
    %% caller-supplied headers are kept
    ?assertEqual("1", proplists:get_value("X-Extra", Headers)),
    ?assert(meck:validate(httpc)).

%% TLS verification stays on, TLS 1.3 session tickets are enabled and
%% ALPN is never advertised (httpc only speaks HTTP/1.1).
get_tls_options(_Config) ->
    expect_response(get, 200, jsx:encode(#{})),
    {ok, _} = ipdata_http:get("https://api.ipdata.co?api-key=test", [], 7000),
    HttpOpts = meck:capture(first, httpc, request, '_', 3),
    ?assertEqual(7000, proplists:get_value(timeout, HttpOpts)),
    ?assertEqual(7000, proplists:get_value(connect_timeout, HttpOpts)),
    {ssl, SslOpts} = lists:keyfind(ssl, 1, HttpOpts),
    ?assertEqual(verify_peer, proplists:get_value(verify, SslOpts)),
    ?assertEqual(auto, proplists:get_value(session_tickets, SslOpts)),
    ?assertNot(lists:keymember(alpn_advertised_protocols, 1, SslOpts)),
    ?assert(meck:validate(httpc)).

%%--------------------------------------------------------------------
%% POST tests
%%--------------------------------------------------------------------

post_success(_Config) ->
    ResponseBody = jsx:encode([#{<<"ip">> => <<"8.8.8.8">>},
                                #{<<"ip">> => <<"1.1.1.1">>}]),
    meck:expect(httpc, request,
                fun(post, {_URL, _Headers, "application/json", ReqBody},
                    _HttpOpts, _Opts, ipdata) ->
                        %% Verify the request body is valid JSON
                        _Decoded = jsx:decode(ReqBody, [return_maps]),
                        {ok, {{"HTTP/1.1", 200, "OK"}, [], ResponseBody}}
                end),
    {ok, Results} = ipdata_http:post("https://api.ipdata.co/bulk?api-key=test",
                                     [], [<<"8.8.8.8">>, <<"1.1.1.1">>], 5000),
    ?assertEqual(2, length(Results)),
    ?assert(meck:validate(httpc)).

post_api_error(_Config) ->
    Body = jsx:encode(#{<<"message">> => <<"Forbidden">>}),
    meck:expect(httpc, request,
                fun(post, {_URL, _Headers, _CT, _Body}, _HttpOpts, _Opts, ipdata) ->
                        {ok, {{"HTTP/1.1", 403, "Forbidden"}, [], Body}}
                end),
    ?assertMatch({error, {http_error, 403, <<"Forbidden">>}},
                 ipdata_http:post("https://example.com/bulk", [],
                                  [<<"8.8.8.8">>], 5000)),
    ?assert(meck:validate(httpc)).

post_network_error(_Config) ->
    meck:expect(httpc, request,
                fun(post, {_URL, _Headers, _CT, _Body}, _HttpOpts, _Opts, ipdata) ->
                        {error, timeout}
                end),
    ?assertMatch({error, {request_failed, timeout}},
                 ipdata_http:post("https://example.com/bulk", [],
                                  [<<"8.8.8.8">>], 5000)),
    %% a timeout is not a stale connection: no retry
    ?assertEqual(1, meck:num_calls(httpc, request, '_')),
    ?assert(meck:validate(httpc)).

post_uses_ipdata_profile(_Config) ->
    expect_response(post, 200, jsx:encode([#{<<"ip">> => <<"8.8.8.8">>}])),
    {ok, _} = ipdata_http:post("https://api.ipdata.co/bulk?api-key=test",
                               [], [<<"8.8.8.8">>], 5000),
    ?assertEqual(1, meck:num_calls(httpc, request, '_')),
    ?assert(meck:called(httpc, request, [post, '_', '_', '_', ipdata])),
    ?assert(meck:validate(httpc)).

%% A POST that httpc hands back because the server closed the connection
%% before answering is retried exactly once, with the same request.
post_retries_once_on_socket_closed_remotely(_Config) ->
    ResponseBody = jsx:encode([#{<<"ip">> => <<"8.8.8.8">>}]),
    meck:expect(httpc, request, 5,
                meck:seq([{error, socket_closed_remotely},
                          {ok, {{"HTTP/1.1", 200, "OK"}, [], ResponseBody}}])),
    {ok, Results} = ipdata_http:post("https://api.ipdata.co/bulk?api-key=test",
                                     [], [<<"8.8.8.8">>], 5000),
    ?assertEqual(1, length(Results)),
    ?assertEqual(2, meck:num_calls(httpc, request, [post, '_', '_', '_', ipdata])),
    [First, Second] = request_args(),
    ?assertEqual(First, Second),
    ?assert(meck:validate(httpc)).

post_retries_only_once(_Config) ->
    meck:expect(httpc, request, 5, {error, socket_closed_remotely}),
    ?assertEqual({error, {request_failed, socket_closed_remotely}},
                 ipdata_http:post("https://example.com/bulk", [],
                                  [<<"8.8.8.8">>], 5000)),
    ?assertEqual(2, meck:num_calls(httpc, request, '_')),
    ?assert(meck:validate(httpc)).

post_does_not_retry_http_errors(_Config) ->
    expect_response(post, 502, <<"Bad Gateway">>),
    ?assertEqual({error, {http_error, 502, <<"Bad Gateway">>}},
                 ipdata_http:post("https://example.com/bulk", [],
                                  [<<"8.8.8.8">>], 5000)),
    ?assertEqual(1, meck:num_calls(httpc, request, '_')),
    ?assert(meck:validate(httpc)).

%%--------------------------------------------------------------------
%% Profile lifecycle from the request path
%%--------------------------------------------------------------------

%% When the application was never started, the first request starts
%% the profile, applies its options and is retried once.
not_started_starts_profile_and_retries(_Config) ->
    ok = stop_profile(),
    Body = jsx:encode(#{<<"ip">> => <<"1.2.3.4">>}),
    meck:expect(httpc, request, 5,
                meck:seq([{error, {not_started, ipdata}},
                          {ok, {{"HTTP/1.1", 200, "OK"}, [], Body}}])),
    {ok, Result} = ipdata_http:get("https://api.ipdata.co?api-key=test", [], 5000),
    ?assertEqual(<<"1.2.3.4">>, maps:get(<<"ip">>, Result)),
    ?assertEqual(2, meck:num_calls(httpc, request, [get, '_', '_', '_', ipdata])),
    assert_profile_running(),
    ok = stop_profile(),
    ?assert(meck:validate(httpc)).

%% OTP's httpc:request/5 lets the gen_server noproc exit through instead
%% of returning {error, {not_started, Profile}}; both shapes are handled.
not_started_noproc_exit_starts_profile_and_retries(_Config) ->
    ok = stop_profile(),
    Body = jsx:encode([#{<<"ip">> => <<"8.8.8.8">>}]),
    Exit = {noproc, {gen_server, call, [httpc_ipdata, request, infinity]}},
    meck:expect(httpc, request, 5,
                meck:seq([meck:raise(exit, Exit),
                          {ok, {{"HTTP/1.1", 200, "OK"}, [], Body}}])),
    {ok, Results} = ipdata_http:post("https://api.ipdata.co/bulk?api-key=test",
                                     [], [<<"8.8.8.8">>], 5000),
    ?assertEqual(1, length(Results)),
    ?assertEqual(2, meck:num_calls(httpc, request, [post, '_', '_', '_', ipdata])),
    assert_profile_running(),
    ok = stop_profile(),
    ?assert(meck:validate(httpc)).

%% If the profile cannot be started (inets is down) the request fails
%% with the usual request_failed error instead of crashing.
not_started_profile_start_failure_is_request_failed(_Config) ->
    ok = stop_profile(),
    meck:new(inets, [unstick, passthrough]),
    try
        meck:expect(inets, start,
                    fun(httpc, [{profile, ipdata}]) -> {error, inets_not_started} end),
        meck:expect(httpc, request, 5, {error, {not_started, ipdata}}),
        ?assertEqual({error, {request_failed, inets_not_started}},
                     ipdata_http:get("https://api.ipdata.co?api-key=test", [], 5000)),
        ?assertEqual(1, meck:num_calls(httpc, request, '_')),
        ?assert(meck:validate(inets)),
        ?assert(meck:validate(httpc))
    after
        meck:unload(inets)
    end.

%%--------------------------------------------------------------------
%% Profile options
%%--------------------------------------------------------------------

profile_options_defaults(_Config) ->
    ok = application:unset_env(ipdata, httpc_options),
    ?assertEqual([{keep_alive_timeout, 60000},
                  {max_keep_alive_length, 4},
                  {max_sessions, 16}],
                 lists:sort(ipdata_http:profile_options())).

%% httpc_options entries override the defaults key by key and may add
%% further httpc options.
profile_options_env_overrides(_Config) ->
    Proxy = {{"proxy.example.com", 3128}, []},
    ok = application:set_env(ipdata, httpc_options,
                             [{max_sessions, 2}, {https_proxy, Proxy}]),
    try
        Opts = ipdata_http:profile_options(),
        ?assertEqual(4, length(Opts)),
        ?assertEqual(2, proplists:get_value(max_sessions, Opts)),
        ?assertEqual(4, proplists:get_value(max_keep_alive_length, Opts)),
        ?assertEqual(60000, proplists:get_value(keep_alive_timeout, Opts)),
        ?assertEqual(Proxy, proplists:get_value(https_proxy, Opts))
    after
        ok = application:unset_env(ipdata, httpc_options)
    end.

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

expect_response(Method, Status, Body) ->
    meck:expect(httpc, request,
                fun(M, _Request, _HttpOpts, _Opts, ipdata) when M =:= Method ->
                        {ok, {{"HTTP/1.1", Status, "Reason"}, [], Body}}
                end).

%% Argument lists of every recorded httpc:request/5 call, in order.
request_args() ->
    [Args || {_Pid, {httpc, request, Args}, _Result} <- meck:history(httpc)].

stop_profile() ->
    _ = inets:stop(httpc, ipdata),
    ok.

assert_profile_running() ->
    ?assertMatch({error, {already_started, _}},
                 inets:start(httpc, [{profile, ipdata}])),
    {ok, Opts} = httpc:get_options([max_sessions, max_keep_alive_length,
                                    keep_alive_timeout], ipdata),
    ?assertEqual(lists:sort(ipdata_http:profile_options()), lists:sort(Opts)).
