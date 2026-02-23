%%%-------------------------------------------------------------------
%%% @doc Top-level supervisor for the ipdata application.
%%%
%%% This is a minimal supervisor with no children. The ipdata library
%%% is stateless — all state is held in the client map returned by
%%% `ipdata:new/1,2'. The supervisor exists to satisfy OTP application
%%% conventions.
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
-spec init(term()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    {ok, {SupFlags, []}}.
