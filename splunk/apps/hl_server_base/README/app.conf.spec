# Declares the role-owned marker stanza, so `splunk btool check` knows it (spec §5.5). It applies
# to every app that carries the marker (hl_server_base, hl_data_health).
[hl]
managed = <boolean>
* true marks an app the homelab_splunk role installed and may remove.
