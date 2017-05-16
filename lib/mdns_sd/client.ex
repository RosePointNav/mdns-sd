defmodule Client do
  @moduledoc """
  queries services available over MDNS
  TODO
  -make sure query header contains the appropriate values
  -Process.monitor listener
  """
  use GenServer
  import MdnsSd.Helpers

  @informant MdnsSd
  @mdns_group {224,0,0,251}
  @mdns_port 5353
  @query_header %DNS.Header{
    aa: true,
    qr: true,
    opcode: 0,
    rcode: 0,
  }

  #services is a Map where key is {service_type, domain}, value is %Service{}
  #domains is a map where key is domain name, value is ip address
  defmodule State do
    defstruct [port: 0, instances: %{}, domains: %{}, types: []]
  end
  defmodule Instance do
    defstruct [informant: nil, data: %MdnsSd.Service{}]
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
    {:ok, _pid} = Informant.start_link(@informant)
    {:ok, udp_pid} = :gen_udp.open(5353, udp_options)
    {:ok, %State{port: udp_pid}}
  end

  def listen(service_type) when is_list(service_type) do
    GenServer.call(Client, {:listen, service_type})
    Informant.subscribe(@informant, {service_type, :_})
  end

  def handle_call({:listen, service_type}, _, state) do
    if Enum.member? state.types, service_type do
      {:reply, :already_listening, state}
    else
      send_query(:ptr, service_type, state.port)
      new_state = %{state | types: [service_type | state.types]}
      {:reply, :started_listening, new_state}
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
    |> Enum.map(& publish_changes(is_complete(&1, state.domains), &1, state))
    state
  end

  defp publish_changes(false = _complete?, _, _), do: nil
  defp publish_changes(true, name, state) do
    %{data: data, informant: informant} = Map.fetch!(state.instances, name)
    new_state = %{data | ip: Map.get(state.domains, data.domain)}
    Informant.update(informant, new_state)
  end

  defp is_complete(service, domains) do
    empty = %Instance{}
    service.txt != empty.txt && service.port != empty.port &&
      Map.fetch(domains, service.domain) != :error
  end

  defp handle_answer(:ptr, answer, {changed, state}) do
    with {instance, domain} = service_name <- parse_instance_and_dom(answer.data),
    true <- Enum.member?(state.types, domain),
    false <- Map.has_key?(state.instances, service_name) do
      send_queries([:txt, :srv], service_name, state.port)
      {:ok, informant} = Informant.publish(@informant, {domain, instance}, state: %{})
      instance = %Instance{informant: informant}
      new_instances = Map.put state.instances, service_name, instance
      {[service_name | changed], %{state | instances: new_instances}}
    else
      true -> state
    end
  end
  defp handle_answer(:txt, answer, {changed, state}) do
    with {_, domain} = service_name <- parse_instance_and_dom(answer.domain),
    true <- Enum.member?(state.types, domain),
    {:ok, existing_instance} <- Map.fetch(state.instances, service_name),
    {:ok, new_txt_map} <- parse_txt_map(answer.data) do
      new_data = Map.put(existing_instance.data, :txt, new_txt_map)
      new_instance = %{existing_instance | data: new_data}
      new_instances = Map.put state.instances, service_name, new_instance
      state = %{state | instances: new_instances}
      {[service_name | changed], state}
    else
      true -> state
    end
  end
  defp handle_answer(:srv, answer, {changed, state}) do
    with {_, domain} = service_name <- parse_instance_and_dom(answer.domain),
    true <- Enum.member?(state.types, domain),
    {:ok, existing_instance} <- Map.fetch(state.instances, service_name),
    {:ok, {port, srv_domain}} <- parse_srv_data(answer.data) do
      new_data = Map.merge(existing_instance.data, %{port: port, domain: srv_domain})
      new_instances = Map.put state.instances, service_name, %{existing_instance | data: new_data}
      if Map.fetch(state.domains, srv_domain) == :error do
        send_query(:a, srv_domain, state.port)
      end
      state = %{state | instances: new_instances}
      {[service_name | changed], state}
    else
      true -> state
    end
  end
  defp handle_answer(:a, answer, {changed, state}) do
    {changed?, new_domains} = Map.get_and_update state.domains, answer.domain, fn domain ->
      {domain != nil && domain != answer.data, answer.data}
    end
    additional_changed = if changed? do
      Enum.filter_map(state.instances, fn {_name, instance} ->
        answer.domain == Map.get instance.data, :domain
      end, (&elem(&1, 0)))
    else
      []
    end
    {additional_changed ++ changed, %{state | domains: new_domains}}
  end
  defp handle_answer(_, _, state), do: state

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
