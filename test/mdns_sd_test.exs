defmodule MdnsSdTest do
  @moduledoc """
  TODO:
  -actually incorporate avahi command line calls into test
  """
  use ExUnit.Case
  doctest MdnsSd
  require Logger

  setup do
    {:ok, %{}}
  end

  @tag timeout: 10000000
  @doc """
  this should resolve `avahi-browse -rt _onenet-info._tcp`
  """
  test "announcing a service" do
    foo_service = %MdnsSd.Service{
      domain: 'elixir_mdns_sd.local',
      txt: %{
        'nmeaname' => 'FOOFOOFOO'
      },
      port: 3000
    }
    MdnsSd.Server.add_service({'fooinstance', '_onenet-info._tcp'}, foo_service)
    # Process.sleep(:infinity)
    assert true
  end

  @doc """
  this should log service details after running
  avahi-publish-service -a johnnydev.local fe80::21c:42ff:fe56:ea5b
  avahi-publish-service -H johnnydev.local -s barinstance _onenet-info._tcp 3333 foo=baz
  """
  test "listening for a service" do
    MdnsSd.Client.listen('_onenet-info._tcp')
    Process.sleep(2000)
    msgs = fetch([])
    Logger.info(inspect msgs, limit: 300)
    assert true
  end

  defp fetch(existing) do
    receive do
      msg ->
        fetch([msg | existing])
    after
      100 -> existing
    end
  end

end
