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
     post_success,
     post_api_error,
     post_network_error].

init_per_suite(Config) ->
    application:ensure_all_started(meck),
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
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts) ->
                        {ok, {{"HTTP/1.1", 200, "OK"}, [], Body}}
                end),
    {ok, Result} = ipdata_http:get("https://api.ipdata.co?api-key=test", [], 5000),
    ?assertEqual(<<"1.2.3.4">>, maps:get(<<"ip">>, Result)),
    ?assert(meck:validate(httpc)).

get_json_error(_Config) ->
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts) ->
                        {ok, {{"HTTP/1.1", 200, "OK"}, [], <<"not json">>}}
                end),
    ?assertMatch({error, {json_error, _}}, ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

get_api_error_with_message(_Config) ->
    Body = jsx:encode(#{<<"message">> => <<"Invalid API key">>}),
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts) ->
                        {ok, {{"HTTP/1.1", 401, "Unauthorized"}, [], Body}}
                end),
    ?assertMatch({error, {http_error, 401, <<"Invalid API key">>}},
                 ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

get_api_error_without_json(_Config) ->
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts) ->
                        {ok, {{"HTTP/1.1", 500, "Server Error"}, [],
                              <<"Internal Server Error">>}}
                end),
    ?assertMatch({error, {http_error, 500, <<"Internal Server Error">>}},
                 ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

get_network_error(_Config) ->
    meck:expect(httpc, request,
                fun(get, {_URL, _Headers}, _HttpOpts, _Opts) ->
                        {error, {failed_connect,
                                 [{to_address, {"api.ipdata.co", 443}},
                                  {inet, [inet], timeout}]}}
                end),
    ?assertMatch({error, {request_failed, _}},
                 ipdata_http:get("https://example.com", [], 5000)),
    ?assert(meck:validate(httpc)).

%%--------------------------------------------------------------------
%% POST tests
%%--------------------------------------------------------------------

post_success(_Config) ->
    ResponseBody = jsx:encode([#{<<"ip">> => <<"8.8.8.8">>},
                                #{<<"ip">> => <<"1.1.1.1">>}]),
    meck:expect(httpc, request,
                fun(post, {_URL, _Headers, "application/json", ReqBody},
                    _HttpOpts, _Opts) ->
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
                fun(post, {_URL, _Headers, _CT, _Body}, _HttpOpts, _Opts) ->
                        {ok, {{"HTTP/1.1", 403, "Forbidden"}, [], Body}}
                end),
    ?assertMatch({error, {http_error, 403, <<"Forbidden">>}},
                 ipdata_http:post("https://example.com/bulk", [],
                                  [<<"8.8.8.8">>], 5000)),
    ?assert(meck:validate(httpc)).

post_network_error(_Config) ->
    meck:expect(httpc, request,
                fun(post, {_URL, _Headers, _CT, _Body}, _HttpOpts, _Opts) ->
                        {error, timeout}
                end),
    ?assertMatch({error, {request_failed, timeout}},
                 ipdata_http:post("https://example.com/bulk", [],
                                  [<<"8.8.8.8">>], 5000)),
    ?assert(meck:validate(httpc)).
