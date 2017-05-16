defmodule MdnsSd.Helpers do

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

  def parse_instance_and_dom(full_domain) when is_list(full_domain) do
    parse_instance_and_dom(List.to_string(full_domain))
  end
  def parse_instance_and_dom(full_domain) when is_binary(full_domain) do
    case Regex.run(~r/^([^\.]*)\.(.*)$/, full_domain, capture: :all_but_first) do
      [instance, domain] -> {to_charlist(instance), to_charlist(domain)}
      _ -> nil
    end
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

  def parse_txt_map(txt_charlist) do
    to_string(txt_charlist)
    |> String.split("\n")
    |> Enum.map(fn line ->
      case Regex.run(~r/^(.+)=(.+)$/, line, capture: :all_but_first) do
        [key, val] -> {key, val}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end
end
