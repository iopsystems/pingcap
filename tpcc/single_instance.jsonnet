local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(warehouses=4, partitions=4, threads=4)
{
  local config = {
    name: "pingcap-tpcc",
    tags: ["pingcap","i3en-2xlarge-1"],
    warehouses: warehouses,
    partitions: partitions,
    threads: threads,
    storage: "/mnt/localssd-1",
    interval: "10s",
    duration: "60s",
    parameters: {
      warehouses: warehouses,
      partitions: partitions,
      threads: threads,
      ec2: 'i3en-2xlarge',
    }
  },
  metadata: config,
  name: config.name,
  jobs: {
    tiup_control: {
      host: {
        tags: config.tags,    
      },
      steps: [
        bash(
          |||        
            # prepare the storage        
            source ~/.profile
            STORAGE_DIR=%s/systemslab
            TAG_DIR=~/.tiup/data/systemslab
            rm -rf $STORAGE_DIR
            rm -rf $TARGET_DIR
            mkdir -p $STORAGE_DIR
            mkdir -p ~/.tiup/data || true
            ln -s $STORAGE_DIR $TAG_DIR
            ls -li $TAG_DIR
            tiup playground --tag systemslab > playground.log 2>&1&
            while [ "`grep -o 'TiDB Playground Cluster is started' ./playground.log || true`" == "" ]; do sleep 10; tiup status; done
          ||| % [config.storage]
        ),
        systemslab.barrier('tiup-up'),
        bash(
          |||
            # prepare tpcc
            source ~/.profile
            WAREHOUSES=%s
            PARTITIONS=%s
            pwd
            which tiup
            tiup bench tpcc --warehouses $WAREHOUSES --parts $PARTITIONS prepare -T 8
          ||| % [config.warehouses, config.partitions]
        ),
        systemslab.barrier('tpcc-ready'),
        bash(
          |||
            # run tpcc
            source ~/.profile
            WAREHOUSES=%s
            DURATION=%s
            INTERVAL=%s
            THREADS=%s
            time tiup bench tpcc -T $THREADS --warehouses $WAREHOUSES --time $DURATION --interval $INTERVAL --output json run
          ||| % [config.warehouses, config.duration, config.interval, config.threads]
        ),
        systemslab.barrier('tpcc-finish'),
        bash(
          |||
            source ~/.profile
            pkill tiup-playground || true
            sleep 10
            ps -A | grep tiup || true
          |||
        )
      ],
    }
  }
}