%%%-------------------------------------------------------------------
%%% @doc Common Test suite for the ipdata public API.
%%%
%%% Uses meck to mock `ipdata_http' so tests run without network
%%% access or a real API key.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-compile(export_all).

%%--------------------------------------------------------------------
%% Suite setup
%%--------------------------------------------------------------------

all() ->
    [new_with_defaults,
     new_with_eu_endpoint,
     new_with_custom_endpoint,
     new_with_custom_timeout,
     new_empty_key_rejected,
     new_non_binary_key_rejected,
     lookup_own_ip,
     lookup_specific_ip,
     lookup_with_fields,
     lookup_api_error,
     lookup_network_error,
     bulk_lookup,
     bulk_lookup_with_fields,
     bulk_empty_list_rejected,
     bulk_too_many_ips_rejected,
     bulk_api_error,
     lookup_returns_new_fields_unchanged,
     lookup_with_new_field_names,
     bulk_with_new_field_names].

init_per_suite(Config) ->
    application:ensure_all_started(meck),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    meck:new(ipdata_http, [passthrough]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    meck:unload(ipdata_http),
    ok.

%%--------------------------------------------------------------------
%% Client creation tests
%%--------------------------------------------------------------------

new_with_defaults(_Config) ->
    {ok, Client} = ipdata:new(<<"test-key">>),
    ?assertEqual(<<"test-key">>, maps:get(api_key, Client)),
    ?assertEqual(<<"https://api.ipdata.co">>, maps:get(endpoint, Client)),
    ?assertEqual(5000, maps:get(timeout, Client)).

new_with_eu_endpoint(_Config) ->
    {ok, Client} = ipdata:new(<<"test-key">>, #{endpoint => eu}),
    ?assertEqual(<<"https://eu-api.ipdata.co">>, maps:get(endpoint, Client)).

new_with_custom_endpoint(_Config) ->
    URL = <<"https://custom.example.com">>,
    {ok, Client} = ipdata:new(<<"test-key">>, #{endpoint => URL}),
    ?assertEqual(URL, maps:get(endpoint, Client)).

new_with_custom_timeout(_Config) ->
    {ok, Client} = ipdata:new(<<"test-key">>, #{timeout => 10000}),
    ?assertEqual(10000, maps:get(timeout, Client)).

new_empty_key_rejected(_Config) ->
    ?assertMatch({error, {invalid_input, _}}, ipdata:new(<<>>)).

new_non_binary_key_rejected(_Config) ->
    ?assertMatch({error, {invalid_input, _}}, ipdata:new("string-key", #{})).

%%--------------------------------------------------------------------
%% Lookup tests
%%--------------------------------------------------------------------

lookup_own_ip(_Config) ->
    MockResponse = #{<<"ip">> => <<"1.2.3.4">>,
                     <<"country_name">> => <<"United States">>},
    meck:expect(ipdata_http, get,
                fun("https://api.ipdata.co?api-key=test-key", [], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Result} = ipdata:lookup(Client),
    ?assertEqual(<<"1.2.3.4">>, maps:get(<<"ip">>, Result)),
    ?assertEqual(<<"United States">>, maps:get(<<"country_name">>, Result)),
    ?assert(meck:validate(ipdata_http)).

lookup_specific_ip(_Config) ->
    MockResponse = sample_ip_response(),
    meck:expect(ipdata_http, get,
                fun("https://api.ipdata.co/8.8.8.8?api-key=test-key", [], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>),
    ?assertEqual(<<"8.8.8.8">>, maps:get(<<"ip">>, Result)),
    ?assertEqual(<<"US">>, maps:get(<<"country_code">>, Result)),
    ?assert(meck:validate(ipdata_http)).

lookup_with_fields(_Config) ->
    MockResponse = #{<<"ip">> => <<"8.8.8.8">>,
                     <<"country_name">> => <<"United States">>},
    meck:expect(ipdata_http, get,
                fun("https://api.ipdata.co/8.8.8.8?api-key=test-key&fields=ip,country_name",
                    [], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>,
                                 [<<"ip">>, <<"country_name">>]),
    ?assertEqual(<<"8.8.8.8">>, maps:get(<<"ip">>, Result)),
    ?assert(meck:validate(ipdata_http)).

lookup_api_error(_Config) ->
    meck:expect(ipdata_http, get,
                fun(_, [], 5000) ->
                        {error, {http_error, 401,
                                 <<"You have not provided a valid API Key.">>}}
                end),
    {ok, Client} = ipdata:new(<<"bad-key">>),
    ?assertMatch({error, {http_error, 401, _}}, ipdata:lookup(Client, <<"8.8.8.8">>)),
    ?assert(meck:validate(ipdata_http)).

lookup_network_error(_Config) ->
    meck:expect(ipdata_http, get,
                fun(_, [], 5000) ->
                        {error, {request_failed, {failed_connect, timeout}}}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    ?assertMatch({error, {request_failed, _}}, ipdata:lookup(Client, <<"8.8.8.8">>)),
    ?assert(meck:validate(ipdata_http)).

%%--------------------------------------------------------------------
%% Bulk lookup tests
%%--------------------------------------------------------------------

bulk_lookup(_Config) ->
    MockResponse = [sample_ip_response(),
                    #{<<"ip">> => <<"1.1.1.1">>,
                      <<"country_name">> => <<"Australia">>}],
    meck:expect(ipdata_http, post,
                fun("https://api.ipdata.co/bulk?api-key=test-key", [],
                    [<<"8.8.8.8">>, <<"1.1.1.1">>], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Results} = ipdata:bulk(Client, [<<"8.8.8.8">>, <<"1.1.1.1">>]),
    ?assertEqual(2, length(Results)),
    ?assert(meck:validate(ipdata_http)).

bulk_lookup_with_fields(_Config) ->
    MockResponse = [#{<<"ip">> => <<"8.8.8.8">>, <<"city">> => <<"Ashburn">>}],
    meck:expect(ipdata_http, post,
                fun("https://api.ipdata.co/bulk?api-key=test-key&fields=ip,city", [],
                    [<<"8.8.8.8">>], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Results} = ipdata:bulk(Client, [<<"8.8.8.8">>],
                                [<<"ip">>, <<"city">>]),
    ?assertEqual(1, length(Results)),
    ?assert(meck:validate(ipdata_http)).

bulk_empty_list_rejected(_Config) ->
    {ok, Client} = ipdata:new(<<"test-key">>),
    ?assertMatch({error, {invalid_input, _}}, ipdata:bulk(Client, [])).

bulk_too_many_ips_rejected(_Config) ->
    {ok, Client} = ipdata:new(<<"test-key">>),
    IPs = [<<"1.1.1.1">> || _ <- lists:seq(1, 101)],
    ?assertMatch({error, {invalid_input, _}}, ipdata:bulk(Client, IPs)).

bulk_api_error(_Config) ->
    meck:expect(ipdata_http, post,
                fun(_, [], _, 5000) ->
                        {error, {http_error, 403,
                                 <<"Bulk lookup requires a paid plan.">>}}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    ?assertMatch({error, {http_error, 403, _}},
                 ipdata:bulk(Client, [<<"8.8.8.8">>])),
    ?assert(meck:validate(ipdata_http)).

%%--------------------------------------------------------------------
%% New response fields
%%--------------------------------------------------------------------

%% is_satellite, is_anycast and the dated blocklist entries reach the
%% caller exactly as decoded: the API omits the two flags when false and
%% some feeds omit the dates, so absent keys stay absent.
lookup_returns_new_fields_unchanged(_Config) ->
    MockResponse = satellite_ip_response(),
    meck:expect(ipdata_http, get,
                fun("https://api.ipdata.co/98.97.34.0?api-key=test-key", [], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Result} = ipdata:lookup(Client, <<"98.97.34.0">>),
    ?assertEqual(MockResponse, Result),
    ?assertEqual(true, maps:get(<<"is_satellite">>, Result)),
    ?assertNot(maps:is_key(<<"is_anycast">>, Result)),
    ?assertEqual(false, maps:get(<<"is_anycast">>, Result, false)),
    [Dated, Undated] = maps:get(<<"blocklists">>, maps:get(<<"threat">>, Result)),
    ?assertEqual(<<"2026-10-31">>, maps:get(<<"first_seen">>, Dated)),
    ?assertEqual(2, maps:get(<<"days_seen">>, Dated)),
    ?assertEqual(undefined, maps:get(<<"first_seen">>, Undated, undefined)),
    ?assert(meck:validate(ipdata_http)).

%% The new names are valid field names for the fields parameter.
lookup_with_new_field_names(_Config) ->
    MockResponse = #{<<"ip">> => <<"8.8.8.8">>, <<"is_anycast">> => true},
    meck:expect(ipdata_http, get,
                fun("https://api.ipdata.co/8.8.8.8?api-key=test-key&fields=ip,is_satellite,is_anycast",
                    [], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>,
                                 [<<"ip">>, <<"is_satellite">>, <<"is_anycast">>]),
    ?assertEqual(true, maps:get(<<"is_anycast">>, Result)),
    ?assertEqual(false, maps:get(<<"is_satellite">>, Result, false)),
    ?assert(meck:validate(ipdata_http)).

bulk_with_new_field_names(_Config) ->
    MockResponse = [#{<<"ip">> => <<"98.97.34.0">>, <<"is_satellite">> => true},
                    #{<<"ip">> => <<"8.8.8.8">>, <<"is_anycast">> => true}],
    meck:expect(ipdata_http, post,
                fun("https://api.ipdata.co/bulk?api-key=test-key&fields=ip,is_satellite,is_anycast",
                    [], [<<"98.97.34.0">>, <<"8.8.8.8">>], 5000) ->
                        {ok, MockResponse}
                end),
    {ok, Client} = ipdata:new(<<"test-key">>),
    {ok, [Satellite, Anycast]} =
        ipdata:bulk(Client, [<<"98.97.34.0">>, <<"8.8.8.8">>],
                    [<<"ip">>, <<"is_satellite">>, <<"is_anycast">>]),
    ?assertEqual(true, maps:get(<<"is_satellite">>, Satellite)),
    ?assertEqual(false, maps:get(<<"is_anycast">>, Satellite, false)),
    ?assertEqual(true, maps:get(<<"is_anycast">>, Anycast)),
    ?assertEqual(false, maps:get(<<"is_satellite">>, Anycast, false)),
    ?assert(meck:validate(ipdata_http)).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

%% Decoded shape of a satellite ISP response (is_anycast omitted) whose
%% blocklist has one dated entry and one from a feed without dates.
satellite_ip_response() ->
    #{<<"ip">> => <<"98.97.34.0">>,
      <<"is_satellite">> => true,
      <<"is_eu">> => false,
      <<"city">> => <<"Seattle">>,
      <<"country_code">> => <<"US">>,
      <<"threat">> => #{
          <<"is_vpn">> => false,
          <<"is_threat">> => false,
          <<"blocklists">> => [
              #{<<"name">> => <<"Gluetun">>,
                <<"site">> => <<"https://github.com/qdm12/gluetun">>,
                <<"type">> => <<"vpn">>,
                <<"days_seen">> => 2,
                <<"first_seen">> => <<"2026-10-31">>,
                <<"last_seen">> => <<"2026-11-02">>},
              #{<<"name">> => <<"ipdata">>,
                <<"site">> => <<"https://ipdata.co">>,
                <<"type">> => <<"vpn">>}
          ]
      },
      <<"count">> => <<"0">>}.

sample_ip_response() ->
    #{<<"ip">> => <<"8.8.8.8">>,
      <<"is_eu">> => false,
      <<"city">> => <<"Ashburn">>,
      <<"region">> => <<"Virginia">>,
      <<"region_code">> => <<"VA">>,
      <<"region_type">> => <<"state">>,
      <<"country_name">> => <<"United States">>,
      <<"country_code">> => <<"US">>,
      <<"continent_name">> => <<"North America">>,
      <<"continent_code">> => <<"NA">>,
      <<"latitude">> => 39.03,
      <<"longitude">> => -77.5,
      <<"postal">> => <<"20149">>,
      <<"calling_code">> => <<"1">>,
      <<"flag">> => <<"https://ipdata.co/flags/us.png">>,
      <<"emoji_flag">> => <<240, 159, 135, 186, 240, 159, 135, 184>>,
      <<"emoji_unicode">> => <<"U+1F1FA U+1F1F8">>,
      <<"asn">> => #{
          <<"asn">> => <<"AS15169">>,
          <<"name">> => <<"Google LLC">>,
          <<"domain">> => <<"google.com">>,
          <<"route">> => <<"8.8.8.0/24">>,
          <<"type">> => <<"business">>
      },
      <<"company">> => #{
          <<"name">> => <<"Google LLC">>,
          <<"domain">> => <<"google.com">>,
          <<"network">> => <<"8.8.8.0/24">>,
          <<"type">> => <<"business">>
      },
      <<"languages">> => [
          #{<<"name">> => <<"English">>,
            <<"native">> => <<"English">>,
            <<"code">> => <<"en">>}
      ],
      <<"currency">> => #{
          <<"name">> => <<"US Dollar">>,
          <<"code">> => <<"USD">>,
          <<"symbol">> => <<"$">>,
          <<"native">> => <<"$">>,
          <<"plural">> => <<"US dollars">>
      },
      <<"time_zone">> => #{
          <<"name">> => <<"America/New_York">>,
          <<"abbr">> => <<"EST">>,
          <<"offset">> => <<"-0500">>,
          <<"is_dst">> => false,
          <<"current_time">> => <<"2025-01-01T12:00:00-05:00">>
      },
      <<"threat">> => #{
          <<"is_tor">> => false,
          <<"is_vpn">> => false,
          <<"is_icloud_relay">> => false,
          <<"is_proxy">> => false,
          <<"is_datacenter">> => true,
          <<"is_anonymous">> => false,
          <<"is_known_attacker">> => false,
          <<"is_known_abuser">> => false,
          <<"is_threat">> => false,
          <<"is_bogon">> => false,
          <<"blocklists">> => [],
          <<"scores">> => #{
              <<"vpn_score">> => 0,
              <<"proxy_score">> => 0,
              <<"threat_score">> => 0,
              <<"trust_score">> => 0
          }
      },
      <<"carrier">> => #{
          <<"name">> => <<"Google">>,
          <<"mcc">> => <<"310">>,
          <<"mnc">> => <<"004">>
      },
      <<"count">> => <<"1">>}.
