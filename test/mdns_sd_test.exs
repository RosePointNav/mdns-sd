defmodule MdnsSdTest do
  use ExUnit.Case
  doctest MdnsSd

  setup do
    {:ok, %{}}
  end

  test "announcing a service" do
    MdnsSd.Server.add_addr_record('foobar.local', '10.252.154.106')
    foo_service = %MdnsSd.Service{
      domain: 'foobar.local',
      txt: %{
        'nmea-name' => 'FOOFOOFOO'
      },
      port: 3000
    }
    MdnsSd.Server.add_service({'fooinstance', '_pgn-transport._udp.local'}, foo_service)
    assert true
  end

  test "listening for a service" do
    assert true
  end

end
