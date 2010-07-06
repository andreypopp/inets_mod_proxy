%%% @copyright 2010, Andrey Popp <apopp@moneyps.ru>
%%% @doc Inets httpd module that proxies request to another server.
%%% This module acts by proxying all incoming requests to server, defined in
%%% httpd configuration as <code>mod_proxy_target</code>, for example
%%% <code>{https, "google.com", 443}</code>. Note, that trailing slash is not
%%% allowed here.

-module(entrysmr_mod_proxy).
-export([do/1]).

-include_lib("inets/src/httpd.hrl").


%% @doc Inets httpd module callback.
do(Info) ->
    ProxyTo = which_proxy_target(Info),
    error_logger:info_msg("proxying request ~p to ~p",
        [Info#mod.method ++ " " ++ Info#mod.request_uri, ProxyTo]),
    case proxy_request(ProxyTo, Info) of
        {ok, {{_, StatusCode, _}, RespHeaders, Body}} ->
            Headers = [{code, StatusCode}] ++ RespHeaders,
            {break, [{response, {response,  Headers, Body}}]};
        {error, Reason} ->
            error_logger:error_msg("proxy error ~p", [Reason]),
            {break, [{response, {502, []}}]}
    end.
    

%% @doc Proxy request to sepcified host and return response.
%% @spec proxy_request(Target, Info) -> {ok, status_line(), headers(), body()}
%%                                    | {error, Reason}
%%  ProxyTarget = {Proto, Host, Port}
%%  Proto = http | https
%%  Host = string()
%%  Port = integer()
%%  Reason = term()
proxy_request({Proto, Host, Port}, Info) ->
    ProxyUrl = compose_url(Proto, Host, Port, Info#mod.request_uri),
    Method = which_method(Info),
    HTTPOptions = [{autoredirect, false}],
    Headers = derive_headers(Info#mod.parsed_header, Host),
    if
        (Method =:= post) or (Method =:= put) ->
            case which_content_type(Info) of
                none -> {error, no_content_type};
                ContentType -> 
                    Rq = {ProxyUrl, Headers, ContentType, Info#mod.entity_body},
                    http:request(Method, Rq, HTTPOptions, [])
            end;
        true ->
            http:request(Method, {ProxyUrl, Headers}, HTTPOptions, [])
    end.


%% @doc Derive headers for proxy request.
%% @spec derive_headers(IncomingHeaders, Host) -> ProxyHeaders
%%  IncomingHeaders = headers()
%%  Host = string()
%%  ProxyHeaders = headers()
derive_headers(IncomingHeaders, Host) ->
    [{"host", Host} | proplists:delete("host", IncomingHeaders)].


%% @doc Extract HTTP method value as atom from module info.
%% @spec which_method(Info) -> HTTPMethod
%%  Info = #mod()
%%  HTTPMethod = get | post | head | put | delete | trace | options
which_method(#mod{method="GET"}) -> get; 
which_method(#mod{method="POST"}) -> post; 
which_method(#mod{method="HEAD"}) -> head; 
which_method(#mod{method="PUT"}) -> put; 
which_method(#mod{method="DELETE"}) -> delete; 
which_method(#mod{method="TRACE"}) -> trace; 
which_method(#mod{method="OPTIONS"}) -> options.


%% @doc Read proxy target from httpd service configuration.
%% @spec which_proxy_target(Info) -> {Proto, Host, Port}
%%  Info = #mod()
%%  Proto = http | https
%%  Host = string()
%%  Port = integer()
which_proxy_target(Info) ->
    case httpd_util:lookup(Info#mod.config_db, mod_proxy_target) of
        {Proto, Host} -> case Proto of
                http -> {http, Host, 80};
                https -> {https, Host, 443}
            end;
        {Proto, Host, Port} -> {Proto, Host, Port}
    end.


%% @doc Extract Content-Type header from module info.
%% spec which_content_type(Info) -> ContentType | none
%%  Info = #mod()
%%  ContentType = string()
which_content_type(Info) ->
    case proplists:lookup("content-type", Info#mod.parsed_header) of
        {"content-type", Value} -> Value;
        none -> none
    end.


%% @doc Compose URL from protocol, host, port and URI parts.
%% @spec compose_url(Proto, Host, Port, Uri) -> Url
%%  Proto = http | https
%%  Host = string()
%%  Port = integer()
%%  Uri = string()
compose_url(Proto, Host, Port, Uri) ->
    atom_to_list(Proto) ++ "://" ++ Host ++ ":" ++ integer_to_list(Port) ++ Uri.
