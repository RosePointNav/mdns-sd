defmodule MdnsSd.Server do
  @moduledoc """
  publishes available services over multicast dns
  responds to queries for PTR, SRV, and TXT records
  #TODO
  -remove_service({instance, service_type})
  """
  use GenServer
  require Logger

  @mdns_group {0xFF, 0x02, 0, 0, 0, 0, 0, 0xFB}
  @mdns_port 5353
  @ttl 120
  @response_packet %DNS.Record{
    header: %DNS.Header{
      aa: true,
      qr: true,
      opcode: 0,
      rcode: 0,
      },
      anlist: []
    }

  #Services is Map of %{{instance, domain}: %Service{}}
  defmodule State do
    defstruct [services: %{}, port: nil, addresses: %{}]
  end

  defmodule Service do
    defstruct [domain: "", txt: %{}, port: nil, ip: nil]
  end

  def start_link(args \\ []) do
    Logger.info "starting link"
    {:ok, pid} = GenServer.start_link(__MODULE__, args, name: Server)
    Logger.info "pid is:"
    Logger.info(inspect pid)
    {:ok, pid}
  end

  def init(_args) do
    udp_options = [
      :binary,
      :inet6,
      active: true,
      # ip:    {0,0,0,0,0,0,0,0},
      # add_membership:  {{65282, 0, 0, 0, 0, 0, 0, 251}, {0,0,0,0,0,0,0,0}},
      multicast_loop:  true,
      multicast_ttl:   255,
      reuseaddr:       true
    ]
    {:ok, pid} = :gen_udp.open(5353, udp_options)
    Logger.info "udp res: #{res}"
    {:ok, %State{}}
  end

  def add_service({instance, type} = domain, service_to_add) do
    GenServer.call(Server, {:add_service, domain, service_to_add})
  end

  def add_addr_record(domain, ip) do
    GenServer.call(Server, {:add_addr_record, domain, ip})
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, handle_packet(packet, state)}
  end

  def handle_call({:add_service, domain, service}, _, state) do
    case Map.has_key?(state.services, domain) do
      true -> {:reply, {:error, :already_added}, state}
      false ->
        new_services = Map.put(state.services, domain, service)
        {:reply, :ok, %{state | services: new_services}}
    end
  end

  def handle_call({:add_addr_record, domain, ip}, _, state) do
    case Map.has_key?(state.addresses, domain) do
      true -> {:reply, {:error, :already_added}, state}
      false ->
        new_addresses = Map.put(state.addresses, domain, ip)
        {:reply, :ok, %{state | addresses: new_addresses}}
    end
  end

  defp handle_packet(packet, state) do
    record = DNS.Record.decode(packet)
    handle_query(record.header.qr, record, state)
  end

  defp handle_query(false, _, state), do: state
  defp handle_query(true, record, state) do
    Enum.flat_map(record.qrlist, fn query ->
      to_resources(query.type, query.domain, state)
    end)
    |> Enum.map(fn resources ->
      send_dns_response(resources, state)
    end)
  end

  defp to_resources(:aaaa, domain, state) do
    case Map.fetch state.addresses, domain do
      {:ok, ip} -> [dns_resource(ip, :aaaa, domain)]
      :error -> []
    end
  end

  defp to_resources(:ptr, domain, state) do
    state.services
    |> Enum.filter_map(fn {{_instance, domain}, _} ->
      domain == domain
    end, fn {instance, domain} ->
      dns_resource("#{instance}.#{domain}", :ptr, domain)
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
        "#{domain} #{@ttl} IN SRV 0 0 #{port} #{service.domain}"
        |> dns_resource(:srv, domain)
        |> List.wrap
    else
      :error ->
        []
    end
  end
  defp to_resources(_, _domain, _state), do: nil

  defp parse_instance_and_dom(full_domain) do
    case Regex.run(~r/^([^\.]*)\.(.*)$/, full_domain, capture: :all_but_first) do
      [instance, domain] -> {instance, domain}
      _ -> nil
    end
  end

  defp dns_resource(data, type, domain) do
    %DNS.Resource{
      class: :in,
      type: type,
      ttl: @ttl,
      data: data,
      domain: "#{domain}"
    }
  end

  defp send_dns_response([], state), do: nil
  defp send_dns_response(answers, state) do
    packet = %DNS.Record{@response_packet | :anlist => answers}
    :gen_udp.send(state.udp_port, @mdns_group, @mdns_port, DNS.Record.encode(packet))
  end

end
