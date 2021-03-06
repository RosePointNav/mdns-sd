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
```
Mdns.Server.add_service({service_instance, service}, service)
```
where `{service_instance, service}` is something like
`{'ff339870', '_onenet-pgn._tcp'}` and `service` is a hash such as:
 ```
 %{
   port: 3000
   txt: %{
     'nmea-name' => 'foo'
   }
 }
 ```

### Client
```
Mdns.Client.listen(service_type)
```
where `service_type` is something like `'_onenet-info._tcp'`. This subscribes the
calling process to an [Informant](https://github.com/ghitchens/informant) topic for that service type.
When any instance of that service type is announced/updated, the calling process
receives a message:
```
{:informant, MdnsSd, {'_onenet-info._tcp', 'foobar'}, {:changes, %MdnsSd.Service{
  domain: 'johnnymac.local', ip: {192, 168, 15, 157}, port: 5000, txt:
  %{'url' => 'foorl'}}, nil}, []}
```
