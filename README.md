# ipdata

Official Erlang client library for the [ipdata.co](https://ipdata.co) IP geolocation and threat intelligence API.

[![Hex.pm](https://img.shields.io/hexpm/v/ipdata.svg)](https://hex.pm/packages/ipdata)

## Features

- IP geolocation (city, region, country, continent, coordinates)
- ASN and company data
- Carrier detection (mobile network operator)
- Timezone, currency, and language detection
- Threat intelligence (Tor, VPN, proxy, datacenter, blocklists)
- Bulk lookups (up to 100 IPs per request)
- Field filtering to reduce response size
- EU endpoint support for data residency
- Persistent HTTPS connections (HTTP/1.1 keep-alive) through a dedicated `httpc` profile
- Production-ready with proper TLS verification and error handling

## Requirements

- Erlang/OTP 25 or later
- rebar3

## Installation

Add `ipdata` to your `rebar.config` dependencies:

```erlang
{deps, [
    {ipdata, "~> 1.1"}
]}.
```

## Quick Start

```erlang
%% Start the application (it owns the pool of persistent connections)
application:ensure_all_started(ipdata).

%% Create a client with your API key
{ok, Client} = ipdata:new(<<"YOUR_API_KEY">>).

%% Look up an IP address
{ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>).
maps:get(<<"country_name">>, Result).
%% => <<"United States">>
```

## Usage

### Create a Client

```erlang
%% Default options (global endpoint, 5s timeout)
{ok, Client} = ipdata:new(<<"YOUR_API_KEY">>).

%% Use the EU endpoint for data residency
{ok, Client} = ipdata:new(<<"YOUR_API_KEY">>, #{endpoint => eu}).

%% Custom endpoint and timeout
{ok, Client} = ipdata:new(<<"YOUR_API_KEY">>, #{
    endpoint => <<"https://custom-api.example.com">>,
    timeout => 10000
}).
```

### Look Up Your Own IP

```erlang
{ok, Result} = ipdata:lookup(Client).
```

### Look Up a Specific IP

```erlang
{ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>).

%% Access response fields
maps:get(<<"ip">>, Result).           %% => <<"8.8.8.8">>
maps:get(<<"country_name">>, Result). %% => <<"United States">>
maps:get(<<"country_code">>, Result). %% => <<"US">>

%% Fields the API has no data for are null. 8.8.8.8 is an anycast address
%% located at country level only, so it has no city and country-level coordinates.
maps:get(<<"city">>, Result).         %% => null
maps:get(<<"latitude">>, Result).     %% => 39.7599983215332
maps:get(<<"longitude">>, Result).    %% => -98.5

%% Nested data
ASN = maps:get(<<"asn">>, Result).
maps:get(<<"name">>, ASN).            %% => <<"Google LLC">>

Threat = maps:get(<<"threat">>, Result).
maps:get(<<"is_vpn">>, Threat).        %% => false
maps:get(<<"is_datacenter">>, Threat). %% => true

%% Flags the API includes only when they are true: read them with a default
maps:get(<<"is_anycast">>, Result, false).   %% => true
maps:get(<<"is_satellite">>, Result, false). %% => false
```

### Filter Response Fields

Request only the fields you need to reduce response size and improve performance:

```erlang
{ok, Result} = ipdata:lookup(Client, <<"8.8.8.8">>,
                              [<<"ip">>, <<"country_name">>, <<"city">>]).
%% Result contains only the requested fields
```

### Bulk Lookup

Look up multiple IP addresses in a single request (up to 100, requires a paid plan):

```erlang
{ok, Results} = ipdata:bulk(Client, [<<"8.8.8.8">>, <<"1.1.1.1">>]).
%% Results is a list of maps, one per IP

%% With field filtering
{ok, Results} = ipdata:bulk(Client, [<<"8.8.8.8">>, <<"1.1.1.1">>],
                             [<<"ip">>, <<"country_name">>]).
```

### Error Handling

All functions return `{ok, Result}` on success or `{error, Reason}` on failure:

```erlang
case ipdata:lookup(Client, <<"8.8.8.8">>) of
    {ok, Result} ->
        io:format("Country: ~s~n", [maps:get(<<"country_name">>, Result)]);
    {error, {http_error, 401, Message}} ->
        io:format("Authentication failed: ~s~n", [Message]);
    {error, {http_error, 403, Message}} ->
        io:format("Forbidden: ~s~n", [Message]);
    {error, {http_error, 429, Message}} ->
        io:format("Rate limited: ~s~n", [Message]);
    {error, {request_failed, Reason}} ->
        io:format("Network error: ~p~n", [Reason]);
    {error, {json_error, Reason}} ->
        io:format("JSON parse error: ~p~n", [Reason])
end.
```

## Connection reuse

The `ipdata` application owns a dedicated `httpc` profile, also named `ipdata`, that keeps persistent HTTPS connections (HTTP/1.1 keep-alive) to the API for as long as the application runs. Start the application once per node and keep it running: every lookup from every process then goes out on an already established connection. A new connection pays a TCP and TLS handshake; a request on a reused connection does not. Idle connections are closed after 60 seconds. HTTP/2 is not available with `httpc`, so the saving is the TLS handshake, not multiplexing; an HTTP/2 client such as `gun` would need a connection-owner process and a new client lifecycle, which is out of scope for this library. TLS 1.3 session tickets are enabled so that a connection opened after the idle timeout can resume the previous TLS session.

A client map returned by `ipdata:new/1,2` is plain immutable data: it holds no process, socket or other resource, so it can be shared freely between processes, kept in application state or rebuilt at any time, and there is nothing to close. `application:stop(ipdata)` stops the profile and closes its connections. If a request is made before the application has been started, the profile is started on demand (`inets` and `ssl` must be running).

The profile is tuned through the `httpc_options` key of the `ipdata` application environment, for example in `sys.config`:

```erlang
[{ipdata, [
    {httpc_options, [
        {max_sessions, 16},          %% persistent connections per host (default 16)
        {max_keep_alive_length, 4},  %% outstanding requests per connection (default 4)
        {keep_alive_timeout, 60000}  %% close a connection idle for this long, in ms (default 60000)
    ]}
]}].
```

Each entry overrides the default of the same name, and any other `httpc:set_options/2` option (for example `https_proxy`) can be added. The options are applied when the application starts.

A bulk lookup is a POST, so it is retried exactly once if the server closed the connection before answering (`socket_closed_remotely`); `httpc` has already discarded that connection, so the retry goes out on a fresh one. HTTP error statuses are never retried.

## API Reference

### `ipdata:new/1,2`

```erlang
-spec new(ApiKey :: binary()) -> {ok, client()} | {error, term()}.
-spec new(ApiKey :: binary(), Opts :: opts()) -> {ok, client()} | {error, term()}.
```

Create a new client. Options:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `endpoint` | `global \| eu \| binary()` | `global` | API endpoint to use |
| `timeout` | `pos_integer()` | `5000` | Request timeout in milliseconds |

### `ipdata:lookup/1,2,3`

```erlang
-spec lookup(Client) -> {ok, map()} | {error, term()}.
-spec lookup(Client, IP :: binary()) -> {ok, map()} | {error, term()}.
-spec lookup(Client, IP :: binary(), Fields :: [binary()]) -> {ok, map()} | {error, term()}.
```

Look up geolocation and metadata for an IP address.

### `ipdata:bulk/2,3`

```erlang
-spec bulk(Client, IPs :: [binary()]) -> {ok, [map()]} | {error, term()}.
-spec bulk(Client, IPs :: [binary()], Fields :: [binary()]) -> {ok, [map()]} | {error, term()}.
```

Look up multiple IP addresses in a single request. Maximum 100 IPs. Requires a paid API key.

## Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `ip` | binary | IP address |
| `is_eu` | boolean | Whether the country is in the EU |
| `is_satellite` | boolean | Satellite internet provider; present only when `true` |
| `is_anycast` | boolean | Anycast address; present only when `true` |
| `city` | binary | City name |
| `region` | binary | Region/state name |
| `region_code` | binary | Region code |
| `region_type` | binary | Region type |
| `country_name` | binary | Country name |
| `country_code` | binary | ISO country code |
| `continent_name` | binary | Continent name |
| `continent_code` | binary | Continent code |
| `latitude` | float | Latitude |
| `longitude` | float | Longitude |
| `postal` | binary | Postal/ZIP code |
| `calling_code` | binary | International calling code |
| `flag` | binary | Country flag image URL |
| `emoji_flag` | binary | Country flag emoji |
| `emoji_unicode` | binary | Country flag unicode |
| `asn` | map | ASN data (`asn`, `name`, `domain`, `route`, `type`) |
| `organisation` | binary | Organization name |
| `company` | map | Company data (`name`, `domain`, `network`, `type`) |
| `carrier` | map | Mobile carrier (`name`, `mcc`, `mnc`) |
| `languages` | list | Languages (`name`, `native`, `code`) |
| `currency` | map | Currency (`name`, `code`, `symbol`, `native`, `plural`) |
| `time_zone` | map | Timezone (`name`, `abbr`, `offset`, `is_dst`, `current_time`) |
| `threat` | map | Threat data (see below) |
| `count` | binary | API request count |

The API includes `is_satellite` and `is_anycast` only when they are `true` and omits them otherwise. The library returns the decoded JSON unchanged, so read them with a default: `maps:get(<<"is_satellite">>, Result, false)`. Both names can be requested through the fields parameter like any other field.

### Threat Fields

| Field | Type | Description |
|-------|------|-------------|
| `is_tor` | boolean | Tor exit node |
| `is_vpn` | boolean | VPN |
| `is_icloud_relay` | boolean | iCloud Private Relay |
| `is_proxy` | boolean | Proxy |
| `is_datacenter` | boolean | Datacenter IP |
| `is_anonymous` | boolean | Anonymous access |
| `is_known_attacker` | boolean | Known attacker |
| `is_known_abuser` | boolean | Known abuser |
| `is_threat` | boolean | Any threat detected |
| `is_bogon` | boolean | Bogon IP |
| `blocklists` | list | Blocklist entries (see below) |
| `scores` | map | Reputation scores (`vpn_score`, `proxy_score`, `threat_score`, `trust_score`) |

### Blocklist Entry Fields

Each element of `blocklists` is a map:

| Field | Type | Description |
|-------|------|-------------|
| `name` | binary | Blocklist name |
| `site` | binary | Blocklist website |
| `type` | binary | Blocklist type (for example `vpn`, `cloud`, `general`) |
| `first_seen` | binary | First day the IP was listed, `YYYY-MM-DD` (UTC); optional |
| `last_seen` | binary | Last day the IP was listed, `YYYY-MM-DD` (UTC); optional |
| `days_seen` | integer | Number of days the IP was listed; optional |

Some feeds, for example ipdata's own `vpn` feed, carry none of `first_seen`, `last_seen` and `days_seen`, so read them with a default such as `maps:get(<<"days_seen">>, Entry, undefined)`. The dates are returned as binaries and are not parsed.

## Testing

```bash
rebar3 ct
```

## License

MIT - see [LICENSE](LICENSE) for details.
