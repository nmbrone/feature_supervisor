defmodule FeatureSupervisor do
  @moduledoc """
  A wrapper for built-in `Supervisor` that allows starting children only if the features that they
  correspond to are enabled.
  """

  alias FeatureSupervisor.Manager

  @type child ::
          Supervisor.child_spec()
          | {module(), term()}
          | module()
          | (old_erlang_child_spec :: :supervisor.child_spec())

  @type option :: {:sync_interval, non_neg_integer()}

  @doc """
  A wrapper for `Supervisor.start_link/2`.

  The children will be split into two groups:

  * "static" - those without the `:enabled?` field or with `enabled?: true`
  * "dynamic" - those with `enabled?: (spec -> boolean())`

  Specs with `enabled?: false` will be excluded from the children.

  The "static" children will be started as usual.

  The "dynamic" children (if any) won't be started immediately but instead will be started via the
  `Supervisor.start_child/2` function by a different process (the child spec of which will be
  appended to the children) and only if the function given in the `:enabled?` field returns `true`.

  If a "dynamic" child is expected to be started/terminated later (via a feature flag, for example)
  you should provide the `sync_interval` option. Keep in mind though that this won't work with
  children where the `:restart` field is set to `:temporary` or `:transient`.
  """
  @spec start_link([child()], [Supervisor.option() | Supervisor.init_option() | option()]) ::
          {:ok, pid} | {:error, {:already_started, pid} | {:shutdown, term} | term}
  def start_link(children, options) when is_list(children) do
    children
    |> group_children()
    |> maybe_add_manager_spec(options)
    |> Supervisor.start_link(options)
  end

  @doc """
  Same as `Supervisor.child_spec/2` but allows any key in the overrides.
  """
  @spec child_spec(child(), Keyword.t()) :: map()
  def child_spec(child, overrides) do
    child
    |> Supervisor.child_spec([])
    |> Map.merge(Map.new(overrides))
  end

  @doc """
  Splits children into "static" and "dynamic" groups.

  * "static" - those without the `:enabled?` field or with `enabled?: true`
  * "dynamic" - those with `enabled?: (spec -> boolean())`

  Specs with `enabled?: false` will be excluded.
  """
  def group_children(children) do
    children
    |> Enum.reverse()
    |> Enum.reduce({[], []}, fn spec, {static, dynamic} = acc ->
      case child_spec(spec, []) do
        %{enabled?: fun} = spec when is_function(fun, 1) -> {static, [spec | dynamic]}
        %{enabled?: false} -> acc
        spec -> {[spec | static], dynamic}
      end
    end)
  end

  defp maybe_add_manager_spec({static, []}, _), do: static

  defp maybe_add_manager_spec({static, dynamic}, options) do
    static ++
      [
        Manager.child_spec(
          children: dynamic,
          sync_interval: Keyword.get(options, :sync_interval)
        )
      ]
  end
end
