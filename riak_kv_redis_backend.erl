%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at

%%   http://www.apache.org/licenses/LICENSE-2.0


%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.    

%% @doc riak_redis_backend is a Riak storage backend using erldis.


-module(riak_redis_backend).
-author('Eric Cestari <eric@ohmforce.com').
-export([start/1,stop/1,get/2,put/3,list/1,list_bucket/2,delete/2]).


-define(RSEND(V), redis_send(fun()-> V end)).
% @type state() = term().
-record(state, {pid, partition}).

% @spec start(Partition :: integer()) ->
%                        {ok, state()} | {{error, Reason :: term()}, state()}
start(Partition)->
  {ok, Pid} = erldis_sync_client:connect(),
  P=list_to_binary(atom_to_list(node()) ++ integer_to_list(Partition)),
  {ok, #state{pid=Pid, partition = P}}.

% @spec stop(state()) -> ok | {error, Reason :: term()}  
stop(_State)->
  ok.

% get(state(), Key :: binary()) ->
%   {ok, Val :: binary()} | {error, Reason :: term()}
get(#state{partition=P, pid=Pid}, BK)->
  case erldis:get(Pid, k2l(P,BK)) of
    nil -> {error, notfound};
    Val -> 
    case catch binary_to_term(Val) of
      {'EXIT', _}->
        throw({badterm, BK, Val});
      V ->
        {ok, V}
    end
  end.

% put(state(), Key :: binary(), Val :: binary()) ->
%   ok | {error, Reason :: term()}  
put(#state{partition=P,pid=Pid}, {Bucket, Key}=BK, Value)->
  %Fun = fun(_C)->
    erldis:set_pipelining(Pid,true),
    erldis:sadd(Pid, <<"buckets:",P/binary>>,Bucket),
    erldis:set(Pid, k2l(P,BK), term_to_binary(Value)),
    erldis:sadd(Pid, <<P/binary,Bucket/binary>>, Key),
    erldis:sadd(Pid, <<"world:",P/binary>>, term_to_binary(BK)),
    erldis:get_all_results(Pid),
    erldis:set_pipelining(Pid,false),
    ok.
  %end,
  %case  erldis:exec(Pid, Fun) of
  %  [_,_, _, _] ->
  %    ok;
  %  _ ->
  %    {error, unable_to_put}
  %end.


% delete(state(), Key :: binary()) ->
%   ok | {error, Reason :: term()}
delete(#state {partition=P, pid=Pid }, {Bucket, Key}=BK) ->
  %Fun = fun(_C)->
    erldis:set_pipelining(Pid,true),
    erldis:srem(Pid, <<"buckets:",P/binary>>,Bucket),
    erldis:del(Pid, k2l(P,BK)),
    erldis:srem(Pid, <<P/binary,Bucket/binary>>, Key),
    erldis:srem(Pid, <<"world:",P/binary>>, term_to_binary(BK)),
    erldis:get_all_results(Pid),
    erldis:set_pipelining(Pid,false),
  ok.
  %end,
  %case erldis:exec(Pid, Fun) of
  %  [_,_, _, _] ->
  %    ok;
  %  _ ->
  %    {error, unable_to_delete}
  %end.
  
% list(state()) -> [Key :: binary()]
list(#state {partition=P, pid=Pid }) ->
  lists:map(fun binary_to_term/1, 
      erldis:smembers(Pid, <<"world:",P/binary>>)).

list_bucket(#state {partition=P, pid=Pid }, '_')->
  erldis:smembers(Pid, <<"buckets:",P/binary>>);  
    
list_bucket(#state {partition=P, pid=Pid }, {filter, Bucket, Fun})->
  lists:filter(Fun, erldis:smembers(Pid, <<P/binary,Bucket/binary>>));
list_bucket(#state {partition=P,  pid=Pid }, Bucket) ->
  erldis:smembers(Pid, <<P/binary,Bucket/binary>>).

k2l(P,{B, V})->
  <<P/binary,B/binary,V/binary>>.
