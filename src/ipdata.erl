%%%-------------------------------------------------------------------
%%% @doc Erlang client library for the ipdata.co API.
%%%
%%% Provides IP geolocation, threat intelligence, ASN, carrier,
%%% timezone, currency, and other IP metadata lookups.
%%%
%%% == Quick Start ==
%%%
%%% ```
%%% application:ensure_all_started(ipdata).
%%% {ok, Client} = ipdata:new(<<"YOUR_API_KEY">>).
%%% {ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>).
%%% maps:get(<<"country_name">>, Result).
%%% '''
%%%
%%% == Endpoints ==
%%%
%%% By default the global endpoint is used. You can specify the EU
%%% endpoint or a custom URL via options:
%%%
%%% ```
%%% {ok, Client} = ipdata:new(<<"KEY">>, #{endpoint => eu}).
%%% {ok, Client} = ipdata:new(<<"KEY">>, #{endpoint => <<"https://custom.example.com">>}).
%%% '''
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata).

%% Public API
-export([new/1, new/2,
         lookup/1, lookup/2, lookup/3,
         bulk/2, bulk/3]).

%% Types
-export_type([client/0, opts/0]).

-type client() :: #{
    api_key := binary(),
    endpoint := binary(),
    timeout := pos_integer()
}.

-type opts() :: #{
    endpoint => global | eu | binary(),
    timeout => pos_integer()
}.

-define(DEFAULT_ENDPOINT, <<"https://api.ipdata.co">>).
-define(EU_ENDPOINT, <<"https://eu-api.ipdata.co">>).
-define(DEFAULT_TIMEOUT, 5000).
-define(MAX_BULK_IPS, 100).

%%--------------------------------------------------------------------
%% @doc Create a new ipdata client with default options.
%%
%% Uses the global endpoint and a 5 second timeout.
%% @end
%%--------------------------------------------------------------------
-spec new(ApiKey :: binary()) -> {ok, client()} | {error, term()}.
new(ApiKey) ->
    new(ApiKey, #{}).

%%--------------------------------------------------------------------
%% @doc Create a new ipdata client with custom options.
%%
%% Options:
%% <ul>
%%   <li>`endpoint' - `global' (default), `eu', or a custom URL binary</li>
%%   <li>`timeout' - Request timeout in milliseconds (default 5000)</li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec new(ApiKey :: binary(), Opts :: opts()) -> {ok, client()} | {error, term()}.
new(<<>>, _Opts) ->
    {error, {invalid_input, <<"API key must not be empty">>}};
new(ApiKey, Opts) when is_binary(ApiKey), is_map(Opts) ->
    Endpoint = resolve_endpoint(maps:get(endpoint, Opts, global)),
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
    {ok, #{api_key => ApiKey,
           endpoint => Endpoint,
           timeout => Timeout}};
new(_ApiKey, _Opts) ->
    {error, {invalid_input, <<"API key must be a binary">>}}.

%%--------------------------------------------------------------------
%% @doc Look up the IP address of the calling machine.
%% @end
%%--------------------------------------------------------------------
-spec lookup(Client :: client()) -> {ok, map()} | {error, term()}.
lookup(Client) ->
    lookup(Client, <<>>, []).

%%--------------------------------------------------------------------
%% @doc Look up a specific IP address.
%%
%% The IP can be an IPv4 or IPv6 address as a binary string.
%% @end
%%--------------------------------------------------------------------
-spec lookup(Client :: client(), IP :: binary()) ->
    {ok, map()} | {error, term()}.
lookup(Client, IP) ->
    lookup(Client, IP, []).

%%--------------------------------------------------------------------
%% @doc Look up a specific IP address, returning only the specified fields.
%%
%% Fields is a list of field name binaries to include in the response.
%% Pass an empty IP binary (`<<>>') to look up the caller's own IP.
%%
%% Example:
%% ```
%% ipdata:lookup(Client, <<"8.8.8.8">>, [<<"country_name">>, <<"city">>]).
%% '''
%% @end
%%--------------------------------------------------------------------
-spec lookup(Client :: client(), IP :: binary(), Fields :: [binary()]) ->
    {ok, map()} | {error, term()}.
lookup(#{api_key := ApiKey, endpoint := Endpoint, timeout := Timeout}, IP, Fields) ->
    Path = case IP of
               <<>> -> <<>>;
               _    -> <<"/", IP/binary>>
           end,
    URL = build_url(Endpoint, Path, ApiKey, Fields),
    ipdata_http:get(binary_to_list(URL), [], Timeout).

%%--------------------------------------------------------------------
%% @doc Look up multiple IP addresses in a single request.
%%
%% Accepts up to 100 IP addresses. Requires a paid API key.
%% @end
%%--------------------------------------------------------------------
-spec bulk(Client :: client(), IPs :: [binary()]) ->
    {ok, [map()]} | {error, term()}.
bulk(Client, IPs) ->
    bulk(Client, IPs, []).

%%--------------------------------------------------------------------
%% @doc Look up multiple IP addresses, returning only the specified fields.
%%
%% Accepts up to 100 IP addresses. Requires a paid API key.
%%
%% Example:
%% ```
%% ipdata:bulk(Client, [<<"8.8.8.8">>, <<"1.1.1.1">>],
%%             [<<"country_name">>, <<"ip">>]).
%% '''
%% @end
%%--------------------------------------------------------------------
-spec bulk(Client :: client(), IPs :: [binary()], Fields :: [binary()]) ->
    {ok, [map()]} | {error, term()}.
bulk(_Client, [], _Fields) ->
    {error, {invalid_input, <<"At least one IP address is required">>}};
bulk(_Client, IPs, _Fields) when length(IPs) > ?MAX_BULK_IPS ->
    {error, {invalid_input, <<"Bulk lookup supports at most 100 IP addresses">>}};
bulk(#{api_key := ApiKey, endpoint := Endpoint, timeout := Timeout}, IPs, Fields) ->
    URL = build_url(Endpoint, <<"/bulk">>, ApiKey, Fields),
    ipdata_http:post(binary_to_list(URL), [], IPs, Timeout).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

-spec resolve_endpoint(global | eu | binary()) -> binary().
resolve_endpoint(global) -> ?DEFAULT_ENDPOINT;
resolve_endpoint(eu) -> ?EU_ENDPOINT;
resolve_endpoint(URL) when is_binary(URL) -> URL.

-spec build_url(Endpoint :: binary(), Path :: binary(),
                ApiKey :: binary(), Fields :: [binary()]) -> binary().
build_url(Endpoint, Path, ApiKey, Fields) ->
    Base = <<Endpoint/binary, Path/binary, "?api-key=", ApiKey/binary>>,
    case Fields of
        [] ->
            Base;
        _ ->
            FieldStr = join_fields(Fields),
            <<Base/binary, "&fields=", FieldStr/binary>>
    end.

-spec join_fields(Fields :: [binary()]) -> binary().
join_fields([]) ->
    <<>>;
join_fields([F]) ->
    F;
join_fields([F | Rest]) ->
    lists:foldl(fun(Field, Acc) ->
                        <<Acc/binary, ",", Field/binary>>
                end, F, Rest).
