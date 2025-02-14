%
% The contents of this file are subject to the Mozilla Public License
% Version 1.1 (the "License"); you may not use this file except in
% compliance with the License. You may obtain a copy of the License at
% http://www.mozilla.org/MPL/
%
% Copyright (c) 2015 Petr Gotthard <petr.gotthard@centrum.cz>
%

% registry of server content handlers
% provides the .well-known/code resource and (in future) content queries
-module(coap_server_content).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).
-export([add_handler/2, get_handler/1]).

-include("coap.hrl").

-record(state, {reg}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_handler(Process, Links) ->
    gen_server:call(?MODULE, {add_handler, Process, Links}).

get_handler(Message) ->
    UriPath = proplists:get_value(uri_path, Message#coap_message.options, []),
    gen_server:call(?MODULE, {get_handler, UriPath}).

init(_Args) ->
    {ok, #state{reg=
        % RFC 6690, Section 4
        [{?MODULE, {absolute, [".well-known", "core"], []}}]
    }}.

handle_call({add_handler, Process, Links}, _From, State=#state{reg=Reg}) ->
    Reg2 = Reg++[{Process, Link} || Link <- Links],
    {reply, ok, State#state{reg=Reg2}};
handle_call({get_handler, Uri}, _From, State=#state{reg=Reg}) ->
    {reply, lookup_uri(Reg, Uri), State}.

handle_cast(Request, State) ->
    io:fwrite("coap_server_content unknown cast ~p~n", [Request]),
    {noreply, State}.

handle_info({coap_request, _ChId, Channel, _Match, Request=#coap_message{method='get'}}, State=#state{reg=Reg}) ->
    coap_request:reply_content(Channel, Request,
        <<"application/link-format">>,
        list_to_binary(core_link:encode(lists:usort(get_links(Reg))))),
    {noreply, State};
handle_info({coap_request, _ChId, Channel, _Match, Request}, State) ->
    coap_request:reply(Channel, Request, {error, method_not_allowed}),
    {noreply, State};
handle_info(_Unknown, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

% ask each handler to provide a link list
get_links(Reg) ->
    lists:foldl(
        fun({Module, Uri}, Acc) -> Acc++get_links(Module, Uri) end,
        [], Reg).

% the .well-known/core itself is not listed under .well-known/core
get_links(?MODULE, _Uri) ->
    [];
get_links(Handler, Uri) ->
    case is_pattern(Uri) of
        % for each pattern ask the handler to provide a list of resources
        true -> gen_server:call(Handler, {get_links, Uri});
        false -> [Uri]
    end.

is_pattern({absolute, Uri, _}) -> is_pattern0(Uri).

is_pattern0([Atom|_List]) when is_atom(Atom) -> true;
is_pattern0([_E|List]) -> is_pattern0(List);
is_pattern0([]) -> false.

lookup_uri(Reg, Uri) ->
    lists:foldl(
        fun ({Handler, Pattern}, none) ->
                case match_uri(Pattern, Uri) of
                    {ok, Match} -> {Handler, Match};
                    none -> none
                end;
            (_Any, Result) ->
                Result
        end, none, Reg).

match_uri({absolute, Pattern, _}, Uri) ->
    match_uri0(Pattern, Uri, []).

match_uri0([String|Pattern], [String|Uri], Acc) ->
    match_uri0(Pattern, Uri, Acc);
match_uri0([Atom|Pattern], [String|Uri], Acc) when is_atom(Atom) ->
    match_uri0(Pattern, Uri, [{Atom, String}|Acc]);
match_uri0([], [], Acc) ->
    {ok, Acc};
match_uri0(_Any1, _Any2, _Acc) ->
    none.


-include_lib("eunit/include/eunit.hrl").

content_test_() -> [
        ?_assertEqual(false, is_pattern({absolute, [], []})),
        ?_assertEqual(false, is_pattern({absolute, ["one"], []})),
        ?_assertEqual(true,  is_pattern({absolute, ["one", second], []})),
        ?_assertEqual({ok, []}, match_uri({absolute, [], []},              [])),
        ?_assertEqual({ok, []}, match_uri({absolute, ["one", "two"], []},  ["one", "two"])),
        ?_assertEqual(none,     match_uri({absolute, ["one", "two"], []},  ["one"])),
        ?_assertEqual(none,     match_uri({absolute, ["one"], []},         ["one", "two"])),
        ?_assertEqual(none,     match_uri({absolute, ["one", "two"], []},  ["one", "three"])),
        ?_assertEqual({ok, [{second, "two"}]},   match_uri({absolute, ["one", second], []}, ["one", "two"])),
        ?_assertEqual({ok, [{second, "three"}]}, match_uri({absolute, ["one", second], []}, ["one", "three"]))
    ].

% end of file
