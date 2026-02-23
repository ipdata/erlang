%%%-------------------------------------------------------------------
%%% @doc Application behaviour callback for the ipdata library.
%%%
%%% Ensures that required OTP applications (`inets', `ssl') are
%%% started and launches the top-level supervisor.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_app).

-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @doc Start the ipdata application.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) ->
    {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    ipdata_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the ipdata application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
