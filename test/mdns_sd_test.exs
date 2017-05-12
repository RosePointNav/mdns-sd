defmodule MdnsSdTest do
  use ExUnit.Case
  doctest MdnsSd

  setup do
    {:ok, %{}}
  end

  test "add address record" do
    MdnsSd.Server.add_addr_record('foobar.local', '10.252.154.106')
    assert true
  end
end
