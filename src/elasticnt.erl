%%
%%   Copyright 2016 Dmitry Kolesnikov, All Rights Reserved
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%% @doc
%%   N-triple intake to elastic search
-module(elasticnt).

%% elastic search i/o
-export([
   schema/3,
   in/2
]).
%% data processing
-export([
   nt/2,
   freebase/1,
   dbpedia/1
]).

%% 
%%
-define(URN, {urn, <<"es">>, <<>>}).


%%
%% defines schema for attributes
%%  Options
%%    n - number of replica (default 1)
%%    q - number of shards (default 8)
schema(Sock, Schema, Opts) ->
   esio:put(Sock, uri:segments([Schema], ?URN),
      #{
         settings => #{
            number_of_shards   => opts:val(q, 8, Opts), 
            number_of_replicas => opts:val(n, 1, Opts)
         },
         mappings => #{
            '_default_' => #{properties => properties(string)},
            string      => #{properties => properties(string)},
            long        => #{properties => properties(long)},
            double      => #{properties => properties(double)},
            datetime    => #{properties => properties(string)}
         }
      }
   ).

properties(Type) ->
   #{
      s => #{type => string, index => not_analyzed},
      p => #{type => string, index => not_analyzed},
      o => #{type => Type},
      k => #{type => string, index => not_analyzed}
   }.

%%
%% intake stream of atomic statements 
in(Sock, Stream) ->
   stream:foreach(
      fun(#{s:= S, p := P, o := O} = Fact) ->
         Uid  = base64:encode( uid:encode(uid:g()) ),
         JsO  = jsonify(O),
         Key  = key(S, P, JsO),
         Type = typeof(Fact),
         Urn  = uri:segments([Type, Key], ?URN),
         esio:put(Sock, Urn, #{s => S, p => P, o => JsO, k => Uid}, infinity)
      end,
      Stream
   ).

%% unique fact identity (content address)
key(S, P, O) ->
   bits:btoh(
      crypto:hash(md5, [scalar:s(S), scalar:s(P), scalar:s(O)])
   ).

%% fact type
typeof(#{lang := Lang}) ->
   Lang;
typeof(#{o := O})
 when is_binary(O) ->
   string;
typeof(#{o := O})
 when is_integer(O) ->
   long;
typeof(#{o := O})
 when is_float(O) ->
   double;
typeof(#{o := {_, _, _}}) ->
   datetime.

%% jsonify fact value
jsonify({_, _, _} = X) ->
   scalar:s(tempus:encode(X));
jsonify(X) ->
   X.


%%
%% produces stream of triples, read from n-triple file
-spec nt(atom() | list(), datum:stream()) -> datum:stream().

nt(Prefixes, Stream) ->
   stream:map(
      fun(X) -> fact(Prefixes, X) end,
      nt:stream(Stream)
   ).

fact(Prefixes, {{url, S}, {url, P}, {url, O}}) ->
   #{
      s => uri:urn(S, Prefixes), 
      p => uri:urn(P, Prefixes), 
      o => uri:urn(O, Prefixes)
   };
fact(Prefixes, {{url, S}, {url, P}, {url, O}, Lang})
 when is_binary(Lang) ->
   #{
      s => uri:urn(S, Prefixes), 
      p => uri:urn(P, Prefixes), 
      o => uri:urn(O, Prefixes), 
      lang => Lang
   };
fact(Prefixes, {{url, S}, {url, P}, O}) ->
   #{
      s => uri:urn(S, Prefixes), 
      p => uri:urn(P, Prefixes), 
      o => O
   };
fact(Prefixes, {{url, S}, {url, P}, O, Lang})
 when is_binary(Lang) ->
   #{
      s => uri:urn(S, Prefixes), 
      p => uri:urn(P, Prefixes), 
      o => O,
      lang => Lang
   }.

%%
%% takes stream of N-triples and converts them to 
%% knowledge statements, using freebase ontology to
%% build identifiers.
-spec freebase(string() | datum:stream()) -> datum:stream().

freebase({s, _, _} = Stream) ->
   elasticnt_freebase:nt(Stream);
freebase(File) ->
   freebase(gz:stream(stdio:file(File))).


%%
%% takes stream of N-triples and converts them to 
%% knowledge statements, using dbpedia ontology to
%% build identifiers.
-spec dbpedia(string() | datum:stream()) -> datum:stream().

dbpedia({s, _, _} = Stream) ->
   elasticnt_dbpedia:nt(Stream);
dbpedia(File) ->
   dbpedia(stdio:file(File)).

