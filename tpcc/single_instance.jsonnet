local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function()
{
  local config = {
    name: "pingcap-tpcc",
    tags: ["pingcap"],
    warehouses: 4,
    topics: 10,
  },
  name: config.name,
  host: {
    tags: config.tags,    
  },
  steps: [
    bash(
      |||
        # start the pingcap services
      ||| % [config.warehouses, config.topics]
    )
  ]
}