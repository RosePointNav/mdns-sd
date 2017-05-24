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
    defstruct [services: %{}, port: nil, ip: nil, protocol: nil]
  end

  defmodule Service do
    defstruct [domain: '', txt: %{}, port: nil, ip: nil]
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Server)
  end

  def init(args) do
    {:ok, pid} = case args[:protocol] do
      :inet -> open_inet_port()
      :inet6 -> open_inet6_port(Application.get_env :mdns_sd, :interface)
    end
    state = %State{port: pid, ip: args[:service_ip], protocol: args[:protocol]}
    broadcast_addr(state)
    {:ok, state}
  end

  def add_service({_instance, _type} = domain, service_to_add) do
    GenServer.call(Server, {:add_service, domain, service_to_add})
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, handle_packet(packet, state)}
  end

  def broadcast_addr(%{protocol: :inet} = state) do
    send_dns_response [dns_resource(state.ip, :a, @domain)], state
  end
  def broadcast_addr(%{protocol: :inet6} = state) do
    send_dns_response [dns_resource(state.ip, :aaaa, @domain)], state
  end

  def handle_call({:add_service, {instance, service} = name, data}, _, state) do
    case Map.has_key?(state.services, name) do
      true -> {:reply, {:error, :already_added}, state}
      false ->
        new_services = Map.put(state.services, name, data)
        service_domain = '#{instance}.#{service}.local'
        [ dns_resource(service_domain, :ptr, '#{@domain}.local'),
          srv_resource(data.port, service_domain),
          txt_resource(data.txt, service_domain)
        ]
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

  defp to_resources(:a, domain, %{protocol: :inet} = state) do
    if @domain == trunc_local(domain) do
      [dns_resource(state.ip, :a, '#{@domain}.local')]
    else
      []
    end
  end

  defp to_resources(:aaaa, domain, %{protocol: :inet6} = state) do
    if @domain == trunc_local(domain) do
      [dns_resource(state.ip, :aaaa, '#{@domain}.local')]
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
        [txt_resource(txt, domain)]
    else
      _error -> []
    end
  end

  defp to_resources(:srv, q_domain, state) do
    with {instance, service_name} <- parse_instance_and_service(q_domain),
      {:ok, service} <- Map.fetch(state.services, {instance, service_name}),
      {:ok, port} <- Map.fetch(service, :port) do
        [srv_resource(port, q_domain)]
    else
      _error -> []
    end
  end
  defp to_resources(_, _domain, _state), do: []

  #domain is suffixed with .local
  defp srv_resource(port, domain) do
    <<0::32>> <> <<port::16>> <> to_labels('#{@domain}.local')
    |> dns_resource(:srv, domain)
  end

  defp txt_resource(txt_map, domain) do
    Enum.map(txt_map, fn {key, val} ->
      {key, val} = {to_string(key), to_string(val)}
      <<byte_size(key)>> <> key <> <<byte_size(val)>> <> val
    end)
    |> dns_resource(:txt, domain)
  end

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
    :gen_udp.send(state.port, mdns_group(state.protocol), @mdns_port, DNS.Record.encode(packet))
  end

end
