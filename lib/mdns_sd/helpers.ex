defmodule MdnsSd.Helpers do
  def parse_instance_and_dom(full_domain) do
    case Regex.run(~r/^([^\.]*)\.(.*)$/, full_domain, capture: :all_but_first) do
      [instance, domain] -> {instance, domain}
      _ -> nil
    end
  end
  def parse_srv_data(srv_charlist) do
    srv_regex = ~r/.+\s(\d+)\s(.+)\.$/
    with [port, domain] <- Regex.run(srv_regex, to_string(srv_charlist), capture: :all_but_first),
    {port, _rest} <- Integer.parse(port) do
      {port, domain}
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
