# MdnsSd

## Description

Simple Elixir MDNS-SD implementation. `Client` listens for new services, and notifies
any subscribed processes of their presence. Address records and services can be
added to `Server`, which will then respond to requests for the corresponding
A, PTR, SRV, and TXT records.

Currently a barebones implementation which does not implement known answer
suppression or keep track of TTLs.

## Usage
### Server
currently ipv4 only, eventually will be ipv6 configurable
```
Mdns.Server.add_service({service_instance, service_domain}, service)
```
where `{service_instance, service_domain}` is something like
`{"ff339870", "_onenet-pgn._tcp.local"}` and `service` is an `%MdnsSd.Service{}`
struct whose domain has been registered via `add_addr_record`.

### Client
```
Mdns.Client.listen(service_type)
```
where `service_type` is something like "_onenet-pgn._tcp". This is a GenServer
call which returns all known services in a Map:
```
%{
  service_type_1: %{
    instances: %{
      service_instance_1: %ServiceDetails{}
      service_instance_2: %ServiceDetails{}
    },
    listeners: [<pid#187.7>]
  }
  [...]
}
```
subsequent services will be sent one by one to the calling process:
```
{:mdns_sd, service_type, {service_ip, service_details}}
```
