%%%-------------------------------------------------------------------
%%% @doc HTTP transport layer for the ipdata API.
%%%
%%% Wraps OTP's `httpc' module to provide GET and POST requests
%%% with proper TLS configuration, JSON parsing, and error handling.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_http).

-export([get/3, post/4]).

-define(USER_AGENT, "erlang-ipdata/1.0.0").
-define(CONTENT_TYPE_JSON, "application/json").

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
    AllHeaders = [{"User-Agent", ?USER_AGENT} | Headers],
    HttpOpts = http_options(Timeout),
    Opts = [{body_format, binary}],
    handle_response(
        httpc:request(get, {URL, AllHeaders}, HttpOpts, Opts)
    ).

%%--------------------------------------------------------------------
%% @doc Perform an HTTP POST request with a JSON body.
%%
%% The body term is encoded to JSON before sending. Returns the
%% decoded JSON response body on success, or an error tuple on
%% failure.
%% @end
%%--------------------------------------------------------------------
-spec post(URL :: string(), Headers :: [{string(), string()}],
           Body :: jsx:json_term(), Timeout :: pos_integer()) ->
    {ok, jsx:json_term()} | {error, term()}.
post(URL, Headers, Body, Timeout) ->
    AllHeaders = [{"User-Agent", ?USER_AGENT} | Headers],
    HttpOpts = http_options(Timeout),
    Opts = [{body_format, binary}],
    EncodedBody = jsx:encode(Body),
    handle_response(
        httpc:request(post,
                      {URL, AllHeaders, ?CONTENT_TYPE_JSON, EncodedBody},
                      HttpOpts, Opts)
    ).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

-spec http_options(Timeout :: pos_integer()) -> list().
http_options(Timeout) ->
    [{timeout, Timeout},
     {connect_timeout, Timeout},
     {ssl, ssl_options()}].

-spec ssl_options() -> list().
ssl_options() ->
    [{verify, verify_peer},
     {depth, 100},
     {cacerts, public_key:cacerts_get()},
     {customize_hostname_check,
      [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}].

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

-spec extract_error_message(binary()) -> binary().
extract_error_message(Body) when is_binary(Body), byte_size(Body) > 0 ->
    try jsx:decode(Body, [return_maps]) of
        #{<<"message">> := Msg} -> Msg;
        _ -> Body
    catch
        _:_ -> Body
    end;
extract_error_message(_) ->
    <<"Unknown error">>.
