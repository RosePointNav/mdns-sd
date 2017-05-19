defmodule MdnsSd.Client do
  @moduledoc """
  queries services available over MDNS
  TODO
  -make sure query header contains the appropriate values
  """
  use GenServer
  import MdnsSd.Helpers
  require Logger

  @informant MdnsSd
  @mdns_port 5353
  @query_header %DNS.Header{
    aa: true,
    qr: false,
    opcode: 0,
    rcode: 0,
  }

  #services is a Map where key is {service_type, domain}, value is %Service{}
  #domains is a map where key is domain name, value is ip address
  defmodule State do
    defstruct [port: 0, instances: %{}, domains: %{}, types: [], protocol: nil]
  end
  defmodule Instance do
    defstruct [informant: nil, data: %MdnsSd.Service{}]
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Client)
  end

  def init(args) do
    {:ok, _pid} = Informant.start_link(@informant)
    {:ok, udp_pid} = case args[:protocol] do
      :inet -> open_inet_port()
      :inet6 -> open_inet6_port(Application.get_env :mdns_sd, :interface)
    end
    {:ok, %State{port: udp_pid, protocol: args[:protocol]}}
  end

  def listen(service_type) when is_list(service_type) do
    GenServer.call(Client, {:listen, service_type})
    Informant.subscribe(@informant, {service_type, :_})
  end

  def handle_call({:listen, service_type}, _, state) do
    if Enum.member? state.types, service_type do
      {:reply, :already_listening, state}
    else
      send_query(:ptr, '#{service_type}.local', state.port, state.protocol)
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

  defp handle_response(_is_resp = false, _, state), do: state
  defp handle_response(true, record, state) do
    arlist = try do
      Enum.map(record.arlist, &DNS.Resource.from_record/1)
    rescue
      e in FunctionClauseError ->
        Logger.warn "Error decoding additional response packet: #{Exception.format :error, e}"
        []
    end
    {changed, state} = Enum.reduce(record.anlist ++ arlist, {[], state}, fn answer, {_, _} = acc ->
      handle_answer(answer.type, answer, acc)
    end)
    Enum.uniq(changed)
    |> Enum.map(& publish_changes(is_complete(&1, state), &1, state))
    state
  end

  defp publish_changes(false = _complete?, _, _), do: nil
  defp publish_changes(true, name, state) do
    %{data: data, informant: informant} = Map.fetch!(state.instances, name)
    new_state = %{data | ip: Map.get(state.domains, data.domain)}
    Informant.update(informant, new_state)
  end

  defp is_complete(instance_name, %{domains: domains, instances: instances}) do
    case Map.fetch(instances, instance_name) do
      {:ok, instance} ->
        data = instance.data
        empty = %Instance{}.data
        data.txt != empty.txt && data.port != empty.port &&
        Map.fetch(domains, data.domain) != :error
      :error ->
        false
    end
  end

  defp handle_answer(:ptr, answer, {changed, state} = acc) do
    with {instance, domain} = service_name <- parse_instance_and_service(answer.data),
    true <- Enum.member?(state.types, domain),
    false <- Map.has_key?(state.instances, service_name) do
      send_queries([:txt, :srv], '#{instance}.#{domain}.local', state.port, state.protocol)
      {:ok, informant} = Informant.publish(@informant, {domain, instance}, state: %{})
      instance = %Instance{informant: informant}
      new_instances = Map.put state.instances, service_name, instance
      {[service_name | changed], %{state | instances: new_instances}}
    else
      _ -> acc
    end
  end
  defp handle_answer(:txt, answer, {changed, state} = acc) do
    with {_, service} = name <- parse_instance_and_service(answer.domain),
    true <- Enum.member?(state.types, service),
    {:ok, existing_instance} <- Map.fetch(state.instances, name) do
      new_data = %{existing_instance.data | txt: parse_txt_map(answer.data)}
      new_instance = %{existing_instance | data: new_data}
      new_instances = Map.put state.instances, name, new_instance
      {[name | changed], %{state | instances: new_instances}}
    else
      _ -> acc
    end
  end
  defp handle_answer(:srv, answer, {changed, state} = acc) do
    with {_, service} = name <- parse_instance_and_service(answer.domain),
    true <- Enum.member?(state.types, service),
    {:ok, existing_instance} <- Map.fetch(state.instances, name),
    {_pri, _weight, port, srv_domain} <- answer.data do
      new_data = Map.merge(existing_instance.data, %{port: port, domain: srv_domain})
      new_instances = Map.put state.instances, name, %{existing_instance | data: new_data}
      if Map.fetch(state.domains, srv_domain) == :error do
        send_query(:a, srv_domain, state.port, state.protocol)
      end
      state = %{state | instances: new_instances}
      {[name | changed], state}
    else
      _ -> acc
    end
  end
  defp handle_answer(:a, answer, {_, %{protocol: :inet}} = acc) do
    register_ip(answer.data, answer.domain, acc)
  end
  defp handle_answer(:aaaa, answer, {_, %{protocol: :inet6}} = acc) do
    register_ip(answer.data, answer.domain, acc)
  end
  defp handle_answer(_, _, acc), do: acc

  def register_ip(ip, domain, {changed, state}) do
    answer_ip = parse_ip(ip)
    {changed?, new_domains} = Map.get_and_update state.domains, domain, fn ip ->
      {ip != nil && ip != answer_ip, answer_ip}
    end
    additional_changed = if changed? do
      Enum.filter_map(state.instances, fn {_name, instance} ->
        domain == Map.get instance.data, :domain
      end, (&elem(&1, 0)))
    else
      []
    end
    {additional_changed ++ changed, %{state | domains: new_domains}}
  end

  defp send_queries(queries, domain, port, protocol) do
    Enum.map queries, &(send_query &1, domain, port, protocol)
  end
  defp send_query(type, domain, port, protocol) do
    to_query(domain, type)
    |> send_dns_query(port, protocol)
  end

  defp to_query(domain, type) do
    %DNS.Query{
      class: :in,
      type: type,
      domain: domain
    }
  end

  defp send_dns_query(question, port, protocol) do
    packet = %DNS.Record{header: @query_header, qdlist: [question]}
    :gen_udp.send(port, mdns_group(protocol), @mdns_port, DNS.Record.encode(packet))
  end

end
