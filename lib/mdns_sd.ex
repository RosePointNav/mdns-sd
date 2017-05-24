defmodule MdnsSd do
  @moduledoc """
  Documentation for MdnsSd.
  """
  use Application

  defmodule Service do
    defstruct [ip: nil, domain: '', txt: nil, port: 0]
  end

  def start(_type, _args) do
    MdnsSd.Supervisor.start_link
    {:ok, self()}
  end

end

defmodule MdnsSd.Supervisor do
  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    protocol = Application.get_env(:mdns_sd, :protocol, :inet)
    #local interface where services are available. For my convenience,
    #this is set on init and is the same for all services
    interface = Application.get_env(:mdns_sd, :interface, 'eth0')
    ip = ip_from_interface(interface, protocol)

    child_args = [protocol: protocol, service_ip: ip]
    children = [
      worker(MdnsSd.Server, [child_args]),
      worker(MdnsSd.Client, [child_args])
    ]

    supervise(children, strategy: :one_for_one)
  end

  defp ip_from_interface(interface, protocol) do
    {:ok, addrs} = :inet.getifaddrs()
    {^interface, data} = Enum.find addrs, fn {iface, _} ->
      iface == interface
    end
    {:addr, address} = Enum.find data, fn {k, v} ->
      k == :addr && case protocol do
        :inet -> tuple_size(v) == 4
        :inet6 -> tuple_size(v) == 8
      end
    end
    address
  end

end
