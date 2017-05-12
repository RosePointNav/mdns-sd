# MdnsSd

##Description

Simple IPv6 MDNS-SD implementation. `Client` listens for new services, and notifies
any subscribed processes of their presence. Address records and services can be
added to `Server`, which will then respond to requests for the corresponding
A, PTR, SRV, and TXT records.

Currently a barebones implementation which does not implement known answer
suppression or keep track of TTLs.
