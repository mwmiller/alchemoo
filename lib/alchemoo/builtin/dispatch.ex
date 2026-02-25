defmodule Alchemoo.Builtins.Dispatch do
  @moduledoc """
  Dispatches built-in function calls to their implementations.
  """
  alias Alchemoo.Value
  import Alchemoo.Builtins.Macros
  require Logger

  @doc """
  Dispatches a built-in function call.
  Returns `{:ok, value, new_env}` or `{:error, reason}`.
  """
  def call(name, args, env)

  # Special built-ins that handle their own environment or are implemented in Builtins module
  def call(:pass, args, env), do: Alchemoo.Builtins.pass_fn(args, env)
  def call(:call_function, args, env), do: Alchemoo.Builtins.call_function(args, env)
  def call(:eval, args, env), do: Alchemoo.Builtins.eval_fn(args, env)
  def call(:match_object, args, env), do: Alchemoo.Builtins.match_object_fn(args, env)

  # Type conversion
  defbuiltin(:typeof)
  defbuiltin(:tostr)
  defbuiltin(:toint)
  defbuiltin(:tonum, :toint)
  defbuiltin(:toobj)
  defbuiltin(:toliteral)

  # List operations
  defbuiltin(:length, :length_fn)
  defbuiltin(:is_member, :member?)
  defbuiltin(:listappend)
  defbuiltin(:listinsert)
  defbuiltin(:listdelete)
  defbuiltin(:listset)
  defbuiltin(:setadd)
  defbuiltin(:setremove)
  defbuiltin(:sort, :sort_fn)
  defbuiltin(:reverse, :reverse_fn)

  # Comparison
  defbuiltin(:equal)

  # Math
  defbuiltin(:random, :random_fn)
  defbuiltin(:min, :min_fn)
  defbuiltin(:max, :max_fn)
  defbuiltin(:abs, :abs_fn)
  defbuiltin(:sqrt, :sqrt_fn)
  defbuiltin(:sin, :sin_fn)
  defbuiltin(:cos, :cos_fn)
  defbuiltin(:tan, :tan_fn)
  defbuiltin(:sinh, :sinh_fn)
  defbuiltin(:cosh, :cosh_fn)
  defbuiltin(:tanh, :tanh_fn)
  defbuiltin(:asin, :asin_fn)
  defbuiltin(:acos, :acos_fn)
  defbuiltin(:atan, :atan_fn)
  defbuiltin(:atan2, :atan2_fn)
  defbuiltin(:exp, :exp_fn)
  defbuiltin(:log, :log_fn)
  defbuiltin(:log10, :log10_fn)
  defbuiltin(:ceil, :ceil_fn)
  defbuiltin(:floor, :floor_fn)
  defbuiltin(:trunc, :trunc_fn)
  defbuiltin(:floatstr)

  # Time
  defbuiltin(:time, :time_fn)
  defbuiltin(:ctime, :ctime_fn)

  # Output/Communication
  defbuiltin(:notify)
  defbuiltin(:notify_except, :notify_except_fn)
  defbuiltin(:connected_players)
  defbuiltin(:connection_name)
  defbuiltin(:boot_player)
  defbuiltin(:flush_input, :flush_input_fn)
  defbuiltin(:read, :read_fn)
  defbuiltin(:connection_options)
  defbuiltin(:connection_option)
  defbuiltin(:set_connection_option)
  defbuiltin(:output_delimiters)
  defbuiltin(:set_output_delimiters)
  defbuiltin(:buffered_output_length)

  # Context
  defbuiltin(:player, :player_fn)
  defbuiltin(:caller, :caller_fn)
  defbuiltin(:this, :this_fn)
  defbuiltin(:is_player, :player?)
  defbuiltin(:is_wizard, :wizard?)
  defbuiltin(:players, :players_fn)
  defbuiltin(:set_player_flag)
  defbuiltin(:check_password, :check_password_fn)

  # String operations
  defbuiltin(:index, :index_fn)
  defbuiltin(:rindex, :rindex_fn)
  defbuiltin(:strsub)
  defbuiltin(:strcmp)
  defbuiltin(:explode)
  defbuiltin(:substitute)
  defbuiltin(:match, :match_fn)
  defbuiltin(:rmatch, :rmatch_fn)
  defbuiltin(:decode_binary)
  defbuiltin(:encode_binary)
  defbuiltin(:crypt)
  defbuiltin(:binary_hash)
  defbuiltin(:value_hash, :value_hash_fn)

  # Object operations
  defbuiltin(:valid)
  defbuiltin(:parent, :parent_fn)
  defbuiltin(:children)
  defbuiltin(:max_object)
  defbuiltin(:chown)
  defbuiltin(:renumber)
  defbuiltin(:reset_max_object)

  # Property operations
  defbuiltin(:properties)
  defbuiltin(:property_info)
  defbuiltin(:get_property)
  defbuiltin(:set_property)
  defbuiltin(:add_property)
  defbuiltin(:delete_property)
  defbuiltin(:set_property_info)
  defbuiltin(:is_clear_property, :clear_property?)
  defbuiltin(:clear_property)

  # Object management
  defbuiltin(:create)
  defbuiltin(:recycle)
  defbuiltin(:chparent)
  defbuiltin(:move)

  # Verb management
  defbuiltin(:verbs)
  defbuiltin(:verb_info)
  defbuiltin(:set_verb_info)
  defbuiltin(:verb_args)
  defbuiltin(:set_verb_args)
  defbuiltin(:verb_code)
  defbuiltin(:add_verb)
  defbuiltin(:delete_verb)
  defbuiltin(:set_verb_code)
  defbuiltin(:function_info)
  defbuiltin(:disassemble)

  # Task management
  defbuiltin(:suspend, :suspend_fn)
  defbuiltin(:yield, :yield_fn)
  defbuiltin(:task_id)
  defbuiltin(:queued_tasks)
  defbuiltin(:kill_task)
  defbuiltin(:resume, :resume_fn)
  defbuiltin(:task_stack)
  defbuiltin(:queue_info)
  defbuiltin(:raise, :raise_fn)

  # Security
  defbuiltin(:caller_perms)
  defbuiltin(:set_task_perms)
  defbuiltin(:callers, :callers_fn)

  # Network
  defbuiltin(:idle_seconds)
  defbuiltin(:connected_seconds)
  defbuiltin(:listen)
  defbuiltin(:unlisten)
  defbuiltin(:open_network_connection)

  # Server management
  defbuiltin(:server_version)
  defbuiltin(:server_log)
  defbuiltin(:shutdown)
  defbuiltin(:memory_usage)
  defbuiltin(:db_disk_size)
  defbuiltin(:dump_database)
  defbuiltin(:server_started)

  # Utilities
  defbuiltin(:force_input)
  defbuiltin(:read_binary)
  defbuiltin(:object_bytes)
  defbuiltin(:value_bytes)
  defbuiltin(:ticks_left)
  defbuiltin(:seconds_left)

  # Catch-all for unknown builtins
  def call(_name, _args, env) do
    {:ok, Value.err(:E_VERBNF), env}
  end
end
