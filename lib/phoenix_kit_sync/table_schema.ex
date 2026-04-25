defmodule PhoenixKitSync.TableSchema do
  @moduledoc """
  Struct representing a database table's schema information.

  Returned by `SchemaInspector.fetch_table_schema/2` and consumed by
  `DataImporter`, `DataExporter`, sync LiveViews, and the wire protocol.

  ## Fields

  - `table` - Table name
  - `schema` - PostgreSQL schema (e.g., `"public"`)
  - `columns` - List of `ColumnInfo` structs
  - `primary_key` - List of primary key column names
  """

  alias PhoenixKitSync.ColumnInfo

  # Jason.Encoder is required because the WebSocket sync protocol pushes
  # the schema struct directly through Phoenix.Channel.push/3 (which
  # JSON-encodes the payload). Without this derive, any
  # `request:schema` event crashes the channel with
  # `Protocol.UndefinedError`.
  @derive Jason.Encoder
  @enforce_keys [:table, :schema]
  defstruct [:table, :schema, columns: [], primary_key: []]

  @type t :: %__MODULE__{
          table: String.t(),
          schema: String.t(),
          columns: [ColumnInfo.t()],
          primary_key: [String.t()]
        }
end
