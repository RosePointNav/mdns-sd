defmodule MdnsSd.Helpers do

  def parse_ip(data) do
    case data do
      <<oct_1, oct_2, oct_3, oct_4>> ->
        {oct_1, oct_2, oct_3, oct_4}
      {_,_,_,_} = ip -> ip
    end
  end
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
