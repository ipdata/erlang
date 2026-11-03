%%%-------------------------------------------------------------------
%%% @doc Top-level supervisor for the ipdata application.
%%%
%%% This is a minimal supervisor with no children. The client map
%%% returned by `ipdata:new/1,2' is plain immutable data, and the only
%%% process state the library relies on is the `ipdata' httpc profile
%%% holding the persistent connections, which lives in the `inets'
%%% supervision tree and is started and stopped by `ipdata_app'. The
%%% supervisor exists to satisfy OTP application conventions.
%%% @end
%%%-------------------------------------------------------------------
-module(ipdata_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%%--------------------------------------------------------------------
%% @doc Start the supervisor.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc Initialize the supervisor with no children.
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, {supervisor:sup_flags(), []}}.
init([]) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    {ok, {SupFlags, []}}.
