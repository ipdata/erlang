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
- Production-ready with proper TLS verification and error handling

## Requirements

- Erlang/OTP 25 or later
- rebar3

## Installation

Add `ipdata` to your `rebar.config` dependencies:

```erlang
{deps, [
    {ipdata, "~> 1.0"}
]}.
```

## Quick Start

```erlang
%% Start the application
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
maps:get(<<"city">>, Result).         %% => <<"Ashburn">>
maps:get(<<"latitude">>, Result).     %% => 39.03
maps:get(<<"longitude">>, Result).    %% => -77.5

%% Nested data
ASN = maps:get(<<"asn">>, Result).
maps:get(<<"name">>, ASN).            %% => <<"Google LLC">>

Threat = maps:get(<<"threat">>, Result).
maps:get(<<"is_vpn">>, Threat).       %% => false

TimeZone = maps:get(<<"time_zone">>, Result).
maps:get(<<"name">>, TimeZone).       %% => <<"America/New_York">>
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
| `blocklists` | list | Blocklist entries (`name`, `site`, `type`) |
| `scores` | map | Reputation scores (`vpn_score`, `proxy_score`, `threat_score`, `trust_score`) |

## Testing

```bash
rebar3 ct
```

## License

MIT - see [LICENSE](LICENSE) for details.
