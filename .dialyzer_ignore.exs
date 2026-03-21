[
  # MapSet opaque type false positives - Dialyzer can't properly track
  # MapSet opaque types through recursive topo_sort/visit_node functions
  ~r/lib\/phoenix_kit_sync\/web\/connections_live\.ex:.*call_without_opaque/,
  ~r/lib\/phoenix_kit_sync\/web\/connections_live\.ex:.*opaque/
]
