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

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(MdnsSd.Server, []),
      worker(MdnsSd.Client, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
