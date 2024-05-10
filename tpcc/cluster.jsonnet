local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(warehouses=4, partitions=4, threads=4)
{
  local config = {
    name: "pingcap-tpcc-cluster",
    tags: ["pingcap"],    
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
  local topology = {
    global: {
      user: "systemslab-agent",
      ssh_port: 22,
      deploy_dir: config.storage + "/tidb-deploy",
      data_dir: config.storage + "/tidb-data",
      listen_host: "0.0.0.0",
      arch: "amd64",
    },
    pd_servers: [{ host: "PD_SERVER_IP"}],
    tidb_servers: [{ host: "TIDB_SERVER_IP"}],
    tikv_servers: [{ host: "TIKV_SERVER_IP"}],    
    tiflash_servers: [{ host: "TIFLASH_SERVER_IP"}],
  },
  metadata: config,
  name: config.name,
  jobs: {
    tiup_control: {
      host: {
        tags: ['pingcap', 'i3en-2xlarge-1'],    
      },       
      steps: [
        # cleaning up the data also any remaining tidb processes
        bash(        
          |||
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y || true
          |||
        ),
        systemslab.barrier('cluster-up'),
        systemslab.write_file('topology.yaml', std.manifestYamlDoc(topology, indent_array_in_object=true, quote_keys=false)),
        bash(
          |||
            sed -ie "s/PD_SERVER_IP/${PD_SERVER_ADDR}/g" topology.yaml
            echo "PD SERVER at ${PD_SERVER_ADDR}"
            sed -ie "s/TIDB_SERVER_IP/${TIDB_SERVER_ADDR}/g" topology.yaml
            echo "TIDB SERVER at ${TIDB_SERVER_ADDR}"
            sed -ie "s/TIKV_SERVER_IP/${TIKV_SERVER_ADDR}/g" topology.yaml
            echo "TIKV SERVER at ${TIKV_SERVER_ADDR}"
            sed -ie "s/TIFLASH_SERVER_IP/${TIFLASH_SERVER_ADDR}/g" topology.yaml
            echo "TIFLASH SERVER at ${TIFLASH_SERVER_ADDR}"
          |||
        ),
        systemslab.upload_artifact('topology.yaml'),
        bash('~/.tiup/bin/tiup cluster check ./topology.yaml --user systemslab-agent | tee tiup_check_log'),
        systemslab.upload_artifact('tiup_check_log'),
        bash('~/.tiup/bin/tiup cluster deploy systemslab-test v8.0.0 ./topology.yaml --user systemslab-agent -y --ignore-config-check | tee tiup_deploy_log'),
        systemslab.upload_artifact('tiup_deploy_log'),
        bash('~/.tiup/bin/tiup cluster start systemslab-test --init -y | tee tiup_start_log'),
        systemslab.upload_artifact('tiup_start_log'),
        systemslab.barrier('tpcc-start'),
        bash(
          |||
            WAREHOUSES=%s
            PARTITIONS=%s
            DURATION=%s
            INTERVAL=%s
            THREADS=%s
            DB_PASSWORD=`cat tiup_start_log | grep -oP "(?<=The new password is: ').*(?=')"`
            time ~/.tiup/bin/tiup bench tpcc --warehouses $WAREHOUSES --parts $PARTITIONS prepare -T $THREADS -H ${TIDB_SERVER_ADDR} -P 4000 -p ${DB_PASSWORD}
            ~/.tiup/bin/tiup bench tpcc --warehouses $WAREHOUSES --time $DURATION --interval $INTERVAL -H ${TIDB_SERVER_ADDR} -P 4000 -p ${DB_PASSWORD} --output json run | tee tpcc.json
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y
          ||| % [config.warehouses, config.partitions, config.duration, config.interval, config.threads]
        ),
        systemslab.upload_artifact('tpcc.json'), 
        systemslab.barrier('tpcc-end'),
      ],
    },    
    pd_server: {
      host: {
        tags: config.tags,
      },
      steps: [
        systemslab.barrier('cluster-up'),
        systemslab.barrier('tpcc-start'),
        systemslab.barrier('tpcc-end'),
      ],
    },
    tidb_server: {
      host: {
        tags: config.tags,
      },
      steps : [
        systemslab.barrier('cluster-up'),
        systemslab.barrier('tpcc-start'),
        systemslab.barrier('tpcc-end'),       
      ],
    },
    tikv_server: {
      host: {
        tags: config.tags,
      },
      steps : [
        systemslab.barrier('cluster-up'),
        systemslab.barrier('tpcc-start'),
        systemslab.barrier('tpcc-end'),
      ],
    }, 
    tiflash_server: {
      host: {
        tags: config.tags,
      },
      steps : [
        systemslab.barrier('cluster-up'),
        systemslab.barrier('tpcc-start'),
        systemslab.barrier('tpcc-end'),
      ],
    },         
  }
}