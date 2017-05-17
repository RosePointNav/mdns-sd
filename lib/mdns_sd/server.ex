defmodule MdnsSd.Server do
  @moduledoc """
  publishes available services over multicast dns
  responds to queries for PTR, SRV, and TXT records
  #TODO
  -remove_service({instance, service_type})
  -REVIEW: can I just supply a tuple as the SRV data? (see client.ex)
  """
  use GenServer
  require Logger
  import MdnsSd.Helpers

  @domain 'elixir-mdns-sd'
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
    defstruct [services: %{}, port: nil, ip: nil]
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
    state = %State{port: pid, ip: <<192,168,15,171>>}
    broadcast_addr(state)
    {:ok, state}
  end

  def add_service({_instance, _type} = domain, service_to_add) do
    GenServer.call(Server, {:add_service, domain, service_to_add})
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, handle_packet(packet, state)}
  end

  def broadcast_addr(state) do
    send_dns_response [dns_resource(state.ip, :a, @domain)], state
  end

  def handle_call({:add_service, {instance, service} = name, data}, _, state) do
    case Map.has_key?(state.services, name) do
      true -> {:reply, {:error, :already_added}, state}
      false ->
        new_services = Map.put(state.services, name, data)
        [dns_resource('#{instance}.#{service}.local', :ptr, '#{@domain}.local')]
        |> send_dns_response(state)
        {:reply, :ok, %{state | services: new_services}}
    end
  end

  defp handle_packet(packet, state) do
    record = DNS.Record.decode(packet)
    handle_query(record.header.qr, record, state)
    state
  end

  defp handle_query(true = _is_response, _, state), do: state
  defp handle_query(_, record, state) do
    Enum.map(record.qdlist, fn query ->
      to_resources(query.type, query.domain, state)
      |> send_dns_response(state)
    end)
  end

  defp to_resources(:a, domain, state) do
    if @domain == trunc_local(domain) do
      [dns_resource(state.ip, :a, '#{@domain}.local')]
    else
      []
    end
  end

  defp to_resources(:ptr, domain, state) do
    state.services
    |> Enum.filter_map(fn {{_instance, service}, _} ->
      service == trunc_local(domain)
    end, fn {{instance, service}, _} ->
      dns_resource('#{instance}.#{service}.local', :ptr, domain)
    end)
  end

  defp to_resources(:txt, domain, state) do
    with {instance, service_name} <- parse_instance_and_service(domain),
      {:ok, service} <- Map.fetch(state.services, {instance, service_name}),
      {:ok, txt} <- Map.fetch(service, :txt) do
        Enum.map(txt, fn {key, val} ->
          {key, val} = {to_string(key), to_string(val)}
          <<byte_size(key)>> <> key <> <<byte_size(val)>> <> val
        end)
        |> dns_resource(:txt, domain)
        |> List.wrap
    else
      _error -> []
    end
  end

  defp to_resources(:srv, q_domain, state) do
    with {instance, service_name} <- parse_instance_and_service(q_domain),
      {:ok, service} <- Map.fetch(state.services, {instance, service_name}),
      {:ok, port} <- Map.fetch(service, :port) do
        <<0::32>> <> <<port::16>> <> to_labels('#{@domain}.local')
        |> dns_resource(:srv, q_domain)
        |> List.wrap()
    else
      _error -> []
    end
  end
  defp to_resources(_, _domain, _state), do: []

  defp dns_resource(data, type, domain) do
    %DNS.Resource{
      class: :in,
      type: type,
      ttl: @ttl,
      data: data,
      domain: domain
    }
  end

  defp send_dns_response([], _state), do: nil
  defp send_dns_response(answers, state) do
    packet = %DNS.Record{header: @response_header, anlist: answers}
    :gen_udp.send(state.port, @mdns_group, @mdns_port, DNS.Record.encode(packet))
  end

end
