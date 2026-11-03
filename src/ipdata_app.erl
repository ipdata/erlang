%%%-------------------------------------------------------------------
%%% @doc Application behaviour callback for the ipdata library.
%%%
%%% The application depends on `inets', `ssl' and `public_key', which
%%% `application:ensure_all_started(ipdata)' starts first. On start it
%%% brings up the `ipdata' httpc profile that holds the persistent
%%% connections used by every request (see
%%% `ipdata_http:start_profile/0'), then launches the top-level
%%% supervisor. On stop the profile and its connections are closed.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_app).

-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @doc Start the ipdata application.
%%
%% Starts the `ipdata' httpc profile (accepting one that is already
%% running) and applies `ipdata_http:profile_options/0' before the
%% supervisor is started.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) ->
    {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    case ipdata_http:start_profile() of
        ok ->
            ipdata_sup:start_link();
        {error, Reason} ->
            {error, {httpc_profile, Reason}}
    end.

%%--------------------------------------------------------------------
%% @doc Stop the ipdata application.
%%
%% Stops the `ipdata' httpc profile, closing its connections.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    _ = inets:stop(httpc, ipdata),
    ok.
