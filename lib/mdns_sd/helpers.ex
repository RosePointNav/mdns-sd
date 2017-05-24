defmodule MdnsSd.Helpers do

  def open_inet_port do
    udp_options = [
      :binary,
      active: true,
      add_membership: {{224,0,0,251}, {0,0,0,0}},
      multicast_loop:  true,
      multicast_ttl:   255,
      reuseaddr:       true
    ]
    :gen_udp.open(5353, udp_options)
  end

  #utility for opening an ipv6 udp port subscribed to provided address
  #due to hard-coded headers and its reliance on ip link, only works on linux
  def open_inet6_port(interface) do
    ifindex_res = :os.cmd('ip link show #{interface}') |> to_string()
    [ifindex] = Regex.run(~r/(^\d*):/, ifindex_res, capture: :all_but_first)
    {ifindex, _} = Integer.parse(ifindex)

    udp_options = [
      :binary,
      :inet6,
      active: true,
      reuseaddr: true
    ]
    {:ok, pid} = :gen_udp.open(5353, udp_options)

    ifindex = <<ifindex::32-native>>
    ipproto_ipv6 = 41
    ipv6_join_group = 20
    :ok = :inet.setopts(pid, [{:raw, ipproto_ipv6, ipv6_join_group, address <> ifindex}])
    {:ok, pid}
  end

  def mdns_group(:inet6), do: {0xFF02, 0, 0, 0, 0, 0, 0, 0xFB}
  def mdns_group(:inet), do: {224,0,0,251}

  def parse_ip(<<oct_1, oct_2, oct_3, oct_4>>), do: {oct_1, oct_2, oct_3, oct_4}
  def parse_ip({_,_,_,_} = ip), do: ip
  def parse_ip(<<s1::16, s2::16, s3::16, s4::16, s5::16, s6::16, s7::16, s8::16>>) do
    {s1, s2, s3, s4, s5, s6, s7, s8}
  end
  def parse_ip({_,_,_,_,_,_,_,_} = ip), do: ip

  def trunc_local(domain) do
    Regex.replace(~r/\.local$/, to_string(domain), "")
    |> String.to_charlist
  end

  def to_labels(domain_name) do
    domain_name =
      to_string(domain_name)
      |> String.split(".")
      |> Enum.map(& <<byte_size(&1)>> <> &1)
      |> Enum.join()
    domain_name <> <<0>>
  end

  def parse_instance_and_service(full_domain) when is_list(full_domain) do
    parse_instance_and_service(List.to_string(full_domain))
  end
  def parse_instance_and_service(full_domain) when is_binary(full_domain) do
    case Regex.run(~r/^([^\.]*)\.(.*)\.local$/, full_domain, capture: :all_but_first) do
      [instance, domain] -> {to_charlist(instance), to_charlist(domain)}
      _ -> nil
    end
  end

  def parse_srv_data(srv_charlist) do
    srv_regex = ~r/.+\s(\d+)\s(.+)\.$/
    with [port, domain] <- Regex.run(srv_regex, to_string(srv_charlist), capture: :all_but_first),
    {port, _rest} <- Integer.parse(port) do
      {port, to_charlist(domain)}
    else
      true -> :error
    end
  end

  def parse_txt_map(txt_list) do
    Enum.map(txt_list, fn line ->
      case Regex.run(~r/^(.+)=(.+)$/, to_string(line), capture: :all_but_first) do
        [key, val] -> {to_charlist(key), to_charlist(val)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end

end
