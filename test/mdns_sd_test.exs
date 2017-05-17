defmodule MdnsSdTest do
  use ExUnit.Case
  doctest MdnsSd
  require Logger

  setup do
    {:ok, %{}}
  end

  test "announcing a service" do
    foo_service = %MdnsSd.Service{
      domain: 'elixirMdnsSd.local',
      txt: %{
        'nmeaname' => 'FOOFOOFOO'
      },
      port: 3000
    }
    MdnsSd.Server.add_service({'fooinstance', '_onenet-info._tcp'}, foo_service)
    Process.sleep(2000)
    assert true
  end

  test "listening for a service" do
    # start up a service
    # dns-sd -R foobar _onenet-info._tcp local nmea-name=fooname
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
