defmodule MdnsSdTest do
  use ExUnit.Case
  doctest MdnsSd

  setup do
    {:ok, %{}}
  end

  test "announcing a service" do
    foo_service = %MdnsSd.Service{
      domain: 'elixir-mdns-sd.local',
      txt: %{
        'nmeaname' => 'FOOFOOFOO'
      },
      port: 3000
    }
    MdnsSd.Server.add_service({'fooinstance', '_onenet-info._tcp'}, foo_service)
    Process.sleep(3000)
    assert true
  end

  test "listening for a service" do
    assert true
  end

end
