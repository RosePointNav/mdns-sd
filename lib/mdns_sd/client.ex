defmodule Client do
  @moduledoc """
  queries services available over MDNS
  TODO
  -make sure query header contains the appropriate values
  -Process.monitor listener
  """
  use GenServer
  import MdnsSd.Helpers

  @mdns_group {224,0,0,251}
  @mdns_port 5353
  @ttl 120
  @query_header %DNS.Header{
    aa: true,
    qr: true,
    opcode: 0,
    rcode: 0,
  }

  #services is a Map where key is service_type, value is %Service{}
  #domains is a map where key is domain name, value is ip address
  defmodule State do
    defstruct [port: 0, services: %{}, domains: %{}]
  end
  defmodule Service do
    defstruct [listeners: [], instances: %{}]
  end

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: Client)
  end

  def init(_args) do
    udp_options = [
      :binary,
      active: true,
      add_membership: {{224,0,0,251}, {0,0,0,0}},
      multicast_loop:  true,
      multicast_ttl:   255,
      reuseaddr:       true
    ]
    {:ok, udp_pid} = :gen_udp.open(5353, udp_options)
    {:ok, %State{port: udp_pid}}
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, state}
  end

  def listen(service_type) when is_list(service_type) do
    GenServer.call(Client, {:listen, service_type})
  end

  def handle_call({:listen, service_type}, {from,_}, state) do
    case Map.fetch state.services service_type do
      {:ok, service} ->
        case Enum.member? service.listeners do
          true ->
            {:reply, {:error, :already_added}, state}
          false ->
            new_service = %{service | listeners: [from | service.listeners]}
            new_state = %{state | services: Map.put state.services new_service}
            {:reply, service.instances, new_state}
        end
      :error ->
        new_services = Map.put state.services, service_type, %Service{listeners: [from]}
        new_state = %{state | services: new_services}
        send_query(:ptr, service_type, state.port)
        {:reply, %{}, new_state}
    end
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, handle_packet(packet, state)}
  end

  defp handle_packet(packet, state) do
    record = DNS.Record.decode(packet)
    handle_response(record.header.qr, record, state)
  end

  defp handle_response(_is_query = true, _, state), do: state
  defp handle_response(false, record, state) do
    {changed, state} = Enum.reduce(record.anlist, {[], state}, fn answer, {_changed, _state} = acc ->
      handle_answer(answer.type, answer, acc)
    end)
    Enum.uniq(changed)
    |> Enum.map(& notify_listeners(is_complete(&1, state.domains), &1, state))
    state
  end

  defp notify_listeners(false, {instance, domain}, state), do: nil
  defp notify_listeners(true, {instance_name, domain}, state) do
    %{listeners: listeners, instances: instances} = Map.fetch(domain, state.services)
    instance = Map.fetch instances, instance_name
    Enum.map(listeners, & notify_listener(&1, instance, domain, state.domains))
  end

  defp notify_listener(pid, instance, domain, domains) do
    ip = Map.fetch instance.domain, domains
    send pid, {:mdns_sd, domain, {ip, instance}}
  end

  defp is_complete(service, domains) do
    empty = %Service{}
    service.txt != empty.txt && service.port != empty.port &&
      Map.fetch(domains, service.domain) != :error
  end

  defp handle_answer(:ptr, answer, {changed, state}) do
    with {instance, domain} = service_name <- parse_instance_and_dom(answer.data),
    existing_service <- Map.fetch(state.services, domain),
    false <- Map.has_key(existing_service.instances, instance) do
      send_queries([:txt, :srv], service_name, state.port)
      new_instances = Map.put existing_service.instances, instance, %MdnsSd.Service{}
      new_service = %{existing_service | instances: new_instances}
      new_state = %{state | services: Map.put(state.services, domain, new_service)}
      {[service_name | changed], new_state}
    else
      true -> state
    end
  end
  defp handle_answer(:txt, answer, {changed, state}) do
    with {instance, domain} = service_name <- parse_instance_and_dom(answer.domain),
    existing_service <- Map.fetch(state.services, domain),
    {:ok, existing_instance} <- Map.fetch(existing_service.instances, instance),
    {:ok, new_txt_map} <- parse_txt_map(answer.data) do
      new_instances = Map.put(existing_service.instances, instance,
        %{existing_instance | txt: new_txt_map})
      new_service = %{existing_service | instances: new_instances}
      new_state = %{state | services: Map.put(state.services, domain, new_service)}
      {[service_name | changed], new_state}
    else
      true -> state
    end
  end
  defp handle_answer(:srv, answer, {changed, state}) do
    with {instance, domain} = service_name <- parse_instance_and_dom(answer.domain),
    existing_service <- Map.fetch(state.services, domain),
    {:ok, existing_instance} <- Map.fetch(existing_service.instances, instance),
    {:ok, {port, srv_domain}} <- parse_srv_data(answer.data) do
      new_instances = Map.put(existing_service.instances, instance,
        %{existing_instance | port: port, domain: srv_domain})
      new_service = %{existing_service | instances: new_instances}
      if Map.fetch(state.domains, srv_domain) == :error do
        send_query(:a, srv_domain, state.port)
      end
      new_state = %{state | services: Map.put(state.services, domain, new_service)}
      {[service_name | changed]}
    else
      true -> state
    end
  end
  defp handle_answer(:a, answer, {changed, state}) do
    {changed?, new_domains} = Map.get_and_update state.domains, answer.domain, fn domain ->
      {domain != nil && domain != answer.data, answer.data}
    end
    additional_changed = if changed? do
      Enum.flat_map state.services fn {domain, %{instances: instances}} ->
        Enum.map instances, fn {instance_name, _inst} ->
          {instance_name, domain}
        end
      end
    else
      []
    end
    {additional_changed ++ changed, %{state | domains: new_domains}}
  end
  defp handle_answer(_, state), do: state

  defp send_queries(queries, domain, port) do
    Enum.map queries, &(send_query &1, domain, port)
  end
  defp send_query(type, domain, port) do
    to_query(domain, type)
    |> send_dns_query(port)
  end

  defp to_query(domain, type) do
    %DNS.Query{
      class: :in,
      type: type,
      domain: domain
    }
  end

  defp send_dns_query(question, port) do
    packet = %DNS.Record{header: @query_header, qdlist: [question]}
    :gen_udp.send(port, @mdns_group, @mdns_port, DNS.Record.encode(packet))
  end

end
