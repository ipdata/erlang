%%%-------------------------------------------------------------------
%%% @doc HTTP transport layer for the ipdata API.
%%%
%%% Wraps OTP's `httpc' module to provide GET and POST requests
%%% with proper TLS configuration, JSON parsing, and error handling.
%%%
%%% Every request goes through a dedicated `httpc' profile named
%%% `ipdata' that keeps persistent HTTP/1.1 keep-alive connections to
%%% the API, so the TCP and TLS handshake is paid once per connection
%%% instead of once per request. The profile is started by
%%% `ipdata_app' when the application starts; if the application was
%%% never started, the first request starts it on demand.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_http).

-export([get/3, post/4]).
-export([start_profile/0, profile_options/0]).

%% Name of the httpc profile owned by the ipdata application.
-define(PROFILE, ipdata).

%% Default profile options, overridable through the `httpc_options'
%% application environment key (see profile_options/0).
-define(DEFAULT_PROFILE_OPTIONS,
        [{max_sessions, 16},
         {max_keep_alive_length, 4},
         {keep_alive_timeout, 60000}]).

-define(USER_AGENT_PREFIX, "erlang-ipdata/").
-define(UNKNOWN_VSN, "unknown").
-define(CONTENT_TYPE_JSON, "application/json").

-type method() :: get | post.
-type headers() :: [{string(), string()}].
%% The two httpc request shapes used here: without and with a body.
-type request() :: {string(), headers()}
                 | {string(), headers(), string(), binary()}.
-type http_options() :: [{timeout, pos_integer()}
                         | {connect_timeout, pos_integer()}
                         | {ssl, [ssl:tls_client_option()]}].
-type request_options() :: [{body_format, binary}].

%%--------------------------------------------------------------------
%% @doc Perform an HTTP GET request.
%%
%% Returns the decoded JSON response body on success, or an error
%% tuple on failure.
%% @end
%%--------------------------------------------------------------------
-spec get(URL :: string(), Headers :: [{string(), string()}],
          Timeout :: pos_integer()) ->
    {ok, jsx:json_term()} | {error, term()}.
get(URL, Headers, Timeout) ->
    AllHeaders = [{"User-Agent", user_agent()},
                  {"Accept", ?CONTENT_TYPE_JSON} | Headers],
    HttpOpts = http_options(Timeout),
    Opts = [{body_format, binary}],
    handle_response(request(get, {URL, AllHeaders}, HttpOpts, Opts)).

%%--------------------------------------------------------------------
%% @doc Perform an HTTP POST request with a JSON body.
%%
%% The body term is encoded to JSON before sending. Returns the
%% decoded JSON response body on success, or an error tuple on
%% failure.
%%
%% A POST is not idempotent, so `httpc' hands a request back with
%% `{error, socket_closed_remotely}' when the server closed the
%% connection before answering it. That request is retried exactly
%% once; `httpc' has already discarded the closed connection, so the
%% retry goes out on a fresh one. HTTP error statuses are never
%% retried.
%% @end
%%--------------------------------------------------------------------
-spec post(URL :: string(), Headers :: [{string(), string()}],
           Body :: jsx:json_term(), Timeout :: pos_integer()) ->
    {ok, jsx:json_term()} | {error, term()}.
post(URL, Headers, Body, Timeout) ->
    AllHeaders = [{"User-Agent", user_agent()},
                  {"Accept", ?CONTENT_TYPE_JSON} | Headers],
    HttpOpts = http_options(Timeout),
    Opts = [{body_format, binary}],
    EncodedBody = jsx:encode(Body),
    Request = {URL, AllHeaders, ?CONTENT_TYPE_JSON, EncodedBody},
    handle_response(post_with_stale_retry(Request, HttpOpts, Opts)).

%%--------------------------------------------------------------------
%% @doc Start the `ipdata' httpc profile and apply profile_options/0.
%%
%% The profile is started under the `inets' supervision tree, so
%% `inets' must be running. An already running profile is accepted
%% and its options are (re)applied, which makes the function safe to
%% call more than once.
%% @end
%%--------------------------------------------------------------------
-spec start_profile() -> ok | {error, term()}.
start_profile() ->
    case inets:start(httpc, [{profile, ?PROFILE}]) of
        {ok, _Pid} ->
            httpc:set_options(profile_options(), ?PROFILE);
        {error, {already_started, _Pid}} ->
            httpc:set_options(profile_options(), ?PROFILE);
        {error, _Reason} = Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @doc Options applied to the `ipdata' httpc profile.
%%
%% The defaults keep up to 16 persistent connections per host, queue
%% at most 4 requests on each of them, and close a connection after
%% 60 seconds idle:
%%
%% ```
%% [{max_sessions, 16}, {max_keep_alive_length, 4}, {keep_alive_timeout, 60000}]
%% '''
%%
%% Each entry can be overridden, and further `httpc:set_options/2'
%% options added, through the `httpc_options' key of the `ipdata'
%% application environment:
%%
%% ```
%% {ipdata, [{httpc_options, [{max_sessions, 4},
%%                            {https_proxy, {{"proxy.example.com", 3128}, []}}]}]}
%% '''
%% @end
%%--------------------------------------------------------------------
-spec profile_options() -> [{atom(), term()}].
profile_options() ->
    Overrides = application:get_env(ipdata, httpc_options, []),
    lists:ukeymerge(1, lists:ukeysort(1, Overrides),
                    lists:ukeysort(1, ?DEFAULT_PROFILE_OPTIONS)).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

%% Issue a request through the profile, starting the profile on demand
%% when the application was never started (or has been stopped) and
%% retrying the request once.
-spec request(method(), request(), http_options(), request_options()) ->
    {ok, term()} | {error, term()}.
request(Method, Request, HttpOpts, Opts) ->
    case profile_request(Method, Request, HttpOpts, Opts) of
        {error, {not_started, ?PROFILE}} ->
            case start_profile() of
                ok ->
                    profile_request(Method, Request, HttpOpts, Opts);
                {error, _Reason} = Error ->
                    Error
            end;
        Result ->
            Result
    end.

%% Retry a POST exactly once when the server closed the connection
%% before any response arrived (see post/4).
-spec post_with_stale_retry(request(), http_options(), request_options()) ->
    {ok, term()} | {error, term()}.
post_with_stale_retry(Request, HttpOpts, Opts) ->
    case request(post, Request, HttpOpts, Opts) of
        {error, socket_closed_remotely} ->
            request(post, Request, HttpOpts, Opts);
        Result ->
            Result
    end.

%% httpc:request/5 is documented to return {error, {not_started, Profile}}
%% when the profile is not running, but OTP releases up to and including
%% 28 catch the wrong exception class (error instead of exit) and let the
%% gen_server noproc exit through instead. Normalise both shapes.
-spec profile_request(method(), request(), http_options(), request_options()) ->
    {ok, term()} | {error, term()}.
profile_request(Method, Request, HttpOpts, Opts) ->
    try
        httpc:request(Method, Request, HttpOpts, Opts, ?PROFILE)
    catch
        exit:{noproc, {gen_server, call, _}} ->
            {error, {not_started, ?PROFILE}}
    end.

%% The User-Agent carries the version of the running ipdata application
%% rather than a hard-coded string, so it cannot go stale.
-spec user_agent() -> nonempty_string().
user_agent() ->
    ?USER_AGENT_PREFIX ++ app_vsn().

-spec app_vsn() -> string().
app_vsn() ->
    case application:get_key(ipdata, vsn) of
        {ok, Vsn} when is_list(Vsn) ->
            Vsn;
        _ ->
            %% Not loaded yet (the application was never started):
            %% loading it is cheap and makes the version available.
            _ = application:load(ipdata),
            case application:get_key(ipdata, vsn) of
                {ok, Vsn} when is_list(Vsn) -> Vsn;
                _ -> ?UNKNOWN_VSN
            end
    end.

-spec http_options(Timeout :: pos_integer()) -> list().
http_options(Timeout) ->
    [{timeout, Timeout},
     {connect_timeout, Timeout},
     {ssl, ssl_options()}].

%% TLS 1.3 session tickets let a connection opened after the idle
%% timeout resume the previous TLS session instead of doing a full
%% handshake. ALPN is deliberately not advertised: httpc only speaks
%% HTTP/1.1, and offering h2 would make the server select it.
-spec ssl_options() -> [ssl:tls_client_option()].
ssl_options() ->
    [{verify, verify_peer},
     {depth, 100},
     {cacerts, public_key:cacerts_get()},
     {customize_hostname_check,
      [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]},
     {session_tickets, auto}].

-spec handle_response({ok, term()} | {error, term()}) ->
    {ok, jsx:json_term()} | {error, term()}.
handle_response({ok, {{_, 200, _}, _RespHeaders, Body}}) ->
    try jsx:decode(Body, [return_maps]) of
        Decoded -> {ok, Decoded}
    catch
        error:Reason -> {error, {json_error, Reason}}
    end;
handle_response({ok, {{_, StatusCode, _}, _RespHeaders, Body}}) ->
    Message = extract_error_message(Body),
    {error, {http_error, StatusCode, Message}};
handle_response({error, Reason}) ->
    {error, {request_failed, Reason}}.

-spec extract_error_message(term()) -> binary().
extract_error_message(Body) when is_binary(Body), byte_size(Body) > 0 ->
    try jsx:decode(Body, [return_maps]) of
        #{<<"message">> := Msg} -> Msg;
        _ -> Body
    catch
        _:_ -> Body
    end;
extract_error_message(_) ->
    <<"Unknown error">>.
