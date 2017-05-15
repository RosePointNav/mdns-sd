defmodule MdnsSd.Server do
  @moduledoc """
  publishes available services over multicast dns
  responds to queries for PTR, SRV, and TXT records
  #TODO
  -remove_service({instance, service_type})
  """
  use GenServer
  require Logger
  import MdnsSd.Helpers

  @mdns_group {224,0,0,251}#{0xFF02, 0, 0, 0, 0, 0, 0, 0xFB}
  @mdns_port 5353
  @ttl 120
  @response_header %DNS.Header{
    aa: true,
    qr: true,
    opcode: 0,
    rcode: 0,
  }

  #Services is Map of %{{instance, domain}: %Service{}}
  defmodule State do
    defstruct [services: %{}, port: nil, addresses: %{}]
  end

  defmodule Service do
    defstruct [domain: '', txt: %{}, port: nil, ip: nil]
  end

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: Server)
  end

  def init(_args) do
    # multicast_addr = String.reverse <<0xFF, 0x02, 0::104, 0xFB>> #little endian
    # ifindex = <<4::32-little>>
    # ipproto_ipv6 = 41
    # ipv6_join_group = 20

    udp_options = [
      :binary,
      # :inet6,
      active: true,
      # add_membership:  {{65282, 0, 0, 0, 0, 0, 0, 251}, {0,0,0,0,0,0,0,0}},
      add_membership: {{224,0,0,251}, {0,0,0,0}},
      multicast_loop:  true,
      multicast_ttl:   255,
      reuseaddr:       true
    ]
    {:ok, pid} = :gen_udp.open(5353, udp_options)
    # :ok = :inet.setopts(pid, [{:raw, ipproto_ipv6, ipv6_join_group, multicast_addr <> ifindex}])
    {:ok, %State{port: pid}}
  end

  def add_service({instance, type} = domain, service_to_add) do
    GenServer.call(Server, {:add_service, domain, service_to_add})
  end

  def add_addr_record(domain, ip) when is_list(ip) do
    GenServer.call(Server, {:add_addr_record, domain, ip})
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, handle_packet(packet, state)}
  end

  def handle_call({:add_service, {instance, dom} = domain, service}, _, state) do
    case Map.has_key?(state.services, domain) do
      true -> {:reply, {:error, :already_added}, state}
      false ->
        new_services = Map.put(state.services, domain, service)
        [dns_resource('#{instance}.#{dom}', :ptr, service.domain)]
        |> send_dns_response(state)
        {:reply, :ok, %{state | services: new_services}}
    end
  end

  def handle_call({:add_addr_record, domain, ip}, _, state) do
    case Map.has_key?(state.addresses, domain) do
      true -> {:reply, {:error, :already_added}, state}
      false ->
        new_addresses = Map.put(state.addresses, domain, ip)
        send_dns_response [dns_resource(ip, :a, domain)], state
        {:reply, :ok, %{state | addresses: new_addresses}}
    end
  end

  defp handle_packet(packet, state) do
    record = DNS.Record.decode(packet)
    handle_query(record.header.qr, record, state)
    state
  end

  defp handle_query(false, _, state), do: state
  defp handle_query(true, record, state) do
    Enum.flat_map(record.qdlist, fn query ->
      to_resources(query.type, query.domain, state)
    end)
    |> Enum.map(fn resources ->
      send_dns_response(resources, state)
    end)
  end

  defp to_resources(:a, domain, state) do
    case Map.fetch state.addresses, domain do
      {:ok, ip} -> [dns_resource(ip, :a, domain)]
      :error -> []
    end
  end

  defp to_resources(:ptr, domain, state) do
    state.services
    |> Enum.filter_map(fn {{_instance, domain}, _} ->
      domain == domain
    end, fn {instance, domain} ->
      dns_resource('#{instance}.#{domain}', :ptr, domain)
    end)
  end

  defp to_resources(:txt, domain, state) do
    with {instance, domain} <- parse_instance_and_dom(domain),
      service <- Map.fetch(state.services, {instance, domain}),
      txt <- Map.fetch(service, :txt) do
        Enum.map(txt, fn {key, val} ->
          "#{key}=#{val}"
        end)
        |> Enum.join("\n")
        |> String.to_charlist
        |> dns_resource(:txt, domain)
        |> List.wrap
    else
      :error ->
        []
    end
  end

  defp to_resources(:srv, domain, state) do
    with {instance, domain} <- parse_instance_and_dom(domain),
      service <- Map.fetch(state.services, {instance, domain}),
      port <- Map.fetch(service, :port) do
        '#{domain} #{@ttl} IN SRV 0 0 #{port} #{service.domain}'
        |> dns_resource(:srv, domain)
        |> List.wrap
    else
      :error ->
        []
    end
  end
  defp to_resources(_, _domain, _state), do: nil

  defp dns_resource(data, type, domain) do
    %DNS.Resource{
      class: :in,
      type: type,
      ttl: @ttl,
      data: data,
      domain: '#{domain}'
    }
  end

  defp send_dns_response([], state), do: nil
  defp send_dns_response(answers, state) do
    Logger.info inspect(answers)
    packet = %DNS.Record{header: @response_header, anlist: answers}
    :gen_udp.send(state.port, @mdns_group, @mdns_port, DNS.Record.encode(packet))
  end

end
